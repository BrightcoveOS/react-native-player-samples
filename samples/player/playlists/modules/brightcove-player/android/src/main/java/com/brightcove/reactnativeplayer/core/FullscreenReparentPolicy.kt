package com.brightcove.reactnativeplayer.core

/**
 * Pure decision rules for the playback resume that follows a fullscreen
 * reparent.
 *
 * Moving the Brightcove video view between its React Native parent and the
 * Activity-root fullscreen overlay detaches its rendering surface, which the
 * SDK reports as a pause. The core compensates by restarting playback once the
 * new parent is attached.
 *
 * That compensation must never outlive the transition it was scheduled for. A
 * source swap, an explicit pause, a backgrounded host, or a dispose that lands
 * before the posted restart runs all invalidate the resume — otherwise the fix
 * for "fullscreen paused my video" becomes "fullscreen started a video the
 * caller never asked to play", the worse failure.
 *
 * Kept free of Android/SDK state so these races are unit-testable on the JVM
 * (see FullscreenReparentPolicyTest) instead of only reproducible by timing a
 * real transition.
 */
internal object FullscreenReparentPolicy {
  /**
   * Whether a resume captured before a fullscreen reparent may still run.
   *
   * The caller schedules a resume only when playback was wanted at capture
   * time, and cancels it on an explicit play/pause; this decides whether the
   * surrounding state still permits resuming.
   */
  fun shouldResumeAfterReparent(
    playbackRequested: Boolean,
    capturedGeneration: Int,
    currentGeneration: Int,
    disposed: Boolean,
    disposeRequested: Boolean,
    hostResumed: Boolean,
    attachedToWindow: Boolean,
  ): Boolean {
    if (!playbackRequested) return false
    if (disposed || disposeRequested) return false
    if (capturedGeneration != currentGeneration) return false
    if (!hostResumed || !attachedToWindow) return false
    return true
  }
}
