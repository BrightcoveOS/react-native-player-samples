package com.brightcove.reactnativeplayer.sourceloadingmodes

import com.brightcove.player.edge.Catalog
import com.brightcove.player.edge.CatalogError
import com.brightcove.player.edge.PlaylistListener
import com.brightcove.player.edge.VideoListener
import com.brightcove.player.model.Playlist
import com.brightcove.player.model.Video
import com.brightcove.player.network.HttpRequestConfig
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerErrorClassifier
import com.brightcove.reactnativeplayer.core.PlayerFeature

/**
 * Loads a Video Cloud source from one of four alternate catalog lookups —
 * video reference ID, playlist ID, or playlist reference ID — or a direct
 * HTTPS HLS/MP4 stream, instead of the core's own numeric videoId lookup.
 *
 * Routed through claimsSourceLoading like offline: exactly one of
 * videoReferenceId, playlistId, playlistReferenceId, or sourceUrl selects
 * this feature as the current source's loader (mutually exclusive with each
 * other and with the core's own videoId, enforced here so the ambiguity never
 * reaches the core's own "multiple loaders claimed" crash). A playlist mode
 * adds every resolved video to the native queue at once (SDK-owned
 * end-of-item advancement, matching PlaylistsFeature); the reported ready id
 * is the playlist's first video.
 */
class SourceLoadingModesFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var selection = SourceLoadingModeSelection()

  private val videoReferenceId: String get() = selection.videoReferenceId
  private val playlistId: String get() = selection.playlistId
  private val playlistReferenceId: String get() = selection.playlistReferenceId
  private val sourceUrl: String get() = selection.sourceUrl

  override val ownedProps = setOf(
    "videoReferenceId",
    "playlistId",
    "playlistReferenceId",
    "sourceUrl",
  )
  override val exportedEvents = emptyMap<String, String>()

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    val newValue = (value as? String)?.trim() ?: ""
    val current = selection.currentValue(name)
    if (current == newValue) return

    // Mutually exclusive mode selection is the pure rule in
    // SourceLoadingModeSelection; this only wires the change into a reload.
    selection = selection.apply(name, newValue)
    host.requestSourceReload()
  }

  override fun onSourceReset() {
    // No per-request state to clear: each loadSource call is a single
    // fire-and-forget catalog request guarded by host.isCurrentRequest, with
    // no queue or resolution loop to reset (unlike PlaylistsFeature).
  }

  override fun claimsSourceLoading(): Boolean =
    activeMode() != null

  /**
   * The single active mode this instant, or null if none of this feature's
   * props are set. setProp keeps the four mode fields mutually exclusive; the
   * activeModes guard in loadSource remains a fail-loud invariant check.
   */
  private fun activeMode(): Mode? = when {
    videoReferenceId.isNotEmpty() -> Mode.VideoReferenceId(videoReferenceId)
    playlistId.isNotEmpty() -> Mode.PlaylistId(playlistId)
    playlistReferenceId.isNotEmpty() -> Mode.PlaylistReferenceId(playlistReferenceId)
    sourceUrl.isNotEmpty() -> Mode.DirectUrl(sourceUrl)
    else -> null
  }

  override fun loadSource(requestGeneration: Int, accountId: String, policyKey: String) {
    val activeModes = selection.activeModeCount()
    if (activeModes > 1) {
      host.emitSourceLoadError(
        requestGeneration,
        code = "invalid_configuration",
        nativeCode = "source_loading_modes_ambiguous",
        message = "Exactly one of videoReferenceId, playlistId, playlistReferenceId, " +
          "or sourceUrl must be set; multiple were set at once",
      )
      return
    }

    val mode = activeMode()

    // DirectUrl needs no credentials, but every other mode issues a Playback
    // API request through Catalog, which requires accountId + policyKey. Reject
    // an empty credential loudly here instead of handing Catalog.Builder blank
    // strings that fail opaquely downstream.
    if (selection.requiresCredentials() && (accountId.isBlank() || policyKey.isBlank())) {
      host.emitSourceLoadError(
        requestGeneration,
        code = "invalid_configuration",
        nativeCode = "source_loading_modes_missing_credentials",
        message = "accountId and policyKey are required for videoReferenceId, " +
          "playlistId, and playlistReferenceId sources",
      )
      return
    }

    when (mode) {
      is Mode.DirectUrl -> loadDirectUrl(requestGeneration, mode.url)
      is Mode.VideoReferenceId -> loadVideoByReferenceId(requestGeneration, accountId, policyKey, mode.id)
      is Mode.PlaylistId -> loadPlaylist(requestGeneration, accountId, policyKey) { catalog, listener ->
        catalog.findPlaylistByID(mode.id, HttpRequestConfig.empty(), listener)
      }
      is Mode.PlaylistReferenceId -> loadPlaylist(requestGeneration, accountId, policyKey) { catalog, listener ->
        catalog.findPlaylistByReferenceID(mode.id, HttpRequestConfig.empty(), listener)
      }
      null -> host.emitSourceLoadError(
        requestGeneration,
        code = "invalid_configuration",
        nativeCode = "source_loading_modes_missing",
        message = "One of videoReferenceId, playlistId, playlistReferenceId, or " +
          "sourceUrl must be set when this feature claims the current source",
      )
    }
  }

  private fun loadDirectUrl(requestGeneration: Int, url: String) {
    if (!isValidHttpsStreamUrl(url)) {
      host.emitSourceLoadError(
        requestGeneration,
        code = "invalid_configuration",
        nativeCode = "source_loading_modes_invalid_url",
        message = "sourceUrl must be a valid https URL ending in .m3u8 or .mp4",
      )
      return
    }

    val video = try {
      Video.createVideo(url)
    } catch (e: IllegalArgumentException) {
      host.emitSourceLoadError(
        requestGeneration,
        code = "invalid_configuration",
        nativeCode = e.javaClass.simpleName,
        message = e.localizedMessage ?: "Unable to create a video from sourceUrl",
      )
      return
    }

    if (!host.isCurrentRequest(requestGeneration)) return
    host.setReadyVideoId(requestGeneration, url)
    // Stamp the request generation like every other loader: the core's
    // stale-source guard and ad-event scoping both key off the tag.
    host.videoView.add(host.tagVideoForCurrentRequest(host.onVideoLoaded(video)))
    host.markVideoLoaded(requestGeneration, url)
  }

  private fun loadVideoByReferenceId(
    requestGeneration: Int,
    accountId: String,
    policyKey: String,
    referenceId: String,
  ) {
    val catalog = Catalog.Builder(host.eventEmitter, accountId)
      .setPolicy(policyKey)
      .build()
    catalog.findVideoByReferenceID(
      referenceId,
      HttpRequestConfig.empty(),
      object : VideoListener() {
        override fun onVideo(video: Video) {
          if (!host.isCurrentRequest(requestGeneration)) return
          val readyVideoId = video.id?.ifBlank { null } ?: referenceId
          host.setReadyVideoId(requestGeneration, readyVideoId)
          host.videoView.add(host.tagVideoForCurrentRequest(host.onVideoLoaded(video)))
          host.markVideoLoaded(requestGeneration, readyVideoId)
        }

        override fun onError(errors: List<CatalogError>) {
          if (!host.isCurrentRequest(requestGeneration)) return
          emitCatalogError(requestGeneration, errors.firstOrNull(), "Unable to retrieve the Brightcove video")
        }

        override fun onError(error: String) {
          if (!host.isCurrentRequest(requestGeneration)) return
          host.emitSourceLoadError(
            requestGeneration,
            code = "unknown",
            nativeCode = "catalog_error",
            message = error.ifBlank { "Unable to retrieve the Brightcove video" },
          )
        }
      },
    )
  }

  private fun loadPlaylist(
    requestGeneration: Int,
    accountId: String,
    policyKey: String,
    find: (Catalog, PlaylistListener) -> Unit,
  ) {
    val catalog = Catalog.Builder(host.eventEmitter, accountId)
      .setPolicy(policyKey)
      .build()
    find(
      catalog,
      object : PlaylistListener() {
        override fun onPlaylist(playlist: Playlist) {
          if (!host.isCurrentRequest(requestGeneration)) return
          val videos = playlist.videos
          if (videos.isNullOrEmpty()) {
            host.emitSourceLoadError(
              requestGeneration,
              code = "not_playable",
              nativeCode = "source_loading_modes_empty_playlist",
              message = "The Brightcove playlist contains no videos",
            )
            return
          }
          val firstVideo = videos.first()
          val readyVideoId = firstVideo.id?.ifBlank { null }
            ?: firstVideo.referenceId?.ifBlank { null }
            ?: "playlist"
          host.setReadyVideoId(requestGeneration, readyVideoId)
          videos.forEach { host.videoView.add(host.tagVideoForCurrentRequest(host.onVideoLoaded(it))) }
          host.markVideoLoaded(requestGeneration, readyVideoId)
        }

        override fun onError(errors: List<CatalogError>) {
          if (!host.isCurrentRequest(requestGeneration)) return
          emitCatalogError(requestGeneration, errors.firstOrNull(), "Unable to retrieve the Brightcove playlist")
        }

        override fun onError(error: String) {
          if (!host.isCurrentRequest(requestGeneration)) return
          host.emitSourceLoadError(
            requestGeneration,
            code = "unknown",
            nativeCode = "catalog_error",
            message = error.ifBlank { "Unable to retrieve the Brightcove playlist" },
          )
        }
      },
    )
  }

  // Same two-shape catalog failure classification as the core's own
  // emitCatalogError (see BrightcovePlayerView.emitCatalogError): a real
  // Playback API error (typed catalogErrorCode) versus a transport exception
  // (IOException/SocketTimeoutException, empty catalogErrorCode). Classification
  // is shared with the core and playlists so the same native failure cannot
  // report different normalized codes depending on which source loader saw it.
  private fun emitCatalogError(requestGeneration: Int, error: CatalogError?, fallbackMessage: String) {
    val throwable = error?.throwable
    val (code, nativeCode) = PlayerErrorClassifier.classifyCatalogError(
      error?.catalogErrorCode,
      throwable,
    )
    host.emitSourceLoadError(
      requestGeneration,
      code = code,
      nativeCode = nativeCode,
      message = throwable?.localizedMessage
        ?: error?.message?.ifBlank { null }
        ?: fallbackMessage,
    )
  }

  private sealed interface Mode {
    data class VideoReferenceId(val id: String) : Mode
    data class PlaylistId(val id: String) : Mode
    data class PlaylistReferenceId(val id: String) : Mode
    data class DirectUrl(val url: String) : Mode
  }

  companion object {
    /**
     * A pure, unit-testable validity check for a direct-URL source: https
     * scheme, a non-blank host, and a path ending in a playable extension.
     * Kept as a standalone function (not requiring a Uri/URL instance) so it
     * can be exercised without Robolectric — see SourceLoadingModesFeatureTest.
     */
    fun isValidHttpsStreamUrl(url: String): Boolean {
      val uri = try {
        java.net.URI(url)
      } catch (_: java.net.URISyntaxException) {
        return false
      }
      if (!uri.scheme.equals("https", ignoreCase = true)) return false
      if (uri.host.isNullOrBlank()) return false
      val path = uri.path?.lowercase() ?: return false
      return path.endsWith(".m3u8") || path.endsWith(".m3u") || path.endsWith(".mp4")
    }
  }
}
