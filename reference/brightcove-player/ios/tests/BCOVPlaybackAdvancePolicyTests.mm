#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../core/BCOVPlaybackAdvancePolicy.h"

// Pins the loop/autoAdvance rule: loop is single-video repeat, so the SDK must
// not auto-advance while it is on, or the SDK's advance races the core's own
// restart of the finished item.
@interface BCOVPlaybackAdvancePolicyTests : XCTestCase
@end

@implementation BCOVPlaybackAdvancePolicyTests

- (void)testAutoAdvanceIsEnabledWhenLoopIsOff
{
  XCTAssertTrue(BCOVShouldAutoAdvance(NO));
}

- (void)testAutoAdvanceIsDisabledWhenLoopIsOn
{
  XCTAssertFalse(BCOVShouldAutoAdvance(YES));
}

@end
