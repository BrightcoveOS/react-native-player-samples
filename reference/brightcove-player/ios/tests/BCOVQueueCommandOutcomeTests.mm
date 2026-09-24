#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../playlists/BCOVQueueCommandOutcome.h"

// Ports the Android QueueCommandOutcomeTest table to the iOS decision
// functions. The table itself is the cross-platform queue-command contract:
// no-queue, at-end with repeat off, repeat-all wrap, pending during
// resolution, and the applied-next fast path.
@interface BCOVQueueCommandOutcomeTests : XCTestCase
@end

@implementation BCOVQueueCommandOutcomeTests

- (void)testAppliedNextItemAdvances
{
  XCTAssertEqual(BCOVNextQueueCommandOutcome(3, 0, NO, NO), BCOVQueueCommandOutcomeAdvanced);
  XCTAssertEqual(BCOVNextQueueCommandOutcome(3, 1, YES, NO), BCOVQueueCommandOutcomeAdvanced);
}

- (void)testAtLastItemWithRepeatOffIsAtEnd
{
  XCTAssertEqual(BCOVNextQueueCommandOutcome(3, 2, NO, NO), BCOVQueueCommandOutcomeAtEnd);
}

- (void)testRepeatAllWrapsOnlyAfterResolutionFinished
{
  XCTAssertEqual(BCOVNextQueueCommandOutcome(3, 2, NO, YES), BCOVQueueCommandOutcomeAdvanced);
  // Wrapping mid-resolution could jump to item 0 although a genuine next item
  // is about to resolve.
  XCTAssertEqual(BCOVNextQueueCommandOutcome(3, 2, YES, YES), BCOVQueueCommandOutcomePending);
}

- (void)testNothingAppliedYetStaysPending
{
  XCTAssertEqual(BCOVNextQueueCommandOutcome(0, -1, YES, NO), BCOVQueueCommandOutcomePending);
  // Every id failed to resolve: the internal retry drops the request; the
  // decision stays Pending so it never reports at-end.
  XCTAssertEqual(BCOVNextQueueCommandOutcome(0, -1, NO, NO), BCOVQueueCommandOutcomePending);
}

- (void)testAtLastItemDuringResolutionDefers
{
  XCTAssertEqual(BCOVNextQueueCommandOutcome(2, 1, YES, NO), BCOVQueueCommandOutcomePending);
}

- (void)testPreviousMovesBackWhenAnAppliedItemExists
{
  XCTAssertEqual(BCOVPreviousQueueCommandOutcome(3, 1, NO), BCOVPreviousQueueCommandOutcomePrevious);
}

- (void)testPreviousAtFirstItemWithRepeatOffRestartsCurrent
{
  XCTAssertEqual(BCOVPreviousQueueCommandOutcome(3, 0, NO), BCOVPreviousQueueCommandOutcomeRestartCurrent);
}

- (void)testPreviousAtFirstItemWithRepeatAllWrapsToLast
{
  XCTAssertEqual(BCOVPreviousQueueCommandOutcome(3, 0, YES), BCOVPreviousQueueCommandOutcomeWrapToLast);
}

- (void)testPreviousOnEmptyOrderRestartsCurrent
{
  XCTAssertEqual(BCOVPreviousQueueCommandOutcome(0, -1, NO), BCOVPreviousQueueCommandOutcomeRestartCurrent);
}

- (void)testMessagesMatchTheCrossPlatformContractVerbatim
{
  XCTAssertEqualObjects(BCOVQueueAtEndMessage(),
      @"Cannot advance the queue: the last item is already playing and the repeat mode does not wrap the queue");
  XCTAssertEqualObjects(BCOVNextQueueNotLoadedMessage(),
      @"Cannot advance the queue: no queue is loaded in this player");
  XCTAssertEqualObjects(BCOVPreviousQueueNotLoadedMessage(),
      @"Cannot go to the previous queue item: no queue is loaded in this player");
}

@end
