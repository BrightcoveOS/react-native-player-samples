package com.brightcove.reactnativeplayer.playlists

internal enum class QueueCompletionAction {
  WAIT,
  ADVANCE,
  COMPLETE,
}

/**
 * Tracks whether the native SDK's queue has reached its last item and, if so,
 * whether the queue as a whole is done (repeatMode "off") or should loop
 * (repeatMode "all"/"one" is handled by PlaylistsFeature directly and never
 * reaches COMPLETE here).
 *
 * The native queue's own COMPLETED event and current-index bookkeeping are the
 * source of truth; this only reconciles resolution still being in-flight
 * (more items may append after the currently-last resolved item completes)
 * against what has already been observed, so `onQueueCompleted` fires exactly
 * once and only once every item has been resolved.
 */
internal class QueueCompletionState {
  var terminalIndex = -1
    private set
  var terminalObserved = false
    private set
  var completionEmitted = false
    private set
  private var advanceRequested = false

  fun reset() {
    terminalIndex = -1
    terminalObserved = false
    completionEmitted = false
    advanceRequested = false
  }

  fun observeTerminal(index: Int) {
    if (completionEmitted || index < 0) return
    if (!terminalObserved || terminalIndex != index) {
      advanceRequested = false
    }
    terminalObserved = true
    terminalIndex = index
  }

  fun markAdvanceRequested() {
    if (terminalObserved) {
      advanceRequested = true
    }
  }

  fun onTransition(index: Int) {
    if (terminalObserved && index != terminalIndex) {
      terminalIndex = -1
      terminalObserved = false
      advanceRequested = false
    }
  }

  fun reconcile(
    resolvedCount: Int,
    resolutionInProgress: Boolean,
    nativeQueueSize: Int,
    nativeCurrentIndex: Int,
    repeatMode: String = "off",
  ): QueueCompletionAction {
    if (!terminalObserved || completionEmitted || resolvedCount == 0) {
      return QueueCompletionAction.WAIT
    }

    if (repeatMode != "off") {
      return QueueCompletionAction.WAIT
    }

    if (terminalIndex < resolvedCount - 1) {
      // More items resolved after the terminal one was observed: reconcile an
      // automatic transition only while the native player is still parked on
      // the terminal physical item. If native current index has already
      // advanced on its own, rely on that transition and do not double-advance.
      if (!advanceRequested && terminalIndex + 1 < nativeQueueSize && nativeCurrentIndex == terminalIndex) {
        advanceRequested = true
        return QueueCompletionAction.ADVANCE
      }
      return QueueCompletionAction.WAIT
    }

    if (!resolutionInProgress &&
      terminalIndex == nativeQueueSize - 1 &&
      nativeCurrentIndex == terminalIndex
    ) {
      completionEmitted = true
      return QueueCompletionAction.COMPLETE
    }

    return QueueCompletionAction.WAIT
  }
}
