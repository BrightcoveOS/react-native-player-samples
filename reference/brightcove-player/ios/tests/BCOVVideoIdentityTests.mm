#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../core/BCOVVideoIdentity.h"

// Pins the shared video-identity rule the core's session/video guards use
// (determinedVideoType, didPassCuePoints, noPlayableVideosFound): a
// current-generation tag is authoritative — including a feature-inserted
// preloaded item whose id differs from the videoId prop — while a stale tag
// and an untagged video are rejected (fail-closed).
@interface BCOVVideoIdentityTests : XCTestCase
@end

@implementation BCOVVideoIdentityTests

- (BCOVVideo *)videoWithId:(NSString *)videoId generation:(id)generation
{
  NSMutableDictionary *properties = [NSMutableDictionary dictionary];
  if (videoId != nil) {
    properties[[BCOVVideo PropertyKeyId]] = videoId;
  }
  if (generation != nil) {
    properties[BCOVVideoRequestGenerationKey] = generation;
  }
  return [[BCOVVideo alloc] initWithSources:nil cuePoints:nil properties:properties];
}

- (void)testCurrentGenerationTagIsAcceptedRegardlessOfVideoId
{
  // The preloaded next-up item: different id than the source prop, tagged
  // with the active request's generation at insert time.
  BCOVVideo *preloaded = [self videoWithId:@"next-video" generation:@(7)];
  XCTAssertTrue(BCOVVideoIsCurrentRequest(preloaded, 7));
}

- (void)testStaleGenerationTagIsRejectedEvenWhenIdsMatch
{
  BCOVVideo *stale = [self videoWithId:@"current-video" generation:@(6)];
  XCTAssertFalse(BCOVVideoIsCurrentRequest(stale, 7));
}

- (void)testUntaggedVideoIsRejectedFailClosed
{
  // Even an id match must not forward events for an untagged video: every
  // in-repo loader tags, so untagged names nothing this view loaded. This is
  // the fail-closed guarantee — a future untagged loader cannot silently
  // gain event forwarding by reusing an id.
  BCOVVideo *sameId = [self videoWithId:@"current-video" generation:nil];
  XCTAssertFalse(BCOVVideoIsCurrentRequest(sameId, 7));
}

- (void)testNilVideoIsRejected
{
  XCTAssertFalse(BCOVVideoIsCurrentRequest(nil, 7));
}

- (void)testNonNumberTagValueIsRejected
{
  // A malformed tag (not an NSNumber) must not crash or pass.
  BCOVVideo *malformed = [[BCOVVideo alloc] initWithSources:nil cuePoints:nil properties:@{
    BCOVVideoRequestGenerationKey : @"seven",
  }];
  XCTAssertFalse(BCOVVideoIsCurrentRequest(malformed, 7));
}

- (void)testGenerationZeroIsAValidTag
{
  // The counter starts at 0 in a fresh view; a zero generation is a real
  // value, not a sentinel.
  BCOVVideo *first = [self videoWithId:@"video-1" generation:@(0)];
  XCTAssertTrue(BCOVVideoIsCurrentRequest(first, 0));
}

@end
