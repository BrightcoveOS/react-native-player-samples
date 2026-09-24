#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Typed outcomes of the iOS queue-command decision table, mirroring Android's
 * QueueCommandOutcome so both platforms report identical contracts (the web
 * implementation follows the same table). The playlists feature maps its
 * playback-order state onto these pure functions; the imperative command
 * path (handleCommand) emits the typed errors, while the internal retry path
 * stays silent.
 */
typedef NS_ENUM(NSUInteger, BCOVQueueCommandOutcome) {
  /** A next item exists in the applied playback order (or repeat-all wraps). */
  BCOVQueueCommandOutcomeAdvanced,
  /** Resolution may still add items — the request is deferred and retried. */
  BCOVQueueCommandOutcomePending,
  /** At the last resolved item, resolution finished, repeat does not wrap. */
  BCOVQueueCommandOutcomeAtEnd,
  /** This feature owns no loaded queue for the current request. */
  BCOVQueueCommandOutcomeNotLoaded,
};

/**
 * Decides the `next` command outcome from the applied playback-order state.
 *
 * - An applied next item (or repeat-all wrap, only after resolution finished:
 *   wrapping mid-resolution could jump to item 0 although a genuine next item
 *   is about to resolve) → Advanced.
 * - While resolution is in flight (or nothing applied yet) → Pending: the
 *   request is remembered and retried as items apply.
 * - Otherwise the queue is at its end with a repeat mode that does not wrap.
 */
FOUNDATION_EXPORT BCOVQueueCommandOutcome BCOVNextQueueCommandOutcome(
    NSInteger orderCount,
    NSInteger currentOrderIndex,
    BOOL resolutionInProgress,
    BOOL repeatModeAll);

/**
 * Decides the `previous` command outcome. Resolution is deliberately not an
 * input: a previous item can only exist among already-applied items, so the
 * applied state alone decides — matching Android.
 */
typedef NS_ENUM(NSUInteger, BCOVPreviousQueueCommandOutcomeEnum) {
  /** An applied previous item exists. */
  BCOVPreviousQueueCommandOutcomePrevious,
  /** At the first item with repeatMode "all" — wrap to the last item. */
  BCOVPreviousQueueCommandOutcomeWrapToLast,
  /** At the first item without wrap — restart the current item. */
  BCOVPreviousQueueCommandOutcomeRestartCurrent,
};

FOUNDATION_EXPORT BCOVPreviousQueueCommandOutcomeEnum BCOVPreviousQueueCommandOutcome(
    NSInteger orderCount,
    NSInteger currentOrderIndex,
    BOOL repeatModeAll);

/** The typed queue_at_end command-error message, shared verbatim by platforms. */
FOUNDATION_EXPORT NSString *BCOVQueueAtEndMessage(void);

/** The typed queue_not_loaded command-error message for `next`. */
FOUNDATION_EXPORT NSString *BCOVNextQueueNotLoadedMessage(void);

/** The typed queue_not_loaded command-error message for `previous`. */
FOUNDATION_EXPORT NSString *BCOVPreviousQueueNotLoadedMessage(void);

NS_ASSUME_NONNULL_END
