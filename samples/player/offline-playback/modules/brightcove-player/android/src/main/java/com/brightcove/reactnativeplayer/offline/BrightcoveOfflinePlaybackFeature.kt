package com.brightcove.reactnativeplayer.offline

import com.brightcove.player.edge.OfflineCallback
import com.brightcove.player.edge.OfflineCatalog
import com.brightcove.player.edge.OfflineStoreManager
import com.brightcove.player.event.Event
import com.brightcove.player.model.Video
import com.brightcove.player.network.DownloadStatus
import com.brightcove.player.display.ExoPlayerVideoDisplayComponent
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature

/**
 * Resolves an opaque offlineSourceId to the SDK's persisted local Video and
 * supplies it through the ordinary BrightcoveExoPlayerVideoView queue. The
 * local source never calls the online Playback API: OfflineCatalog's lookup is
 * backed by OfflineStoreManager, and the media store makes ExoPlayer read the
 * downloaded DASH manifest and segments.
 */
class BrightcoveOfflinePlaybackFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var offlineSourceId = ""
  private var activeSourceId: String? = null
  private var catalog: OfflineCatalog? = null

  override val ownedProps = setOf("offlineSourceId")
  override val exportedEvents = emptyMap<String, String>()

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    check(name == "offlineSourceId") { "Unexpected offline prop '$name'" }
    val newValue = value as? String ?: ""
    if (offlineSourceId != newValue) {
      offlineSourceId = newValue
      host.requestSourceReload()
    }
  }

  override fun claimsSourceLoading(): Boolean = offlineSourceId.isNotBlank()

  override fun onSourceReset() {
    activeSourceId?.let(OfflinePlaybackActiveSources::remove)
    activeSourceId = null
    catalog?.terminate()
    catalog = null
  }

  override fun onDispose() {
    onSourceReset()
  }

  override fun loadSource(requestGeneration: Int, accountId: String, policyKey: String) {
    val sourceId = offlineSourceId
    catalog?.terminate()
    catalog = null
    if (sourceId.isBlank()) {
      host.emitSourceLoadError(
        requestGeneration,
        code = "invalid_configuration",
        nativeCode = "offline_source_missing",
        message = "offlineSourceId must be non-empty when loading offline playback",
      )
      return
    }

    val context = host.videoView.context.applicationContext
    val display = host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent
    if (display == null) {
      host.emitSourceLoadError(
        requestGeneration,
        code = "not_playable",
        nativeCode = "offline_video_display_unavailable",
        message = "Brightcove's ExoPlayer display is unavailable for offline playback",
      )
      return
    }
    display.setMediaStore(OfflineStoreManager.getInstance(context))

    // OfflineCatalog uses account/policy to construct its SDK helper, but this
    // particular call is a local-store lookup and does not issue a catalog
    // request. Keeping it on the view emitter preserves normal SDK analytics
    // ownership for the player itself.
    val sourceCatalog = OfflineCatalog.Builder(context, host.eventEmitter, accountId)
      .setPolicy(policyKey)
      .build()
    catalog = sourceCatalog
    sourceCatalog.findOfflineVideoById(sourceId, object : OfflineCallback<Video?> {
      override fun onSuccess(video: Video?) {
        if (!host.isCurrentRequest(requestGeneration)) return
        if (video == null) {
          host.emitSourceLoadError(
            requestGeneration,
            code = "not_found",
            nativeCode = "offline_source_not_found",
            message = "No persisted download exists for offlineSourceId '$sourceId'",
          )
          return
        }

        sourceCatalog.getVideoDownloadStatus(video, object : OfflineCallback<DownloadStatus?> {
          override fun onSuccess(status: DownloadStatus?) {
            if (!host.isCurrentRequest(requestGeneration)) return
            if (status?.code != DownloadStatus.STATUS_COMPLETE) {
              host.emitSourceLoadError(
                requestGeneration,
                code = "not_playable",
                nativeCode = "offline_source_not_complete",
                message = "The persisted download for offlineSourceId '$sourceId' is not complete",
              )
              return
            }
            val readyVideoId = video.id.ifBlank { sourceId }
            host.setReadyVideoId(requestGeneration, readyVideoId)
            if (!OfflinePlaybackActiveSources.acquire(sourceId)) {
              host.emitSourceLoadError(
                requestGeneration,
                code = "not_playable",
                nativeCode = "offline_source_removing",
                message = "The persisted download is being removed",
              )
              return
            }
            try {
              host.videoView.add(host.tagVideoForCurrentRequest(host.onVideoLoaded(video)))
            } catch (e: RuntimeException) {
              // The refcount acquired above must be released when the add
              // itself fails, or the source is permanently stuck as
              // active_offline_source and every later removeDownload is
              // rejected.
              OfflinePlaybackActiveSources.remove(sourceId)
              throw e
            }
            activeSourceId = sourceId
            host.markVideoLoaded(requestGeneration, readyVideoId)
          }

          override fun onFailure(throwable: Throwable) {
            if (!host.isCurrentRequest(requestGeneration)) return
            host.emitSourceLoadError(
              requestGeneration,
              code = "unknown",
              nativeCode = throwable.javaClass.simpleName,
              message = throwable.localizedMessage ?: "Unable to inspect the persisted download",
            )
          }
        })
      }

      override fun onFailure(throwable: Throwable) {
        if (!host.isCurrentRequest(requestGeneration)) return
        host.emitSourceLoadError(
          requestGeneration,
          code = "unknown",
          nativeCode = throwable.javaClass.simpleName,
          message = throwable.localizedMessage ?: "Unable to load the persisted download",
        )
      }
    })
  }
}
