package com.brightcove.reactnativeplayer.controls

import com.brightcove.player.mediacontroller.BrightcoveMediaController
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature

/**
 * Controls feature: enables or disables the native Brightcove media controller UI
 * based on the controlsEnabled prop.
 */
class ControlsFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var controlsEnabled = true

  override val ownedProps = setOf("controlsEnabled")
  override val exportedEvents: Map<String, String> = emptyMap()

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "controlsEnabled" -> {
        controlsEnabled = requireNotNull(value as? Boolean) {
          "ControlsFeature requires a Boolean for '$name'"
        }
      }
      else -> error("ControlsFeature does not own prop '$name'")
    }
  }

  override fun onPropsCommitted() {
    applyControls()
  }

  override fun onRegisterPlaybackListeners() {
    applyControls()
  }

  override fun onLayoutChanged() {
    if (controlsEnabled) {
      host.requestHostLayout()
    }
  }

  private fun applyControls() {
    if (host.isDisposed) return
    if (host.videoView.brightcoveMediaController == null) {
      host.videoView.setMediaController(BrightcoveMediaController(host.videoView))
    }
    val controller = host.videoView.brightcoveMediaController ?: return
    controller.setShowControllerEnable(controlsEnabled)
    if (controlsEnabled) {
      controller.show()
    } else {
      controller.hide()
    }
    host.requestHostLayout()
  }
}
