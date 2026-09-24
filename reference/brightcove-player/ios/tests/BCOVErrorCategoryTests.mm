#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "BCOVErrorCategory.h"

// Ports the Android PlayerErrorClassifierTest expectations to the iOS
// classifier. Android extracts a rule and unit-tests it; the iOS parallel
// used to be re-typed by hand and shipped untested (the PR #72/#75/#74
// pattern). The classifier is compiled here from the canonical ios/core
// sources — no copy — so the tests can never drift from what ships, and no
// React Native/Fabric toolchain is required: BCOVErrorCategory.mm only
// imports Foundation, AVFoundation, and BrightcovePlayerSDK.
//
// Android classifies Media3's typed ERROR_CODE_* values; iOS classifies
// NSError domains, typed AVFoundation codes, and the Playback API's typed
// error_code tokens, so each Android case maps to its iOS counterpart
// surface rather than 1:1 code values.

static NSError *CatalogAPIError(NSArray *apiErrors, NSNumber *statusCode)
{
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[BCOVPlaybackService.ErrorKeyAPIErrors] = apiErrors;
  if (statusCode != nil) {
    userInfo[BCOVPlaybackService.ErrorKeyAPIHTTPStatusCode] = statusCode;
  }
  return [NSError errorWithDomain:BCOVPlaybackService.ErrorDomain
                             code:BCOVPlaybackServiceErrorCodeAPIError
                         userInfo:userInfo];
}

@interface BCOVErrorCategoryTests : XCTestCase
@end

@implementation BCOVErrorCategoryTests

// The core of the Android review: an untyped error (no typed code at all)
// must not be classified as any terminal category — unknown, so a pending
// authoritative typed result can still replace it.
- (void)testNilErrorIsUnknown
{
  XCTAssertEqualObjects(BCOVErrorCategory(nil), @"unknown");
}

// Android's ioCodesMapToNetwork. iOS expresses every network failure
// through NSURLErrorDomain.
- (void)testURLErrorDomainIsNetwork
{
  NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                       code:NSURLErrorNotConnectedToInternet
                                   userInfo:nil];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"network");
}

// Android's drmPlaybackCodesMapToDrm. iOS's DRM failure surface is
// AVFoundation's typed not-authorized codes.
- (void)testAVNotAuthorizedCodesAreDrm
{
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorContentIsNotAuthorized
                                        userInfo:nil]),
      @"drm");
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorApplicationIsNotAuthorized
                                        userInfo:nil]),
      @"drm");
}

// FairPlay / content-key session failures. The SDK reports these through
// three typed domains, none of whose string values contain "FairPlay" or
// "ContentKey" — they must be matched by the SDK's own constants.
// AVContentKeySessionErrorDomain has no public NSString constant and stays
// matched by its literal value.
- (void)testFairPlayDomainsAreDrm
{
  NSArray<NSString *> *domains = @[
    BCOVFPSConstants.ErrorDomain,
    BCOVFPSBrightcoveAuthProxy.ErrorDomain,
    BCOVFairPlayManager.ErrorDomain,
    @"AVContentKeySessionErrorDomain",
  ];
  for (NSString *domain in domains) {
    NSError *error = [NSError errorWithDomain:domain code:0 userInfo:nil];
    XCTAssertEqualObjects(BCOVErrorCategory(error), @"drm",
                          @"domain %@ must classify as drm", domain);
  }
}

// An expired or invalid offline download license is a DRM failure.
- (void)testOfflineLicenseCodesAreDrm
{
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:BCOVOfflineVideoManager.ErrorDomain
                                            code:BCOVOfflineVideoManagerErrorCodeExpiredLicense
                                        userInfo:nil]),
      @"drm");
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:BCOVOfflineVideoManager.ErrorDomain
                                            code:BCOVOfflineVideoManagerErrorCodeInvalidLicense
                                        userInfo:nil]),
      @"drm");
}

// Android's parsingAndDecoderCodesMapToNotPlayable.
- (void)testAVParsingAndDecodeCodesAreNotPlayable
{
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorFailedToParse
                                        userInfo:nil]),
      @"not_playable");
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorContentIsUnavailable
                                        userInfo:nil]),
      @"not_playable");
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorDecodeFailed
                                        userInfo:nil]),
      @"not_playable");
}

// Android's unmappedTypedCodeIsPlayback: a typed code that is real but not
// a content defect (the media stack resetting, an item no longer playable)
// is a playback failure, not unknown and not not_playable.
- (void)testAVMediaServicesCodesArePlayback
{
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorNoLongerPlayable
                                        userInfo:nil]),
      @"playback");
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorMediaServicesWereReset
                                        userInfo:nil]),
      @"playback");
}

