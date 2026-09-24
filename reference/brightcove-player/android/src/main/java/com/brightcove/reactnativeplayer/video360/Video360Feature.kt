package com.brightcove.reactnativeplayer.video360

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Reports 360/equirectangular projection detection and VR (goggles) mode
 * transitions, and applies the caller's requested vrMode to the SDK's own
 * spherical renderer. Video360Feature does not implement VR navigation
 * itself — it only toggles the SDK renderer's existing vrMode and relays its
 * own ENTERED_VR_MODE/EXITED_VR_MODE events (e.g. a device-orientation
 * trigger the SDK recognizes) back to JS.
 */
class Video360Feature : PlayerFeature {
  override val ownedProps: Set<String> = setOf("vrMode")

  override val exportedEvents: Map<String, String> = mapOf(
    EVENT_PROJECTION_FORMAT_CHANGED to "onProjectionFormatChanged",
    EVENT_VIDEO_360_MODE_CHANGED to "onVideo360ModeChanged",
  )

  private var host: FeatureHost? = null
  private var requestedVrMode: Boolean = false
  private var activeVrMode: Boolean = false
  private var is360Video: Boolean = false
  private var lastReportedModeKey: String? = null
  private var lastReportedIs360: Boolean? = null
  // A source reset already reports the "back to normal" state once; guards
  // against onVideoLoaded's own onSourceReset-adjacent reset also emitting it
  // a second time for the same reset.
  private var sourceResetReported: Boolean = false

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    if (name != "vrMode") {
      error("Video360Feature does not own prop '$name'")
    }
    val newVrMode = value as? Boolean
      ?: error("Video360Feature requires a Boolean for '$name'")
    if (requestedVrMode != newVrMode) {
      requestedVrMode = newVrMode
      applyVrMode()
    }
  }

  override fun onSourceReset() {
    val renderView = host?.videoView?.renderView
    if (renderView?.isVrMode == true) {
      renderView.setVrMode(false)
    }
    activeVrMode = false
    is360Video = false
    lastReportedModeKey = null
    lastReportedIs360 = null
    if (!sourceResetReported) {
      emitProjectionFormatChanged("normal", false)
      emitVideo360ModeChanged(false, "normal", "none")
      sourceResetReported = true
    }
  }

  // Reads the newly-resolved video's projection format before the core
  // decides how to add it — the SDK reports EQUIRECTANGULAR here even before
  // the first PROJECTION_FORMAT_CHANGED playback event fires, so a 360 video
  // is already known and reported by the time onReady fires. applyMode=false:
  // vrMode is not auto-enabled just because the video is 360 — the caller
  // requests it explicitly via the vrMode prop.
  override fun onVideoLoaded(video: Video): Video {
    sourceResetReported = false
    lastReportedModeKey = null
    lastReportedIs360 = null
    updateProjectionFormat(video.projectionFormat, applyMode = false)
    return video
  }

  override fun onRegisterPlaybackListeners() {
    val h = host ?: return

    h.registerListener(EventType.PROJECTION_FORMAT_CHANGED) { event ->
      updateProjectionFormat(event.properties[Event.PROJECTION_FORMAT] as? Video.ProjectionFormat)
    }

    h.registerListener(EventType.ENTERED_VR_MODE) {
      if (!is360Video) return@registerListener
      requestedVrMode = true
      activeVrMode = true
      emitVideo360ModeChanged(
        vrMode = true,
        projectionStyle = "vrGoggles",
        navigationMethod = "unknown",
      )
    }

    h.registerListener(EventType.EXITED_VR_MODE) {
      if (!is360Video) return@registerListener
      requestedVrMode = false
      activeVrMode = false
      emitVideo360ModeChanged(
        vrMode = false,
        projectionStyle = "normal",
        navigationMethod = "unknown",
      )
    }
  }

  private fun updateProjectionFormat(
    format: Video.ProjectionFormat?,
    applyMode: Boolean = true,
  ) {
    val isEquirectangular = format == Video.ProjectionFormat.EQUIRECTANGULAR
    is360Video = isEquirectangular
    val formatString = if (isEquirectangular) "equirectangular" else "normal"

    if (lastReportedIs360 != isEquirectangular) {
      lastReportedIs360 = isEquirectangular
      emitProjectionFormatChanged(formatString, isEquirectangular)
    }

    if (isEquirectangular && !requestedVrMode) {
      emitVideo360ModeChanged(false, "normal", "unknown")
    }
    if (applyMode) {
      applyVrMode()
    }
  }

  private fun applyVrMode() {
    val h = host ?: return
    val renderView = h.videoView.renderView ?: return
    val targetVrMode = requestedVrMode && is360Video
    if (renderView.isVrMode != targetVrMode) {
      renderView.setVrMode(targetVrMode)
    }
    if (activeVrMode != targetVrMode) {
      activeVrMode = targetVrMode
      val style = if (targetVrMode) "vrGoggles" else "normal"
      emitVideo360ModeChanged(targetVrMode, style, "unknown")
    }
  }

  private fun emitProjectionFormatChanged(projectionFormat: String, is360: Boolean) {
    val h = host ?: return
    h.emitEvent(
      EVENT_PROJECTION_FORMAT_CHANGED,
      Arguments.createMap().apply {
        putString("projectionFormat", projectionFormat)
        putBoolean("is360", is360)
      },
    )
  }

  private fun emitVideo360ModeChanged(
    vrMode: Boolean,
    projectionStyle: String,
    navigationMethod: String,
  ) {
    val modeKey = "$vrMode|$projectionStyle|$navigationMethod"
    if (lastReportedModeKey == modeKey) return
    lastReportedModeKey = modeKey
    val h = host ?: return
    h.emitEvent(
      EVENT_VIDEO_360_MODE_CHANGED,
      Arguments.createMap().apply {
        putBoolean("vrMode", vrMode)
        putString("projectionStyle", projectionStyle)
        putString("navigationMethod", navigationMethod)
      },
    )
  }

  override fun onDispose() {
    host = null
  }

  companion object {
    const val EVENT_PROJECTION_FORMAT_CHANGED = "topProjectionFormatChanged"
    const val EVENT_VIDEO_360_MODE_CHANGED = "topVideo360ModeChanged"
  }
}
