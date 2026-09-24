package com.brightcove.reactnativeplayer.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers the resume decision that follows a fullscreen reparent. The
 * interesting cases are the invalidations — a source swap, an explicit pause,
 * a dispose, or a backgrounded host arriving before the posted restart runs —
 * because each of those becomes "fullscreen restarted a video nobody asked to
 * play" if the decision lets the resume through.
 */
class FullscreenReparentPolicyTest {
  private fun decide(
    playbackRequested: Boolean = true,
    capturedGeneration: Int = 7,
    currentGeneration: Int = 7,
    disposed: Boolean = false,
    disposeRequested: Boolean = false,
    hostResumed: Boolean = true,
    attachedToWindow: Boolean = true,
  ) = FullscreenReparentPolicy.shouldResumeAfterReparent(
    playbackRequested = playbackRequested,
    capturedGeneration = capturedGeneration,
    currentGeneration = currentGeneration,
    disposed = disposed,
    disposeRequested = disposeRequested,
    hostResumed = hostResumed,
    attachedToWindow = attachedToWindow,
  )

  @Test
  fun resumesWhenTheSameSourceIsStillWantedAndForegrounded() {
    assertTrue(decide())
  }

  @Test
  fun doesNotResumeAfterAnExplicitPause() {
    assertFalse(decide(playbackRequested = false))
  }

  @Test
  fun doesNotResumeAcrossASourceChange() {
    // A source swap bumps the generation; the captured resume belongs to the
    // old source and must not start the new one.
    assertFalse(decide(capturedGeneration = 7, currentGeneration = 8))
  }

  @Test
  fun doesNotResumeWhileDisposing() {
    assertFalse(decide(disposed = true))
    assertFalse(decide(disposeRequested = true))
  }

  @Test
  fun doesNotResumeWhileBackgroundedOrDetached() {
    assertFalse(decide(hostResumed = false))
    assertFalse(decide(attachedToWindow = false))
  }

  @Test
  fun everyInvalidationIsIndependentlySufficient() {
    assertFalse(decide(playbackRequested = false))
    assertFalse(decide(currentGeneration = 99))
    assertFalse(decide(disposed = true))
    assertFalse(decide(disposeRequested = true))
    assertFalse(decide(hostResumed = false))
    assertFalse(decide(attachedToWindow = false))
  }
}