// An AVFoundation code the switch does not positively recognize must not
// be guessed into a category.
- (void)testUnmappedAVCodeIsUnknown
{
  XCTAssertEqualObjects(
      BCOVErrorCategory([NSError errorWithDomain:AVFoundationErrorDomain
                                            code:AVErrorUnknown
                                        userInfo:nil]),
      @"unknown");
}

// An unrecognized domain with no underlying error is unknown.
- (void)testUnrecognizedDomainWithoutUnderlyingErrorIsUnknown
{
  NSError *error = [NSError errorWithDomain:@"com.example.Unrecognized" code:7 userInfo:nil];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"unknown");
}

// Many BCOV errors wrap the real cause in NSUnderlyingErrorKey; the
// wrapped failure must be categorized precisely, not reported unknown.
- (void)testUnderlyingErrorIsRecursedForWrappedNetworkError
{
  NSError *wrapped = [NSError errorWithDomain:@"com.example.Wrapping" code:9 userInfo:@{
    NSUnderlyingErrorKey : [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorTimedOut
                                           userInfo:nil],
  }];
  XCTAssertEqualObjects(BCOVErrorCategory(wrapped), @"network");
}

// Android's catalogTokensMapToTheirCategories. The Playback API
// (BCOVPlaybackService) is iOS's catalog resolver; its typed codes are
// ConnectionError and the per-error error_code tokens.
- (void)testCatalogConnectionErrorIsNetwork
{
  NSError *error = [NSError errorWithDomain:BCOVPlaybackService.ErrorDomain
                                       code:BCOVPlaybackServiceErrorCodeConnectionError
                                   userInfo:nil];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"network");
}

- (void)testCatalogVideoNotPlayableTokenIsNotPlayable
{
  XCTAssertEqualObjects(
      BCOVErrorCategory(CatalogAPIError(@[ @{ @"error_code" : @"VIDEO_NOT_PLAYABLE" } ], nil)),
      @"not_playable");
}

- (void)testCatalogTypedNotFoundWith404IsNotFound
{
  XCTAssertEqualObjects(
      BCOVErrorCategory(CatalogAPIError(
          @[ @{ @"error_code" : @"NOT_FOUND", @"error_subcode" : @"RESOURCE_NOT_FOUND" } ],
          @404)),
      @"not_found");
}

// HTTP 404 alone does not identify which Playback API resource is missing:
// an account/route/auth 404 is not a missing video, so without the API's
// typed NOT_FOUND token it must stay unknown.
- (void)testCatalog404WithoutTypedNotFoundTokenIsUnknown
{
  XCTAssertEqualObjects(
      BCOVErrorCategory(CatalogAPIError(@[ @{ @"error_code" : @"ACCESS_DENIED" } ], @404)),
      @"unknown");
}

// Android's accessFailureIsUnknownNotNotFound: an access failure (bad or
// expired policy key, geo-restriction) is real but is NOT a missing video.
- (void)testCatalogAccessFailureIsUnknownNotNotFound
{
  XCTAssertEqualObjects(
      BCOVErrorCategory(CatalogAPIError(@[ @{ @"error_code" : @"ACCESS_DENIED" } ], @403)),
      @"unknown");
  XCTAssertEqualObjects(
      BCOVErrorCategory(CatalogAPIError(@[ @{ @"error_code" : @"FORBIDDEN" } ], @403)),
      @"unknown");
}

// A malformed response is not positively any category.
- (void)testCatalogJSONDeserializationErrorIsUnknown
{
  NSError *error = [NSError errorWithDomain:BCOVPlaybackService.ErrorDomain
                                       code:BCOVPlaybackServiceErrorCodeJSONDeserializationError
                                   userInfo:nil];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"unknown");
}

// The token list is scanned in full: a later matching entry still
// classifies the error even when an earlier entry did not match.
- (void)testCatalogTokenIsMatchedInAnyAPIErrorEntry
{
  NSArray *apiErrors = @[
    @{ @"error_code" : @"ACCESS_DENIED" },
    @{ @"error_code" : @"VIDEO_NOT_PLAYABLE" },
  ];
  XCTAssertEqualObjects(BCOVErrorCategory(CatalogAPIError(apiErrors, @403)), @"not_playable");
}

// Brightcove playback-session failures carry typed session error codes.
- (void)testSessionNoPlayableSourceIsNotPlayable
{
  NSError *error = [NSError errorWithDomain:(NSString *)kBCOVPlaybackSessionErrorDomain
                                       code:kBCOVPlaybackSessionErrorCodeNoPlayableSource
                                   userInfo:nil];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"not_playable");
}

- (void)testSessionWifiUnavailableIsNetwork
{
  NSError *error = [NSError errorWithDomain:(NSString *)kBCOVPlaybackSessionErrorDomain
                                       code:kBCOVPlaybackSessionErrorCodeWifiUnavailable
                                   userInfo:nil];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"network");
}

