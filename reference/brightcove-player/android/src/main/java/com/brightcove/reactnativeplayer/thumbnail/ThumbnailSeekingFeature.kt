package com.brightcove.reactnativeplayer.thumbnail

import android.net.Uri
import com.brightcove.player.captioning.PreviewThumbnailFormat
import com.brightcove.player.event.EventType
import com.brightcove.player.mediacontroller.BrightcoveMediaController
import com.brightcove.player.mediacontroller.PreviewLoader
import com.brightcove.player.mediacontroller.PreviewThumbnailView
import com.brightcove.player.mediacontroller.ThumbnailComponent
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature

/**
 * Installs Brightcove's thumbnail-aware media controller for online videos.
 *
 * The Android plugin loads the preview document from the DID_SET_VIDEO event,
 * so this option must be selected before the current source is loaded. Rejecting
 * a later toggle is preferable to showing a seek bar that looks enabled but has
 * no thumbnail document behind it.
 */
class ThumbnailSeekingFeature : PlayerFeature {
  private var host: FeatureHost? = null
  private var enabled = false
  private var sourceHasLoaded = false
  private var thumbnailComponent: ThumbnailComponent? = null

  override val ownedProps = setOf("thumbnailSeekingEnabled")

  override val exportedEvents = emptyMap<String, String>()

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    if (name != "thumbnailSeekingEnabled") {
      error("ThumbnailSeekingFeature does not own prop '$name'")
    }

    val requested = value as? Boolean
      ?: error("thumbnailSeekingEnabled must be a Boolean")
    if (requested == enabled) return
    if (sourceHasLoaded) {
      error("thumbnailSeekingEnabled must be set before the current video is loaded")
    }

    enabled = requested
    if (enabled) {
      enableThumbnailSeeking()
    } else {
      disableThumbnailSeeking()
    }
  }

  override fun onSourceReset() {
    sourceHasLoaded = false
    if (enabled && thumbnailComponent != null) {
      resetThumbnailComponent()
      enableThumbnailSeeking()
    }
  }

  // Forces preview-thumbnail URLs to HTTPS: the seek-bar preview image loader
  // fetches these directly, and a cleartext (http://) URL would either be
  // silently blocked by network-security-config or, if cleartext were opened
  // for it, would weaken the app's network policy for a URL the caller never
  // asked to allow cleartext for. Returns the input video unchanged when no
  // source is insecure (the common case), so a feature that mutates and
  // returns the same instance and one that only reads it are both safe under
  // the core's onVideoLoaded fold.
  override fun onVideoLoaded(video: Video): Video {
    val sources = video.previewThumbnailSources
    val secureSources = secureThumbnailSources(sources)
    if (secureSources !== sources) {
      video.properties[Video.Fields.PREVIEW_THUMBNAIL_SOURCES] = secureSources
    }
    return video
  }

  override fun onRegisterPlaybackListeners() {
    host?.registerListener(EventType.DID_SET_VIDEO) {
      sourceHasLoaded = true
    }
  }

  override fun onDispose() {
    resetThumbnailComponent()
    host = null
  }

  private fun enableThumbnailSeeking() {
    val host = host ?: return
    if (host.isDisposed || thumbnailComponent != null) return

    // React Native's view-manager setters run on the Android UI thread. The
    // plugin creates Android Views and its setup API explicitly requires that
    // thread; keeping setup here also makes the initialization ordering clear.
    thumbnailComponent = ThumbnailComponent(host.videoView).also {
      it.setupPreviewThumbnailController()
    }
    host.requestHostLayout()
  }

  private fun disableThumbnailSeeking() {
    val host = host ?: return
    if (thumbnailComponent == null) return

    resetThumbnailComponent()
    host.videoView.setMediaController(BrightcoveMediaController(host.videoView))
    host.requestHostLayout()
  }

  private fun resetThumbnailComponent() {
    val host = host ?: return
    val component = thumbnailComponent ?: return
    val mediaController = host.videoView.brightcoveMediaController

    // The SDK does not expose cancellation for its VTT task. Replace the
    // component's loader before removing it so a late callback can only write
    // into PreviewLoader.EMPTY, never into a document used by a new source.
    component.setPreviewLoader(PreviewLoader.EMPTY)
    component.removeListeners()
    (mediaController?.brightcoveSeekBar as? PreviewThumbnailView)?.reset()
    thumbnailComponent = null
    host.videoView.setMediaController(null as BrightcoveMediaController?)
  }
}

internal fun secureThumbnailSources(
  sources: List<PreviewThumbnailFormat>,
): List<PreviewThumbnailFormat> {
  var changed = false
  val result = sources.map { source ->
    val originalUrl = source.uri.toString()
    val secureUrl = secureThumbnailUrl(originalUrl)
    if (secureUrl == originalUrl) {
      source
    } else {
      changed = true
      PreviewThumbnailFormat(
        Uri.parse(secureUrl),
        source.width,
        source.height,
        source.bandwidth,
      )
    }
  }
  return if (changed) result else sources
}

// A plain-String transform (no android.net.Uri construction) so it is
// unit-testable on the JVM without Robolectric/instrumentation — Uri.parse
// itself is not available in a plain JUnit unit test.
internal fun secureThumbnailUrl(url: String): String =
  if (url.startsWith("http://", ignoreCase = true)) {
    "https://${url.substringAfter("://")}"
  } else {
    url
  }
