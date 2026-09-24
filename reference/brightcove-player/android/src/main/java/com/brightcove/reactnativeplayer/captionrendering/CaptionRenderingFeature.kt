package com.brightcove.reactnativeplayer.captionrendering

import androidx.media3.common.Player
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import com.brightcove.player.display.ExoPlayerVideoDisplayComponent
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

internal fun formatCueText(cues: List<Cue>): String {
  if (cues.isEmpty()) return ""
  return cues.joinToString("\n") { it.text?.toString() ?: "" }
}

/**
 * Custom caption rendering feature: extracts cue text directly from ExoPlayer
 * and forwards it to JS via onCaptionCueChanged for custom React Native overlay rendering.
 */
class CaptionRenderingFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var customCaptionRenderingEnabled = false
  private var playerListener: Player.Listener? = null
  private var activeExoPlayer: Player? = null
  private var sourceGeneration = 0

  override val ownedProps = setOf("customCaptionRenderingEnabled")

  override val exportedEvents = mapOf(
    EVENT_CAPTION_CUE_CHANGED to "onCaptionCueChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "customCaptionRenderingEnabled" -> {
        customCaptionRenderingEnabled = requireNotNull(value as? Boolean) {
          "CaptionRenderingFeature requires a Boolean for '$name'"
        }
      }
      else -> error("CaptionRenderingFeature does not own prop '$name'")
    }
  }

  override fun onRegisterPlaybackListeners() {
    attachPlayerListener()
    listOf(
      com.brightcove.player.event.EventType.BUFFERING_STARTED,
      com.brightcove.player.event.EventType.BUFFERING_COMPLETED,
      com.brightcove.player.event.EventType.DID_PLAY,
      com.brightcove.player.event.EventType.CAPTIONS_LANGUAGES,
    ).forEach { eventType ->
      host.registerListener(eventType) { attachPlayerListener() }
    }
  }

  override fun onPropsCommitted() {
    if (customCaptionRenderingEnabled) {
      host.videoView.disableClosedCaptioningRendering()
      attachPlayerListener()
    } else {
      cleanupListener()
      host.videoView.setupClosedCaptioningRendering()
      emitCue(text = "", startTime = 0.0, endTime = 0.0)
    }
  }

  override fun onSourceReset() {
    sourceGeneration += 1
    cleanupListener()
    emitCue(text = "", startTime = 0.0, endTime = 0.0)
  }

  override fun onDispose() {
    cleanupListener()
  }

  private fun cleanupListener() {
    playerListener?.let { listener ->
      activeExoPlayer?.removeListener(listener)
    }
    playerListener = null
    activeExoPlayer = null
  }

  private fun attachPlayerListener() {
    if (!customCaptionRenderingEnabled || host.isDisposed) return

    host.videoView.disableClosedCaptioningRendering()
    val display = host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent ?: return
    val exoPlayer = display.getExoPlayer() ?: return
    if (activeExoPlayer === exoPlayer && playerListener != null) return

    cleanupListener()
    activeExoPlayer = exoPlayer
    val listenerGeneration = sourceGeneration

    val listener = object : Player.Listener {
      override fun onCues(cueGroup: CueGroup) {
        if (
          host.isDisposed ||
          !customCaptionRenderingEnabled ||
          listenerGeneration != sourceGeneration ||
          activeExoPlayer !== exoPlayer
        ) return
        val cues = cueGroup.cues
        val text = formatCueText(cues)
        if (text.isEmpty()) {
          emitCue(text = "", startTime = 0.0, endTime = 0.0)
          return
        }
        val positionSeconds = host.videoView.currentPositionLong / 1000.0
        // Media3's cue callback does not expose the cue end time. Zero is the
        // documented unknown sentinel; never invent a duration for JS.
        emitCue(text = text, startTime = positionSeconds, endTime = 0.0)
      }
    }
    playerListener = listener
    exoPlayer.addListener(listener)
  }

  private fun emitCue(text: String, startTime: Double, endTime: Double) {
    if (host.isDisposed) return
    val payload = Arguments.createMap().apply {
      putString("text", text)
      putDouble("startTime", startTime)
      putDouble("endTime", endTime)
    }
    host.emitEvent(EVENT_CAPTION_CUE_CHANGED, payload)
  }

  companion object {
    const val EVENT_CAPTION_CUE_CHANGED = "topCaptionCueChanged"
  }
}
