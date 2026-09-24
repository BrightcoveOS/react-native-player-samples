package com.brightcove.reactnativeplayer.core

/**
 * Tracks the feature source-reset (PlayerFeature.onSourceReset) owed for the
 * source transition currently in flight, and when in a Fabric commit it fires.
 *
 * A transition can be requested from two places within one commit:
 *  - a core source prop (accountId/policyKey/videoId) marks it at setter time,
 *    before commitConfiguration runs;
 *  - a feature-owned source prop (offlineSourceId, videoIds, videoReferenceId,
 *    playlistId, playlistReferenceId, sourceUrl) marks it while features'
 *    setProp run inside commitConfiguration.
 *
 * Both must be honoured in the same commit. The reset has to run before the new
 * source is loaded, so a source-owning feature releases the outgoing source's
 * state before acquiring the incoming one. It must also not outlive the commit:
 * a reset left pending fires against the next, already-playing source on an
 * unrelated prop update, which for the offline feature both leaks the outgoing
 * source's refcount and unblocks deleting the actively-playing download.
 *
 * Callers take once before applying feature props and once after; each take
 * clears the debt. Kept free of Android/SDK state so the ordering is
 * unit-testable on the JVM (see SourceResetSchedulerTest).
 */
internal class SourceResetScheduler(initiallyPending: Boolean = false) {
  private var pending = initiallyPending

  /** True while a reset is owed and not yet taken. */
  val isPending: Boolean
    get() = pending

  /** A source transition was requested; a reset is owed for this commit. */
  fun markPending() {
    pending = true
  }

  /**
   * Take the reset owed at the current phase, clearing it when it fires.
   * Called once before and once after feature props are applied so a reset
   * requested during apply is flushed in the same commit.
   */
  fun takePending(): Boolean {
    if (!pending) return false
    pending = false
    return true
  }
}
