package com.brightcove.reactnativeplayer.playbackevents

import android.os.SystemClock
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Surfaces playback lifecycle to JS: onPlay, onPause, onEnded, and a periodic
 * onProgress carrying the current position and duration.
 *
 * This reports playback *state* for the app to react to (custom controls, a
 * progress bar, "resume where you left off"). It does NOT configure Brightcove's
 * Video Cloud analytics beacons — the SDK sends those automatically; the core's
 * Catalog is built on the same event emitter the analytics component uses.
 *
 * The feature owns no props (it is event-only). Listeners are registered as
 * source-scoped through the host in onRegisterPlaybackListeners, so they only
 * fire for the current video and are torn down on source change or dispose.
 */
class PlaybackEventsFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  // The SDK's PROGRESS event fires many times per second; forwarding every one
  // across the RN bridge floods the JS thread. Throttle onProgress to at most
  // one emit per PROGRESS_INTERVAL_MS. Reset per source in onSourceReset.
  private var lastProgressEmitMs = 0L

  override val ownedProps = emptySet<String>()

  override val exportedEvents = mapOf(
    EVENT_PLAY to "onPlay",
    EVENT_PAUSE to "onPause",
    EVENT_ENDED to "onEnded",
    EVENT_PROGRESS to "onProgress",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    error("PlaybackEventsFeature owns no props; received '$name'")
  }

  override fun onSourceReset() {
    lastProgressEmitMs = 0L
  }

  override fun onRegisterPlaybackListeners() {
    host.registerListener(EventType.DID_PLAY) {
      host.emitEvent(EVENT_PLAY, Arguments.createMap())
    }
    host.registerListener(EventType.DID_PAUSE) {
      host.emitEvent(EVENT_PAUSE, Arguments.createMap())
    }
    host.registerListener(EventType.COMPLETED) {
      host.emitEvent(EVENT_ENDED, Arguments.createMap())
    }
    host.registerListener(EventType.PROGRESS) { event ->
      val now = SystemClock.elapsedRealtime()
      if (now - lastProgressEmitMs < PROGRESS_INTERVAL_MS) return@registerListener
      lastProgressEmitMs = now
      host.emitEvent(EVENT_PROGRESS, progressPayload(event))
    }
  }

  // PROGRESS carries the playhead and duration in milliseconds (the *_LONG
  // properties are the authoritative wide values; the non-long ints overflow
  // past ~24 days). Convert to seconds for the cross-platform contract. A live
  // stream can report a negative/unset duration before the window is known;
  // clamp it to 0 so JS never sees a nonsense negative total.
  private fun progressPayload(event: Event) = Arguments.createMap().apply {
    val positionMs = event.getLongProperty(Event.PLAYHEAD_POSITION_LONG)
    val durationMs = event.getLongProperty(Event.VIDEO_DURATION_LONG)
    putDouble("currentTime", positionMs.coerceAtLeast(0L) / MILLIS_PER_SECOND)
    putDouble("duration", durationMs.coerceAtLeast(0L) / MILLIS_PER_SECOND)
  }

  companion object {
    private const val MILLIS_PER_SECOND = 1000.0
    // ~4 progress updates per second: enough for a smooth progress bar, bounded
    // so the JS thread is not flooded. Matches the iOS feature's cadence.
    private const val PROGRESS_INTERVAL_MS = 250L
    private const val EVENT_PLAY = "topPlay"
    private const val EVENT_PAUSE = "topPause"
    private const val EVENT_ENDED = "topEnded"
    private const val EVENT_PROGRESS = "topProgress"
  }
}
