package com.brightcove.reactnativeplayer.playlists

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins the queue command decision table shared by the feature and both
 * platforms' contract: no-queue, at-end with repeat off, repeat-all wrap,
 * pending during resolution, and the native-next fast path.
 */
class QueueCommandOutcomeTest {
  @Test
  fun noLoadedQueueCannotAdvance() {
    assertEquals(
      QueueCommandOutcome.QUEUE_NOT_LOADED,
      nextQueueCommandOutcome(
        queueLoaded = false,
        hasNextMediaItem = false,
        resolutionInProgress = false,
        resolvedCount = 0,
        repeatMode = "off",
      ),
    )
  }

  @Test
  fun atEndWithRepeatOffIsQueueAtEnd() {
    assertEquals(
      QueueCommandOutcome.QUEUE_AT_END,
      nextQueueCommandOutcome(
        queueLoaded = true,
        hasNextMediaItem = false,
        resolutionInProgress = false,
        resolvedCount = 3,
        repeatMode = "off",
      ),
    )
  }

  @Test
  fun atEndWithRepeatAllWraps() {
    assertEquals(
      QueueCommandOutcome.ADVANCED,
      nextQueueCommandOutcome(
        queueLoaded = true,
        hasNextMediaItem = false,
        resolutionInProgress = false,
        resolvedCount = 3,
        repeatMode = "all",
      ),
    )
  }

  @Test
  fun repeatAllDoesNotWrapWhileResolutionStillInProgress() {
    // Wrapping mid-resolution could jump to item 0 even though a genuine
    // next item is about to resolve.
    assertEquals(
      QueueCommandOutcome.PENDING,
      nextQueueCommandOutcome(
        queueLoaded = true,
        hasNextMediaItem = false,
        resolutionInProgress = true,
        resolvedCount = 3,
        repeatMode = "all",
      ),
    )
  }

  @Test
  fun nativeNextItemWins() {
    assertEquals(
      QueueCommandOutcome.ADVANCED,
      nextQueueCommandOutcome(
        queueLoaded = true,
        hasNextMediaItem = true,
        resolutionInProgress = true,
        resolvedCount = 1,
        repeatMode = "off",
      ),
    )
  }

  @Test
  fun nothingResolvedYetIsPending() {
    // The queue is loaded but still resolving its first item: the request
    // is remembered and retried as soon as an item queues — not an error.
    assertEquals(
      QueueCommandOutcome.PENDING,
      nextQueueCommandOutcome(
        queueLoaded = true,
        hasNextMediaItem = false,
        resolutionInProgress = true,
        resolvedCount = 0,
        repeatMode = "off",
      ),
    )
  }

  @Test
  fun resolutionFinishedButNothingResolvedStaysPendingForRetry() {
    // Every id failed to resolve: pendingAdvance is dropped by the
    // resolution-finished path, and the empty-queue aggregation reports the
    // source-level error — the command decision itself stays PENDING so the
    // internal retry path never emits queue_at_end.
    assertEquals(
      QueueCommandOutcome.PENDING,
      nextQueueCommandOutcome(
        queueLoaded = true,
        hasNextMediaItem = false,
        resolutionInProgress = false,
        resolvedCount = 0,
        repeatMode = "off",
      ),
    )
  }

  // `previous` is decided by the native queue alone, never gated on
  // resolutionInProgress: a previous item can only exist among already-
  // resolved items, so "previous during resolution" acts on the applied
  // native-queue state — matching iOS, which services previous during
  // resolution (previously Android blanket-rejected here).
  @Test
  fun previousDuringResolutionWithAppliedItemMovesBack() {
    assertEquals(
      PreviousQueueCommandOutcome.PREVIOUS,
      previousQueueCommandOutcome(
        hasPreviousMediaItem = true,
        repeatMode = "off",
        resolvedCount = 2,
      ),
    )
  }

  @Test
  fun previousAtFirstItemWithRepeatOffRestartsCurrent() {
    assertEquals(
      PreviousQueueCommandOutcome.RESTART_CURRENT,
      previousQueueCommandOutcome(
        hasPreviousMediaItem = false,
        repeatMode = "off",
        resolvedCount = 3,
      ),
    )
  }

  @Test
  fun previousAtFirstItemWithRepeatAllWrapsToLast() {
    assertEquals(
      PreviousQueueCommandOutcome.WRAP_TO_LAST,
      previousQueueCommandOutcome(
        hasPreviousMediaItem = false,
        repeatMode = "all",
        resolvedCount = 3,
      ),
    )
  }
}
