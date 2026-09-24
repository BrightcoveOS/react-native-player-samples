package com.brightcove.reactnativeplayer.fullscreen

import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Reports Brightcove's fullscreen state and forwards imperative enter/exit
 * requests to the SDK's public event-driven fullscreen controller.
 */
internal enum class FullscreenTransition { ENTER, EXIT }

// A transition request is a no-op when the target state is already active or
// the opposite transition is still in flight. Extracted and unit-tested so
// the three-state pendingTransition (none / enter pending / exit pending) is
// typed rather than string-compared: a typo in either branch of this guard
// silently stops reporting fullscreen changes to JS.
internal fun shouldIgnoreFullscreenTransition(
  entering: Boolean,
  isFullscreen: Boolean,
  pendingTransition: FullscreenTransition?,
): Boolean {
  return (entering && (isFullscreen || pendingTransition == FullscreenTransition.ENTER)) ||
    (!entering && (!isFullscreen || pendingTransition == FullscreenTransition.EXIT))
}

internal enum class FullscreenCommandRejection(val nativeCode: String) {
  ALREADY_FULLSCREEN("already_fullscreen"),
  NOT_FULLSCREEN("not_fullscreen"),
  TRANSITION_IN_FLIGHT("transition_in_flight"),
}

/**
 * The fullscreen transition state machine: whether the player is fullscreen
 * and which transition (if any) is pending. Both completed transitions clear
 * the pending flag — the enter path's clear matters because without it the
 * pending flag outlives the transition it named, so a second enterFullscreen
 * after a completed enter was reported as transition_in_flight instead of
 * already_fullscreen.
 *
 * Extracted as a class (the QueueCompletionState pattern) so the state
 * lifecycle is unit-testable without an ExoPlayer: the feature delegates
 * every isFullscreen/pendingTransition read and write to it.
 */
internal class FullscreenTransitionState {
  var isFullscreen = false
    private set
  var pendingTransition: FullscreenTransition? = null
    private set

  /**
   * Decision for an imperative transition request: null when the request
   * proceeds (the pending flag is set), or the typed rejection to report.
   */
  fun request(entering: Boolean): FullscreenCommandRejection? {
    if (shouldIgnoreFullscreenTransition(entering, isFullscreen, pendingTransition)) {
      return when {
        pendingTransition != null -> FullscreenCommandRejection.TRANSITION_IN_FLIGHT
        entering -> FullscreenCommandRejection.ALREADY_FULLSCREEN
        else -> FullscreenCommandRejection.NOT_FULLSCREEN
      }
    }
    pendingTransition = if (entering) FullscreenTransition.ENTER else FullscreenTransition.EXIT
    return null
  }

  /** The SDK reported the enter completed: fullscreen now, nothing pending. */
  fun onDidEnter() {
    isFullscreen = true
    pendingTransition = null
  }

  /** The SDK reported the exit completed: not fullscreen, nothing pending. */
  fun onDidExit() {
    isFullscreen = false
    pendingTransition = null
  }

  /**
   * A transition initiated outside the imperative commands (the SDK's own
   * fullscreen controls): recorded as pending so an imperative request in
   * the same direction is reported as in-flight rather than double-issued.
   */
  fun onSdkInitiated(transition: FullscreenTransition) {
    pendingTransition = transition
  }

  /**
   * The core is leaving fullscreen synchronously (source reset/dispose):
   * request the exit and mark not-fullscreen now; the SDK's eventual
   * DID_EXIT completes the cycle.
   */
  fun beginSynchronousExit() {
    pendingTransition = FullscreenTransition.EXIT
    isFullscreen = false
  }
}

class FullscreenFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private val transitionState = FullscreenTransitionState()
  private var listenersRegistered = false
  private var acceptTransitions = false
  private var disposing = false
  private var pictureInPictureActive = false

  private val isFullscreen: Boolean get() = transitionState.isFullscreen
  private val pendingTransition: FullscreenTransition? get() = transitionState.pendingTransition

  override val ownedProps = emptySet<String>()
  override val supportedCommands = setOf("enterFullscreen", "exitFullscreen")
  override val exportedEvents = mapOf(EVENT_FULLSCREEN_CHANGED to "onFullscreenChanged")

  override fun attach(host: FeatureHost) {
    this.host = host
    host.registerPersistentListener(EventType.DID_ENTER_PICTURE_IN_PICTURE_MODE) {
      pictureInPictureActive = true
    }
    host.registerPersistentListener(EventType.DID_EXIT_PICTURE_IN_PICTURE_MODE) {
      pictureInPictureActive = false
      host.hostView.post {
        if (!host.isDisposed && !isFullscreen && !host.isInPictureInPictureMode) {
          host.exitFullscreenLayout()
        }
      }
    }
  }

  override fun setProp(name: String, value: Any?) {
    error("FullscreenFeature owns no props; received '$name'")
  }

  override fun handleCommand(name: String): Boolean {
    check(name in supportedCommands) { "FullscreenFeature does not support command '$name'" }
    if (disposing || host.isDisposed) return false
    val entering = name == "enterFullscreen"
    if (entering && (host.boundActivity == null || !host.hostView.isAttachedToWindow)) {
      host.emitCommandError(
        command = name,
        code = "not_ready",
        message = "Fullscreen is not available until the player view is attached",
        nativeCode = "player_view_not_available",
      )
      return true
    }
    // A command that matches the current state, or lands mid-transition, is a
    // typed invalid_state — the same table iOS exposes (already_fullscreen /
    // not_fullscreen / transition_in_flight), not a silent success.
    transitionState.request(entering)?.let { rejection ->
      host.emitCommandError(
        command = name,
        code = "invalid_state",
        message = "The '$name' command cannot run in the player's current fullscreen state",
        nativeCode = rejection.nativeCode,
      )
      return true
    }

    host.eventEmitter.emitNow(
      if (name == "enterFullscreen") EventType.ENTER_FULL_SCREEN else EventType.EXIT_FULL_SCREEN,
      emptyMap<String, Any>(),
    )
    return true
  }

  override fun onRegisterPlaybackListeners() {
    if (listenersRegistered) return
    listenersRegistered = true
    // Fullscreen belongs to this player view, not to one video source. Keep
    // these listeners persistent so an exit requested during source reset can
    // still deliver its authoritative DID_EXIT event after source listeners
    // have been invalidated.
    host.registerPersistentListener(EventType.DID_ENTER_FULL_SCREEN) {
      transitionState.onDidEnter()
      host.hostView.post {
        if (host.isDisposed || pictureInPictureActive || host.isInPictureInPictureMode) {
          return@post
        }
        if (host.enterFullscreenLayout()) {
          if (acceptTransitions && !disposing) emit(active = true)
        } else {
          // The SDK changed its screen mode/window flags, but the Activity-root
          // overlay could not be created. Restore the SDK state and report a
          // typed failure instead of lying to JS that visual fullscreen is
          // active.
          transitionState.beginSynchronousExit()
          host.eventEmitter.emitNow(EventType.EXIT_FULL_SCREEN, emptyMap<String, Any>())
          host.emitCommandError(
            command = "enterFullscreen",
            code = "not_ready",
            message = "Fullscreen could not attach the player to the Activity root",
            nativeCode = "fullscreen_layout_unavailable",
          )
        }
      }
    }
    host.registerPersistentListener(EventType.DID_EXIT_FULL_SCREEN) {
      // Capture the pending state before the completed exit clears it: the
      // report decision below needs to know whether an imperative exit (or
      // a source-reset/dispose-initiated one) was in flight when the SDK
      // completed it.
      val exitWasPending = pendingTransition == FullscreenTransition.EXIT
      transitionState.onDidExit()
      host.hostView.post {
        if (!host.isDisposed && !pictureInPictureActive && !host.isInPictureInPictureMode) {
          host.exitFullscreenLayout()
        }
      }
      val reportExit = acceptTransitions || (exitWasPending && !disposing)
      if (reportExit) emit(active = false)
    }
    host.registerPersistentListener(EventType.ENTER_FULL_SCREEN) {
      if (acceptTransitions) transitionState.onSdkInitiated(FullscreenTransition.ENTER)
    }
    host.registerPersistentListener(EventType.EXIT_FULL_SCREEN) {
      if (acceptTransitions) transitionState.onSdkInitiated(FullscreenTransition.EXIT)
    }
    host.registerPersistentListener(EventType.DID_SET_VIDEO) {
      // A source reset suppresses late events from the outgoing source. The
      // next native video-set event is the ordering boundary for the new one.
      acceptTransitions = true
    }
  }

  override fun onSourceWillReset() {
    acceptTransitions = false
    if (!pictureInPictureActive && !host.isInPictureInPictureMode) {
      host.exitFullscreenLayout()
    }
    if (!isFullscreen && pendingTransition != FullscreenTransition.ENTER) return
    // markSourceDirty calls this while the old source listeners are still
    // attached. emitNow (not emit) is required: the plain emit is asynchronous,
    // so the exit request could be dispatched only after the core has already
    // unregistered the persistent listeners — dropping it and leaving the
    // Activity's fullscreen window flags set. A synchronous dispatch lets the
    // SDK restore those flags before the source is invalidated.
    transitionState.beginSynchronousExit()
    host.eventEmitter.emitNow(EventType.EXIT_FULL_SCREEN, emptyMap<String, Any>())
  }

  override fun onDispose() {
    disposing = true
    acceptTransitions = false
    if (!pictureInPictureActive && !host.isInPictureInPictureMode) {
      host.exitFullscreenLayout()
    }
    if (!isFullscreen && pendingTransition != FullscreenTransition.ENTER) return
    // Dispose is called before the core removes persistent listeners, so this
    // synchronous SDK request can restore Activity window flags before the
    // render view and its exit listener are destroyed. The core removes the
    // bridge-owned overlay separately even if PiP currently owns the window.
    transitionState.beginSynchronousExit()
    host.eventEmitter.emitNow(EventType.EXIT_FULL_SCREEN, emptyMap<String, Any>())
  }

  private fun emit(active: Boolean) {
    host.emitEvent(
      EVENT_FULLSCREEN_CHANGED,
      Arguments.createMap().apply { putBoolean("active", active) },
    )
  }

  private companion object {
    const val EVENT_FULLSCREEN_CHANGED = "topFullscreenChanged"
  }
}
