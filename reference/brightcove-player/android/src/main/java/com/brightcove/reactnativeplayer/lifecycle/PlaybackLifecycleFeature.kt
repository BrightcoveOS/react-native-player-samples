package com.brightcove.reactnativeplayer.lifecycle

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/** Reports decoded video dimensions without conflating them with RN layout size. */
class PlaybackLifecycleFeature : PlayerFeature {
  private var host: FeatureHost? = null
  private var lastWidth = 0
  private var lastHeight = 0

  override val ownedProps: Set<String> = emptySet()

  override val exportedEvents: Map<String, String> = mapOf(
    EVENT_VIDEO_SIZE_CHANGED to "onVideoSizeChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    error("PlaybackLifecycleFeature does not own prop '$name'")
  }

  override fun onSourceReset() {
    lastWidth = 0
    lastHeight = 0
  }

  override fun onRegisterPlaybackListeners() {
    checkNotNull(host).registerListener(EventType.VIDEO_SIZE_KNOWN, ::handleVideoSizeKnown)
  }

  override fun onDispose() {
    host = null
    lastWidth = 0
    lastHeight = 0
  }

  private fun handleVideoSizeKnown(event: Event) {
    val host = host ?: return
    val width = (event.properties[Event.VIDEO_WIDTH] as? Number)?.toInt() ?: return
    val height = (event.properties[Event.VIDEO_HEIGHT] as? Number)?.toInt() ?: return
    if (host.isDisposed) return
    if (!shouldEmitVideoSize(width, height, lastWidth, lastHeight)) return

    lastWidth = width
    lastHeight = height
    host.emitEvent(
      EVENT_VIDEO_SIZE_CHANGED,
      Arguments.createMap().apply {
        putDouble("width", width.toDouble())
        putDouble("height", height.toDouble())
      },
    )
  }

  companion object {
    const val EVENT_VIDEO_SIZE_CHANGED = "topVideoSizeChanged"
  }
}

internal fun shouldEmitVideoSize(
  width: Int,
  height: Int,
  previousWidth: Int,
  previousHeight: Int,
): Boolean =
  width > 0 && height > 0 && (width != previousWidth || height != previousHeight)
