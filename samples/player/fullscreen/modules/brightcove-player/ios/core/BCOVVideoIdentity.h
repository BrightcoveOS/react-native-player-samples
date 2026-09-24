#import <Foundation/Foundation.h>

// Import the SDK's Swift-interop header first: it declares BCOVVideo (and
// the rest of the SDK's Swift classes) as plain Objective-C interfaces.
// BrightcovePlayerSDK.h alone only forward-declares them, leaving the
// `properties` access below unresolvable.
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * BCOVVideo.properties key every in-repo loader stamps with the request
 * generation the video was resolved under (the core's catalog path, the
 * playlists queue, preloading, source-loading modes, offline). Same string as
 * BCOVBridgeRequestGenerationKey in BrightcovePlayerFeature.h — redeclared
 * here so the identity rule stays compilable in the Foundation-only core
 * test target, which cannot import React event-emitter headers.
 */
FOUNDATION_EXPORT NSString *const BCOVVideoRequestGenerationKey;

/**
 * The single video-identity rule the core's session/video guards use.
 *
 * A BCOVVideo carrying the BCOVVideoRequestGenerationKey property naming the
 * active request generation is current, regardless of its id: every loader
 * this repository ships stamps the tag, and a feature-inserted item (the
 * preloaded next-up video) legitimately has a different id than the videoId
 * prop. A tagged video naming any other generation is rejected. The rule is
 * fail-closed: an untagged video names nothing this view loaded (every
 * in-repo loader tags) and is rejected, so a future untagged loader fails
 * loudly rather than silently gaining event forwarding.
 *
 * Extracted as a pure function (no ivar access) so the identity rule is
 * unit-testable in the Foundation-only core test target.
 */
BOOL BCOVVideoIsCurrentRequest(BCOVVideo *_Nullable video, NSUInteger requestGeneration);

NS_ASSUME_NONNULL_END
