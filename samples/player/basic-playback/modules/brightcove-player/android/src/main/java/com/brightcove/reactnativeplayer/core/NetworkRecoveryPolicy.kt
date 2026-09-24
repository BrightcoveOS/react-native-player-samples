package com.brightcove.reactnativeplayer.core

import androidx.media3.common.PlaybackException

/**
 * Pure decision rules for recovering Android playback after a transient
 * network failure, kept free of ExoPlayer/Android state so the interesting
 * cases are unit-testable on the JVM (see NetworkRecoveryPolicyTest) rather
 * than only exercised through a real device losing connectivity.
 *
 * BrightcovePlayerView owns the actual re-prepare (it needs the live
 * ExoPlayer instance); this object only answers "should it?" and "should
 * playback resume once it does?".
 */
object NetworkRecoveryPolicy {
  /**
   * Whether a PlaybackException's errorCode is a transient network failure
   * worth a single re-prepare attempt, rather than a terminal failure.
   *
   * Keyed off the exact same range PlayerErrorClassifier.playbackErrorCategory
   * already reports as "network" — not a narrower one — so recovery and the
   * `code` a customer sees in a terminal onError agree on what counts as a
   * network problem. A narrower range here would recover only some of the
   * codes the contract calls "network" and let the rest report a terminal
   * `network` error the sample could have silently recovered from instead.
   *
   * Two codes are excluded even though the classifier still calls them
   * "network": ERROR_CODE_IO_NO_PERMISSION and ERROR_CODE_IO_FILE_NOT_FOUND
   * are not transient — no amount of retrying reconnects a resource the app
   * was never allowed to read or that does not exist. Every other code in the
   * range (including ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT, which a
   * mid-request connectivity loss surfaces as — not ...CONNECTION_FAILED,
   * which only covers a connection that never opened) is treated as
   * recoverable.
   *
   * alreadyRecovering guards against re-entering recovery for a second error
   * on the same outage (a stale prepare() racing a fresh one); recovery
   * proceeds only once per stall, and a further error while one is already in
   * flight falls through to the normal terminal-error path. videoLoaded
   * guards against recovering before the source has ever prepared once — a
   * failure that early belongs to the ordinary catalog/source-load error
   * paths, not a mid-playback stall.
   */
  fun isRecoverableNetworkError(
    errorCode: Int?,
    alreadyRecovering: Boolean,
    videoLoaded: Boolean,
  ): Boolean {
    if (alreadyRecovering || !videoLoaded || errorCode == null) return false
    if (errorCode == PlaybackException.ERROR_CODE_IO_NO_PERMISSION ||
      errorCode == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND
    ) {
      return false
    }
    return errorCode in PlaybackException.ERROR_CODE_IO_UNSPECIFIED..
      PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE
  }

  /**
   * Whether a recovered player should resume playback afterward.
   *
   * playbackRequested is the app's last play/pause intent (set by DID_PLAY,
   * cleared by DID_PAUSE/DID_STOP); isPlaying is ExoPlayer's own live state,
   * checked too because a recovery interrupts an in-flight DID_PLAY before it
   * would otherwise land. Recovery must never resume a video the user (or the
   * app) had explicitly paused before the outage — restarting playback the
   * app did not ask for, possibly in someone's pocket, would be a worse
   * outcome than staying paused after a transient network blip.
   */
  fun shouldResumeAfterRecovery(playbackRequested: Boolean, isPlaying: Boolean): Boolean =
    playbackRequested || isPlaying
}
