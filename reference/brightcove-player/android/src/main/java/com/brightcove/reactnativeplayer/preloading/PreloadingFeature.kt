package com.brightcove.reactnativeplayer.preloading

import com.brightcove.player.edge.Catalog
import com.brightcove.player.edge.CatalogError
import com.brightcove.player.edge.VideoListener
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.player.network.HttpRequestConfig
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerErrorClassifier
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Resolves preloadVideoId in the background while the current source plays,
 * and inserts it into the native SDK's own queue (BrightcoveExoPlayerVideoView)
 * directly behind the currently playing video — the same queue mechanism
 * PlaylistsFeature uses for its whole queue, here used for a single ad-hoc
 * "next video" the SDK's own end-of-item advancement will switch to on its
 * own. This is deliberately not a claimsSourceLoading feature: preloading
 * augments whatever source is already loaded (single video, queue, or
 * anything else), rather than replacing how the current source is resolved.
 *
 * The current video may not be loaded yet when preloadVideoId is first set
 * (e.g. both are set in the same initial transaction) — queuing before the
 * core's own video would make the preload the first, actually-playing item.
 * pendingStart defers the fetch until DID_SET_VIDEO reports the current
 * video is already in the native queue.
 */
class PreloadingFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var preloadVideoId = ""
  private var pendingStart = false
  private var activeGeneration = 0
  private var queuedVideoId: String? = null
  private var previousVideoIdAtQueueTime: String? = null

  override val ownedProps = setOf("preloadVideoId")

  override val exportedEvents = mapOf(
    EVENT_PRELOAD_QUEUED to "onPreloadQueued",
    EVENT_PRELOAD_HANDOFF to "onPreloadHandoff",
    EVENT_PRELOAD_ERROR to "onPreloadError",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    check(name == "preloadVideoId") { "PreloadingFeature does not own prop '$name'" }
    val newValue = (value as? String)?.trim() ?: ""
    if (newValue == preloadVideoId) return

    cancelAndDequeuePreload()
    preloadVideoId = newValue
    if (newValue.isEmpty()) return

    if (host.videoView.currentVideo != null) {
      startPreload()
    } else {
      pendingStart = true
    }
  }

  override fun onSourceReset() {
    // Kill the in-flight request but KEEP the configured preloadVideoId:
    // React Native does not resend an unchanged prop after a source swap,
    // so clearing it here would permanently stop background preloading for
    // the rest of the session. The value re-arms the next preload cycle.
    invalidatePendingPreload()
  }

  override fun onDispose() {
    invalidatePendingPreload()
  }

  override fun onRegisterPlaybackListeners() {
    host.registerListener(EventType.DID_SET_VIDEO) { event -> onDidSetVideo(event) }
  }

  private fun onDidSetVideo(event: Event) {
    checkForHandoff(event)
    if (pendingStart && preloadVideoId.isNotEmpty()) {
      pendingStart = false
      startPreload()
    }
  }

  private fun checkForHandoff(event: Event) {
    val queued = queuedVideoId ?: return
    val newVideo = event.properties[Event.VIDEO] as? Video ?: return
    val newId = newVideo.id?.ifBlank { null } ?: return
    if (newId != queued) return

    host.emitEvent(
      EVENT_PRELOAD_HANDOFF,
      Arguments.createMap().apply {
        putString("previousVideoId", previousVideoIdAtQueueTime ?: "")
        putString("currentVideoId", newId)
      },
    )
    queuedVideoId = null
    previousVideoIdAtQueueTime = null
    // The preload slot is consumed: a caller must set a fresh preloadVideoId
    // to preload the next-next video, matching the TS contract's "this is for
    // the next video, not the one already playing".
    preloadVideoId = ""
  }

  private fun startPreload() {
    val accountId = host.accountId
    val policyKey = host.policyKey
    if (accountId.isNullOrBlank() || policyKey.isNullOrBlank()) return

    val generation = ++activeGeneration
    val targetId = preloadVideoId
    val catalog = Catalog.Builder(host.eventEmitter, accountId)
      .setPolicy(policyKey)
      .build()
    catalog.findVideoByID(
      targetId,
      HttpRequestConfig.empty(),
      object : VideoListener() {
        override fun onVideo(video: Video) {
          if (generation != activeGeneration || targetId != preloadVideoId || host.isDisposed) return

          try {
            previousVideoIdAtQueueTime = host.videoView.currentVideo?.id?.ifBlank { null }
            // Insert right after the playing item, so the preload is what the
            // SDK plays next — the contract's "starts instantly once the
            // current video ends", as on iOS and web. Appending would queue it
            // behind every remaining videoIds item instead.
            // Tag the inserted item with the generation active at insert time
            // (the fetch may have started under an older one): the core's
            // lifecycle guards and feature event scopes (ads) key off the tag,
            // so an untagged inserted video would have its ad events dropped.
            host.videoView.add(
              host.videoView.currentIndex + 1,
              host.tagVideoForCurrentRequest(video),
            )
            queuedVideoId = video.id?.ifBlank { null } ?: targetId
            host.emitEvent(
              EVENT_PRELOAD_QUEUED,
              Arguments.createMap().apply { putString("videoId", targetId) },
            )
          } catch (e: Exception) {
            emitPreloadError(targetId, "playback", e.javaClass.simpleName, e.message ?: "Failed to queue preloaded video")
          }
        }

        override fun onError(errors: List<CatalogError>) {
          if (generation != activeGeneration || targetId != preloadVideoId || host.isDisposed) return
          emitCatalogError(targetId, errors.firstOrNull())
        }

        override fun onError(error: String) {
          if (generation != activeGeneration || targetId != preloadVideoId || host.isDisposed) return
          emitPreloadError(targetId, "unknown", "catalog_error", error.ifBlank { "Unable to retrieve the Brightcove video" })
        }
      },
    )
  }

  /**
   * Invalidates in-flight state without touching the native queue (source
   * reset/dispose: the core is already tearing the whole queue down itself).
   */
  private fun invalidatePendingPreload() {
    activeGeneration++
    pendingStart = false
    queuedVideoId = null
    previousVideoIdAtQueueTime = null
  }

  /**
   * A new preloadVideoId superseded a previous one: also remove the stale
   * video from the native queue if it was already added but never played.
   */
  private fun cancelAndDequeuePreload() {
    val queued = queuedVideoId
    invalidatePendingPreload()
    if (queued == null) return
    if (host.videoView.currentVideo?.id == queued) return
    val index = host.videoView.list.indexOfFirst { it.id == queued }
    if (index >= 0) host.videoView.remove(index)
  }

  private fun emitCatalogError(videoId: String, error: CatalogError?) {
    val throwable = error?.throwable
    val catalogCode = error?.catalogErrorCode?.ifBlank { null }

    if (catalogCode == null && throwable != null) {
      emitPreloadError(
        videoId,
        code = if (throwable is java.io.IOException) "network" else "unknown",
        nativeCode = throwable.javaClass.simpleName,
        message = throwable.localizedMessage
          ?: error.message?.ifBlank { null }
          ?: "Unable to retrieve the Brightcove video",
      )
      return
    }

    val nativeCode = catalogCode ?: "catalog_error"
    emitPreloadError(
      videoId,
      code = PlayerErrorClassifier.catalogErrorCategory(nativeCode),
      nativeCode = nativeCode,
      message = error?.message?.ifBlank { null } ?: "Unable to retrieve the Brightcove video",
    )
  }

  private fun emitPreloadError(videoId: String, code: String, nativeCode: String, message: String) {
    host.emitEvent(
      EVENT_PRELOAD_ERROR,
      Arguments.createMap().apply {
        putString("videoId", videoId)
        putString("code", code)
        putString("nativeCode", nativeCode)
        putString("message", message)
      },
    )
  }

  companion object {
    const val EVENT_PRELOAD_QUEUED = "topPreloadQueued"
    const val EVENT_PRELOAD_HANDOFF = "topPreloadHandoff"
    const val EVENT_PRELOAD_ERROR = "topPreloadError"
  }
}
