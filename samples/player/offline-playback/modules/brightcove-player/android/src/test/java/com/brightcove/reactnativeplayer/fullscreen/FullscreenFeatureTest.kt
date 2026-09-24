package com.brightcove.reactnativeplayer.fullscreen

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FullscreenFeatureTest {
  @Test
  fun ignoresTransitionWhenAlreadyInTargetOrTransitionInFlight() {
    // If entering and already fullscreen -> ignore
    assertTrue(shouldIgnoreFullscreenTransition(entering = true, isFullscreen = true, pendingTransition = null))
    // If entering and pending ENTER -> ignore
    assertTrue(shouldIgnoreFullscreenTransition(entering = true, isFullscreen = false, pendingTransition = FullscreenTransition.ENTER))
    // If entering and not fullscreen and not pending ENTER -> do not ignore
    assertFalse(shouldIgnoreFullscreenTransition(entering = true, isFullscreen = false, pendingTransition = null))
    assertFalse(shouldIgnoreFullscreenTransition(entering = true, isFullscreen = false, pendingTransition = FullscreenTransition.EXIT))

    // If exiting and not fullscreen -> ignore
    assertTrue(shouldIgnoreFullscreenTransition(entering = false, isFullscreen = false, pendingTransition = null))
    // If exiting and pending EXIT -> ignore
    assertTrue(shouldIgnoreFullscreenTransition(entering = false, isFullscreen = true, pendingTransition = FullscreenTransition.EXIT))
    // If exiting and fullscreen and not pending EXIT -> do not ignore
    assertFalse(shouldIgnoreFullscreenTransition(entering = false, isFullscreen = true, pendingTransition = null))
    assertFalse(shouldIgnoreFullscreenTransition(entering = false, isFullscreen = true, pendingTransition = FullscreenTransition.ENTER))
  }

  // BUG-02 regression: a completed enter must clear the pending transition.
  // Before the state machine, DID_ENTER_FULL_SCREEN set isFullscreen but left
  // pendingTransition = ENTER forever after, so a second enterFullscreen was
  // reported as transition_in_flight instead of already_fullscreen.
  @Test
  fun completedEnterClearsPendingTransition() {
    val state = FullscreenTransitionState()
    assertNull(state.request(entering = true))
    assertEquals(FullscreenTransition.ENTER, state.pendingTransition)

    state.onDidEnter()
    assertTrue(state.isFullscreen)
    assertNull(state.pendingTransition)

    assertEquals(FullscreenCommandRejection.ALREADY_FULLSCREEN, state.request(entering = true))
  }

  @Test
  fun completedExitClearsPendingTransition() {
    val state = FullscreenTransitionState()
    assertNull(state.request(entering = true))
    state.onDidEnter()

    assertNull(state.request(entering = false))
    assertEquals(FullscreenTransition.EXIT, state.pendingTransition)

    state.onDidExit()
    assertFalse(state.isFullscreen)
    assertNull(state.pendingTransition)

    assertEquals(FullscreenCommandRejection.NOT_FULLSCREEN, state.request(entering = false))
  }

  @Test
  fun requestDuringInFlightTransitionIsTypedAsInFlight() {
    val state = FullscreenTransitionState()
    assertNull(state.request(entering = true))
    // A second enter while the first is still in flight is in-flight, not
    // already-fullscreen (the player is not fullscreen yet).
    assertEquals(FullscreenCommandRejection.TRANSITION_IN_FLIGHT, state.request(entering = true))
  }

  @Test
  fun sdkInitiatedTransitionBlocksImperativeRequestsWhileInFlight() {
    val state = FullscreenTransitionState()
    state.onSdkInitiated(FullscreenTransition.ENTER)
    assertEquals(FullscreenCommandRejection.TRANSITION_IN_FLIGHT, state.request(entering = true))

    state.onDidEnter()
    assertEquals(FullscreenCommandRejection.ALREADY_FULLSCREEN, state.request(entering = true))
    assertNull(state.request(entering = false))
  }

  @Test
  fun synchronousExitMarksNotFullscreenWithExitPending() {
    val state = FullscreenTransitionState()
    assertNull(state.request(entering = true))
    state.onDidEnter()

    state.beginSynchronousExit()
    assertFalse(state.isFullscreen)
    assertEquals(FullscreenTransition.EXIT, state.pendingTransition)

    // The SDK's eventual completion clears the pending exit.
    state.onDidExit()
    assertNull(state.pendingTransition)
    assertEquals(FullscreenCommandRejection.NOT_FULLSCREEN, state.request(entering = false))
  }
}
