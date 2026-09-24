#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../core/BCOVPlayerTeardown.h"

// Pins the teardown-completion rule: a feature's completion may finish a
// teardown only while it is still pending AND the completion belongs to the
// current teardown token. A stale completion from an earlier (backstop-forced)
// teardown must never complete a newer one that reused the pending flag.
@interface BCOVPlayerTeardownTests : XCTestCase
@end

@implementation BCOVPlayerTeardownTests

- (void)testMatchingTokenWhilePendingCompletes
{
  XCTAssertTrue(BCOVShouldCompletePlayerTearDown(
      /*completionToken*/ 4, /*currentToken*/ 4, /*teardownPending*/ YES));
}

- (void)testStaleTokenWhilePendingDoesNotComplete
{
  XCTAssertFalse(BCOVShouldCompletePlayerTearDown(
      /*completionToken*/ 3, /*currentToken*/ 4, /*teardownPending*/ YES));
}

- (void)testAlreadyCompletedDoesNotCompleteAgain
{
  XCTAssertFalse(BCOVShouldCompletePlayerTearDown(
      /*completionToken*/ 4, /*currentToken*/ 4, /*teardownPending*/ NO));
}

- (void)testZeroTokensWithoutPendingDoesNotComplete
{
  XCTAssertFalse(BCOVShouldCompletePlayerTearDown(
      /*completionToken*/ 0, /*currentToken*/ 0, /*teardownPending*/ NO));
}

@end
