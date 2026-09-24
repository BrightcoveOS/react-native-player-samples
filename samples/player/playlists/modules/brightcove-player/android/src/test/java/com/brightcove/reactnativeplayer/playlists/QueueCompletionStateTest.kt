package com.brightcove.reactnativeplayer.playlists

import org.junit.Assert.assertEquals
import org.junit.Test

class QueueCompletionStateTest {
  @Test
  fun waitsUntilTerminalIsObserved() {
    val state = QueueCompletionState()
    assertEquals(
      QueueCompletionAction.WAIT,
      state.reconcile(resolvedCount = 3, resolutionInProgress = false, nativeQueueSize = 3, nativeCurrentIndex = 0),
    )
  }

  @Test
  fun advancesWhenMoreItemsResolvedAfterTerminalObserved() {
    val state = QueueCompletionState()
    state.observeTerminal(0)
    assertEquals(
      QueueCompletionAction.ADVANCE,
      state.reconcile(resolvedCount = 2, resolutionInProgress = false, nativeQueueSize = 2, nativeCurrentIndex = 0),
    )
  }

  @Test
  fun doesNotDoubleAdvanceOnceRequested() {
    val state = QueueCompletionState()
    state.observeTerminal(0)
    state.markAdvanceRequested()
    assertEquals(
      QueueCompletionAction.WAIT,
      state.reconcile(resolvedCount = 2, resolutionInProgress = false, nativeQueueSize = 2, nativeCurrentIndex = 0),
    )
  }

  @Test
  fun completesOnceLastItemResolvedAndTerminal() {
    val state = QueueCompletionState()
    state.observeTerminal(1)
    assertEquals(
      QueueCompletionAction.COMPLETE,
      state.reconcile(resolvedCount = 2, resolutionInProgress = false, nativeQueueSize = 2, nativeCurrentIndex = 1),
    )
  }

  @Test
  fun completionEmittedOnlyOnce() {
    val state = QueueCompletionState()
    state.observeTerminal(1)
    state.reconcile(resolvedCount = 2, resolutionInProgress = false, nativeQueueSize = 2, nativeCurrentIndex = 1)
    assertEquals(
      QueueCompletionAction.WAIT,
      state.reconcile(resolvedCount = 2, resolutionInProgress = false, nativeQueueSize = 2, nativeCurrentIndex = 1),
    )
  }

  @Test
  fun waitsWhileResolutionStillInProgress() {
    val state = QueueCompletionState()
    state.observeTerminal(0)
    assertEquals(
      QueueCompletionAction.WAIT,
      state.reconcile(resolvedCount = 1, resolutionInProgress = true, nativeQueueSize = 1, nativeCurrentIndex = 0),
    )
  }

  @Test
  fun neverCompletesWhileRepeatModeIsNotOff() {
    val state = QueueCompletionState()
    state.observeTerminal(1)
    assertEquals(
      QueueCompletionAction.WAIT,
      state.reconcile(
        resolvedCount = 2,
        resolutionInProgress = false,
        nativeQueueSize = 2,
        nativeCurrentIndex = 1,
        repeatMode = "all",
      ),
    )
  }

  @Test
  fun transitioningAwayFromTerminalClearsIt() {
    val state = QueueCompletionState()
    state.observeTerminal(0)
    state.onTransition(1)
    assertEquals(
      QueueCompletionAction.WAIT,
      state.reconcile(resolvedCount = 2, resolutionInProgress = false, nativeQueueSize = 2, nativeCurrentIndex = 1),
    )
  }

  @Test
  fun resetClearsAllState() {
    val state = QueueCompletionState()
    state.observeTerminal(1)
    state.reconcile(resolvedCount = 2, resolutionInProgress = false, nativeQueueSize = 2, nativeCurrentIndex = 1)
    state.reset()
    assertEquals(false, state.terminalObserved)
    assertEquals(false, state.completionEmitted)
    assertEquals(-1, state.terminalIndex)
  }
}
