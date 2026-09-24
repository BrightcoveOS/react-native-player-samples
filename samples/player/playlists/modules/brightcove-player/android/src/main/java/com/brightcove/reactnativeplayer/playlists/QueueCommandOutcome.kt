package com.brightcove.reactnativeplayer.playlists

/**
 * Pure decision for the `next` imperative command. The feature performs the
 * side effects (seek/retry/error) in the caller; this is the outcome only,
 * so the queue-command contract is unit-testable without an ExoPlayer.
 */
internal enum class QueueCommandOutcome {
  /** A next item exists natively (or repeat-all wraps) — seek it. */
  ADVANCED,

  /** Nothing queued yet or resolution may still add items — retry later. */
  PENDING,

  /** At the last resolved item, repeat off — the queue cannot advance. */
  QUEUE_AT_END,

  /** This feature owns no loaded queue for the current request. */
  QUEUE_NOT_LOADED,
}

/**
 * Decides the `next` command outcome from queue state, mirroring
 * PlaylistsFeature.advanceQueue's branches in decision form:
 *
 * - A queue that is not loaded (no videoIds, no active request generation,
 *   or a superseded one) cannot advance.
 * - A native next item exists → advance.
 * - repeatMode "all" wraps to the first item, but only once resolution
 *   finished: wrapping while more of videoIds might still resolve would jump
 *   back to item 0 even though a genuine next item could be about to arrive.
 * - While resolution is in flight (or nothing resolved yet), the request is
 *   pending — retried as items resolve.
 * - Otherwise the queue is at its end with repeat off.
 */
internal fun nextQueueCommandOutcome(
  queueLoaded: Boolean,
  hasNextMediaItem: Boolean,
  resolutionInProgress: Boolean,
  resolvedCount: Int,
  repeatMode: String,
): QueueCommandOutcome {
  if (!queueLoaded) return QueueCommandOutcome.QUEUE_NOT_LOADED
  if (hasNextMediaItem) return QueueCommandOutcome.ADVANCED
  if (repeatMode == "all" && resolvedCount > 0 && !resolutionInProgress) {
    return QueueCommandOutcome.ADVANCED
  }
  if (resolvedCount == 0 || resolutionInProgress) return QueueCommandOutcome.PENDING
  return QueueCommandOutcome.QUEUE_AT_END
}

/** Typed outcome of the `previous` imperative command's decision table. */
internal enum class PreviousQueueCommandOutcome {
  /** A previous item exists natively — seek it. */
  PREVIOUS,

  /** At the first item with repeatMode "all" — wrap to the last item. */
  WRAP_TO_LAST,

  /** At the first item without wrap — restart the current item. */
  RESTART_CURRENT,
}

/**
 * Decides the `previous` command outcome from queue state. Resolution is
 * deliberately not an input: a previous item can only exist among items
 * already resolved, so the native-queue state alone decides — matching iOS,
 * which services previous from already-applied state during resolution.
 */
internal fun previousQueueCommandOutcome(
  hasPreviousMediaItem: Boolean,
  repeatMode: String,
  resolvedCount: Int,
): PreviousQueueCommandOutcome {
  if (hasPreviousMediaItem) return PreviousQueueCommandOutcome.PREVIOUS
  if (repeatMode == "all" && resolvedCount > 0) return PreviousQueueCommandOutcome.WRAP_TO_LAST
  return PreviousQueueCommandOutcome.RESTART_CURRENT
}
