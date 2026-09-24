package com.brightcove.reactnativeplayer.buffering

import androidx.media3.common.Player
import com.brightcove.player.display.ExoPlayerVideoDisplayComponent
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Reports normal playback stalls after the source has prepared and playback has
 * started. The direct Media3 listener lets the feature distinguish a seek
 * discontinuity from a stall; Brightcove's buffering events alone do not carry
 * that reason.
 */
class BufferingFeature : PlayerFeature {
  private var host: FeatureHost? = null
  private var tracker: RebufferTracker? = null
  private var attachedPlayer: Player? = null
  private var seekInProgress = false
  private var sourceFailed = false

  private val playerListener = object : Player.Listener {
    override fun onPositionDiscontinuity(
      oldPosition: Player.PositionInfo,
      newPosition: Player.PositionInfo,
      reason: Int,
    ) {
      if (reason == Player.DISCONTINUITY_REASON_SEEK) {
        seekInProgress = true
      }
    }

    override fun onEvents(player: Player, events: Player.Events) {
      if (sourceFailed || host?.isDisposed != false) return

      val stateChanged = events.contains(Player.EVENT_PLAYBACK_STATE_CHANGED)
      val playingChanged = events.contains(Player.EVENT_IS_PLAYING_CHANGED)
      val positionChanged = events.contains(Player.EVENT_POSITION_DISCONTINUITY)
      if (!stateChanged && !playingChanged && !positionChanged) return

      tracker?.onPlayerSnapshot(
        playbackState = player.playbackState,
        isPlaying = player.isPlaying,
        seekInProgress = seekInProgress,
      )

      if (seekInProgress && player.playbackState == Player.STATE_READY) {
        seekInProgress = false
      }
    }
  }

  override val ownedProps: Set<String> = emptySet()

  override val exportedEvents: Map<String, String> = mapOf(
    EVENT_REBUFFER_START to "onRebufferStart",
    EVENT_REBUFFER_END to "onRebufferEnd",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
    sourceFailed = false
    tracker = RebufferTracker(
      onStart = { host.emitEvent(EVENT_REBUFFER_START, Arguments.createMap()) },
      onEnd = { host.emitEvent(EVENT_REBUFFER_END, Arguments.createMap()) },
    )
  }

  override fun setProp(name: String, value: Any?) {
    error("BufferingFeature does not own prop '$name'")
  }

  override fun onSourceReset() {
    sourceFailed = false
    tracker?.reset()
    detachPlayerListener()
  }

  override fun onRegisterPlaybackListeners() {
    val host = checkNotNull(host)

    // The SDK creates ExoPlayer when the catalog result is added. These events
    // are the first source-scoped callbacks after that point, so attach the
    // direct listener lazily without depending on SDK internals or a timer.
    listOf(EventType.BUFFERING_STARTED, EventType.BUFFERING_COMPLETED, EventType.DID_PLAY)
      .forEach { eventType ->
        host.registerListener(eventType) {
          if (!sourceFailed) {
            attachPlayerListener()
          }
        }
      }

    host.registerListener(EventType.BUFFERING_COMPLETED) {
      if (!sourceFailed) {
        tracker?.onPrepared()
      }
    }

    listOf(EventType.DID_PAUSE, EventType.DID_STOP, EventType.COMPLETED).forEach { eventType ->
      host.registerListener(eventType) {
        if (!sourceFailed) {
          tracker?.finish()
        }
      }
    }
  }

  override fun onPlaybackError() {
    sourceFailed = true
    tracker?.finish()
    detachPlayerListener()
  }

  // A network-recovery re-prepare stalls playback exactly like a normal
  // rebuffer, so it is reported through the same already-owned events rather
  // than a new one: the app's "reconnecting…" UI for a stall and for a
  // network-loss recovery are the same UI. onEnd() fires once recovery
  // concludes (success or failure) via onNetworkRecoveryEnded; the terminal
  // onPlaybackError above is skipped when recovery ultimately succeeds, so
  // tracker.finish()'s onEnd there is not a duplicate — only one of the two
  // paths ever fires for a given recovery attempt.
  override fun onNetworkRecoveryStarted() {
    if (!sourceFailed) {
      tracker?.forceStart()
    }
  }

  override fun onNetworkRecoveryEnded() {
    if (!sourceFailed) {
      tracker?.finish()
    }
  }

  override fun onDispose() {
    tracker?.reset()
    detachPlayerListener()
    tracker = null
    sourceFailed = true
    host = null
  }

  private fun attachPlayerListener() {
    val host = host ?: return
    if (sourceFailed || host.isDisposed) return

    val display = host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent ?: return
    val player = display.getExoPlayer() ?: return
    if (attachedPlayer === player) return

    detachPlayerListener()
    attachedPlayer = player
    player.addListener(playerListener)
  }

  private fun detachPlayerListener() {
    attachedPlayer?.removeListener(playerListener)
    attachedPlayer = null
    seekInProgress = false
  }

  companion object {
    const val EVENT_REBUFFER_START = "topRebufferStart"
    const val EVENT_REBUFFER_END = "topRebufferEnd"
  }
}

/** Pure state machine for the platform-specific buffering adapter. */
internal class RebufferTracker(
  private val onStart: () -> Unit,
  private val onEnd: () -> Unit,
) {
  private var readyObserved = false
  private var lastIsPlaying = false
  private var rebufferActive = false

  fun onPrepared() {
    readyObserved = true
  }

  fun onPlayerSnapshot(playbackState: Int, isPlaying: Boolean, seekInProgress: Boolean) {
    if (
      playbackState == Player.STATE_BUFFERING &&
      lastIsPlaying &&
      readyObserved &&
      !seekInProgress &&
      !rebufferActive
    ) {
      rebufferActive = true
      onStart()
    }

    if (rebufferActive && playbackState != Player.STATE_BUFFERING) {
      finish()
    }

    lastIsPlaying = isPlaying
  }

  fun finish() {
    if (!rebufferActive) return

    rebufferActive = false
    onEnd()
  }

  /**
   * Reports a stall the tracker did not observe through its own player
   * snapshots — a network-recovery re-prepare starts the stall itself, before
   * ExoPlayer's state necessarily reflects it. A no-op if a stall this
   * tracker did observe (a plain rebuffer) is already active, so recovery
   * during an already-reported stall does not emit a second onStart.
   */
  fun forceStart() {
    if (rebufferActive) return

    rebufferActive = true
    onStart()
  }

  fun reset() {
    finish()
    readyObserved = false
    lastIsPlaying = false
  }
}
