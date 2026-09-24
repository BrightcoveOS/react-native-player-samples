#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Pure decision for the deferred-playback-error flush (BUG-07's race): a
 * playback error deferred on the main queue must only surface while it still
 * belongs to the request it was deferred under. A source swap bumps the
 * request generation in the next main-loop turn; without the generation
 * check the old source's deferred error is attributed to the new source.
 *
 * Inputs are the snapshots taken at defer time (generation, token) and the
 * values read at flush time. Extracted so the race rule is unit-testable in
 * the Foundation-only core test target.
 */
BOOL BCOVShouldFlushDeferredPlaybackError(
    NSUInteger deferredGeneration,
    NSUInteger currentGeneration,
    NSUInteger deferredToken,
    NSUInteger currentToken,
    BOOL sourceFailed,
    BOOL invalidated,
    BOOL hasPendingError);

NS_ASSUME_NONNULL_END
