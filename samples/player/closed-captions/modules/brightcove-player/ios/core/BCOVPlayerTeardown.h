#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Whether a feature-owned teardown completion may finish the current player
 * teardown. Both the pending flag and the monotonic token are required: after
 * a forced completion, a feature's late callback must not finish a newer
 * teardown that happened to set the boolean pending flag again.
 */
BOOL BCOVShouldCompletePlayerTearDown(
    NSUInteger completionToken,
    NSUInteger currentToken,
    BOOL teardownPending);

NS_ASSUME_NONNULL_END
