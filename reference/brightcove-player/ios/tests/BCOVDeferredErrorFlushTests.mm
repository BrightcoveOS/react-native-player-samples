#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../core/BCOVDeferredErrorFlush.h"

// Pins the deferred-playback-error flush race rule: an error deferred under
// request A must never surface after the source swapped to request B, and the
// terminal-state gates (sourceFailed/invalidated/no-pending) still hold.
@interface BCOVDeferredErrorFlushTests : XCTestCase
@end

@implementation BCOVDeferredErrorFlushTests

- (void)testFreshDeferralOnTheSameGenerationFlushes
{
  XCTAssertTrue(BCOVShouldFlushDeferredPlaybackError(
      /*deferredGeneration*/ 7, /*currentGeneration*/ 7,
      /*deferredToken*/ 3, /*currentToken*/ 3,
      /*sourceFailed*/ NO, /*invalidated*/ NO, /*hasPendingError*/ YES));
}

- (void)testSourceSwapBetweenDeferAndFlushSuppressesTheError
{
  // Source A deferred the error; requestSourceReload bumped the generation to
  // B before the main-queue flush ran. The error belongs to A and must not
  // be attributed to B.
  XCTAssertFalse(BCOVShouldFlushDeferredPlaybackError(
      7, 8,
      3, 3,
      NO, NO, YES));
}

- (void)testReplacedDeferralOnTheSameGenerationSuppressesTheOldError
{
  // A second defer on the same generation replaced the pending error; the
  // first deferral's token no longer names the pending error.
  XCTAssertFalse(BCOVShouldFlushDeferredPlaybackError(
      7, 7,
      3, 4,
      NO, NO, YES));
}

- (void)testNoPendingErrorNeverFlushes
{
  XCTAssertFalse(BCOVShouldFlushDeferredPlaybackError(7, 7, 3, 3, NO, NO, NO));
}

- (void)testSourceFailedSuppressesTheFlush
{
  XCTAssertFalse(BCOVShouldFlushDeferredPlaybackError(7, 7, 3, 3, YES, NO, YES));
}

- (void)testInvalidatedSuppressesTheFlush
{
  XCTAssertFalse(BCOVShouldFlushDeferredPlaybackError(7, 7, 3, 3, NO, YES, YES));
}

@end
