#import "BCOVDeferredErrorFlush.h"

BOOL BCOVShouldFlushDeferredPlaybackError(
    NSUInteger deferredGeneration,
    NSUInteger currentGeneration,
    NSUInteger deferredToken,
    NSUInteger currentToken,
    BOOL sourceFailed,
    BOOL invalidated,
    BOOL hasPendingError)
{
  if (!hasPendingError || sourceFailed || invalidated) {
    return NO;
  }
  // The generation gate is authoritative: an error deferred for a request
  // that is no longer current belongs to a superseded source, even when the
  // token bookkeeping was not invalidated (the token is defense-in-depth for
  // a defer-then-defer replacement on the same generation).
  if (deferredGeneration != currentGeneration) {
    return NO;
  }
  return deferredToken == currentToken;
}