// LoadFailed is ambiguous on its own; the underlying error names the real
// cause, so a wrapped network failure is categorized as network.
- (void)testSessionLoadFailedRecursesIntoUnderlyingError
{
  NSError *error = [NSError errorWithDomain:(NSString *)kBCOVPlaybackSessionErrorDomain
                                       code:kBCOVPlaybackSessionErrorCodeLoadFailed
                                   userInfo:@{
    NSUnderlyingErrorKey :
        [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil],
  }];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"network");
}

// An offline-manager error that is not one of the license-expiry codes
// recurses into its underlying error.
- (void)testOfflineManagerNonLicenseCodeRecursesIntoUnderlyingError
{
  NSError *error = [NSError errorWithDomain:BCOVOfflineVideoManager.ErrorDomain
                                       code:69300
                                   userInfo:@{
    NSUnderlyingErrorKey :
        [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil],
  }];
  XCTAssertEqualObjects(BCOVErrorCategory(error), @"network");
}

@end

// Android's aggregateQueueErrorCategory suite: a queue where every item
// failed to resolve must report the shared category honestly or unknown —
// never an arbitrary one of several.
@interface BCOVAggregateQueueErrorCategoryTests : XCTestCase
@end

@implementation BCOVAggregateQueueErrorCategoryTests

- (void)testReportsSharedCategoryWhenAllItemsMatch
{
  XCTAssertEqualObjects(
      BCOVAggregateQueueErrorCategory(@[ @"not_found", @"not_found" ]), @"not_found");
  XCTAssertEqualObjects(BCOVAggregateQueueErrorCategory(@[ @"network" ]), @"network");
}

// A mixed batch of failure categories has no single honest cause; picking
// one (e.g. the first) would claim more than the data supports.
- (void)testMixedCategoriesReportUnknown
{
  XCTAssertEqualObjects(
      BCOVAggregateQueueErrorCategory(@[ @"not_found", @"network" ]), @"unknown");
}

- (void)testEmptyQueueReportsUnknown
{
  XCTAssertEqualObjects(BCOVAggregateQueueErrorCategory(@[]), @"unknown");
}

@end

// The diagnostic nativeCode (domain:code) that ships alongside the
// normalized category, so a customer can log the real error identity while
// branching on the stable category.
@interface BCOVNativeErrorCodeTests : XCTestCase
@end

@implementation BCOVNativeErrorCodeTests

- (void)testUsesDomainAndCodeForGenericErrors
{
  NSError *error = [NSError errorWithDomain:@"com.example.Custom" code:42 userInfo:nil];
  XCTAssertEqualObjects(BCOVNativeErrorCode(error), @"com.example.Custom:42");
}

// For a Playback API error, the API's own typed error_code (and subcode)
// is more useful than the generic APIError code every API error shares.
- (void)testUsesTypedTokenAndSubcodeForAPIError
{
  NSError *error = CatalogAPIError(
      @[ @{ @"error_code" : @"NOT_FOUND", @"error_subcode" : @"RESOURCE_NOT_FOUND" } ], @404);
  XCTAssertEqualObjects(BCOVNativeErrorCode(error), @"NOT_FOUND:RESOURCE_NOT_FOUND");
}

- (void)testOmitsSubcodeWhenAbsent
{
  NSError *error = CatalogAPIError(@[ @{ @"error_code" : @"VIDEO_NOT_PLAYABLE" } ], nil);
  XCTAssertEqualObjects(BCOVNativeErrorCode(error), @"VIDEO_NOT_PLAYABLE");
}

- (void)testFallsBackWhenAPIErrorsAreMissingOrMalformed
{
  NSString *fallback = [NSString stringWithFormat:@"%@:%ld", BCOVPlaybackService.ErrorDomain,
                                                  (long)BCOVPlaybackServiceErrorCodeAPIError];
  // No token at all.
  XCTAssertEqualObjects(BCOVNativeErrorCode(CatalogAPIError(@[], @500)), fallback);
  // Token without an error_code value.
  XCTAssertEqualObjects(BCOVNativeErrorCode(CatalogAPIError(@[ @{} ], @500)), fallback);
  // Payload is not a dictionary.
  XCTAssertEqualObjects(BCOVNativeErrorCode(CatalogAPIError(@[ @"garbage" ], @500)), fallback);
  // Non-API Playback Service errors keep the plain domain:code form.
  NSError *connection = [NSError errorWithDomain:BCOVPlaybackService.ErrorDomain
                                            code:BCOVPlaybackServiceErrorCodeConnectionError
                                        userInfo:nil];
  NSString *connectionFallback = [NSString
      stringWithFormat:@"%@:%ld", BCOVPlaybackService.ErrorDomain,
                       (long)BCOVPlaybackServiceErrorCodeConnectionError];
  XCTAssertEqualObjects(BCOVNativeErrorCode(connection), connectionFallback);
}

@end
