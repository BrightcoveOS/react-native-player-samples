#import "BCOVErrorCategory.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

// Maps a native NSError to the normalized cross-platform error category
// documented in the TS contract, so error.code is a value a customer can
// branch on identically on iOS and Android. The raw domain:code is preserved
// separately in nativeCode.
//
// Anything not positively recognized is reported as `unknown`, never guessed:
// the iOS parallel of Android's typed-code mapping. In particular an access
// failure (a 401/403 from an expired/invalid policy key or a geo-restriction)
// and a 5xx server error are NOT a missing video, so they must never be
// reported as not_found — the whole value of `code` is that it does not lie.
static BOOL BCOVPlaybackServiceErrorHasAPIErrorCode(
    NSError *error,
    NSString *expectedCode,
    NSString * _Nullable expectedSubcode)
{
  id apiErrors = error.userInfo[BCOVPlaybackService.ErrorKeyAPIErrors];
  if (![apiErrors isKindOfClass:NSArray.class]) {
    return NO;
  }

  for (id apiError in (NSArray *)apiErrors) {
    if (![apiError isKindOfClass:NSDictionary.class]) {
      continue;
    }

    NSDictionary *errorDictionary = (NSDictionary *)apiError;
    NSString *errorCode = errorDictionary[@"error_code"];
    NSString *errorSubcode = errorDictionary[@"error_subcode"];
    if ([errorCode isEqualToString:expectedCode] &&
        (expectedSubcode == nil || [errorSubcode isEqualToString:expectedSubcode])) {
      return YES;
    }
  }

  return NO;
}

NSString *BCOVErrorCategory(NSError *error)
{
  if (error == nil) {
    return @"unknown";
  }

  NSString *domain = error.domain ?: @"";

  if ([domain isEqualToString:NSURLErrorDomain]) {
    return @"network";
  }

  if ([domain isEqualToString:AVFoundationErrorDomain]) {
    switch (error.code) {
      case AVErrorContentIsNotAuthorized:
      case AVErrorApplicationIsNotAuthorized:
        return @"drm";
      case AVErrorNoLongerPlayable:
      case AVErrorMediaServicesWereReset:
        return @"playback";
      case AVErrorFailedToParse:
      case AVErrorContentIsUnavailable:
      case AVErrorDecodeFailed:
        return @"not_playable";
      default:
        return @"unknown";
    }
  }

  // FairPlay / content-key session failures. The Brightcove SDK reports these
  // through three typed domains (certificate fetch, license/key request, auth
  // proxy) — none of whose string values contain "FairPlay" or "ContentKey", so
  // they must be matched by the SDK's own domain constants, not a substring
  // guess. AVContentKeySessionErrorDomain (raised by AVFoundation itself for
  // content-key failures) has no public NSString constant, so it stays matched
  // by its literal value.
  if ([domain isEqualToString:BCOVFPSConstants.ErrorDomain] ||
      [domain isEqualToString:BCOVFPSBrightcoveAuthProxy.ErrorDomain] ||
      [domain isEqualToString:BCOVFairPlayManager.ErrorDomain] ||
      [domain isEqualToString:@"AVContentKeySessionErrorDomain"]) {
    return @"drm";
  }

  if ([domain isEqualToString:BCOVOfflineVideoManager.ErrorDomain]) {
    if (error.code == BCOVOfflineVideoManagerErrorCodeExpiredLicense ||
        error.code == BCOVOfflineVideoManagerErrorCodeInvalidLicense) {
      return @"drm";
    }
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class]) {
      return BCOVErrorCategory(underlying);
    }
    return @"unknown";
  }

  // Brightcove Playback API (catalog) failures carry a typed
  // BCOVPlaybackServiceErrorCode and, for API errors, the HTTP status in
  // userInfo — the iOS parallel to Android's typed catalog codes. Switch on
  // those instead of assuming every BCOV error means "video not found".
  if ([domain isEqualToString:BCOVPlaybackService.ErrorDomain]) {
    switch (error.code) {
      case BCOVPlaybackServiceErrorCodeConnectionError:
        return @"network";
      case BCOVPlaybackServiceErrorCodeAPIError: {
        if (BCOVPlaybackServiceErrorHasAPIErrorCode(error, @"VIDEO_NOT_PLAYABLE", nil)) {
          return @"not_playable";
        }

        // HTTP status alone does not identify which Playback API resource is
        // missing. Require the API's typed VIDEO_NOT_FOUND error before exposing
        // not_found; account, route, auth, and malformed-response 404s stay
        // unknown.
        id status = error.userInfo[BCOVPlaybackService.ErrorKeyAPIHTTPStatusCode];
        if ([status respondsToSelector:@selector(integerValue)] &&
            [status integerValue] == 404 &&
            BCOVPlaybackServiceErrorHasAPIErrorCode(error, @"NOT_FOUND", @"RESOURCE_NOT_FOUND")) {
          return @"not_found";
        }
        return @"unknown";
      }
      default:
        // JSONDeserializationError and anything else: a malformed or
        // unrecognized response, not positively any category.
        return @"unknown";
    }
  }

  // Brightcove playback-session failures carry typed session error codes.
  if ([domain isEqualToString:kBCOVPlaybackSessionErrorDomain]) {
    if (error.code == kBCOVPlaybackSessionErrorCodeNoPlayableSource) {
      return @"not_playable";
    }
    if (error.code == kBCOVPlaybackSessionErrorCodeWifiUnavailable) {
      return @"network";
    }
    // LoadFailed / FailedToPlayToEnd are ambiguous on their own; fall through
    // to the underlying error, which usually names the real cause.
  }

  // Many BCOV errors wrap the real cause; the SDK documents NSUnderlyingErrorKey
  // as where the actual connection/decode error lives. Recurse so a wrapped
  // network or DRM failure is categorized precisely instead of as unknown.
  NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
  if ([underlying isKindOfClass:NSError.class]) {
    return BCOVErrorCategory(underlying);
  }

  return @"unknown";
}

NSString *BCOVNativeErrorCode(NSError *error)
{
  NSString *fallback = [NSString stringWithFormat:@"%@:%ld", error.domain, (long)error.code];
  if (![error.domain isEqualToString:BCOVPlaybackService.ErrorDomain] ||
      error.code != BCOVPlaybackServiceErrorCodeAPIError) {
    return fallback;
  }

  id apiErrors = error.userInfo[BCOVPlaybackService.ErrorKeyAPIErrors];
  NSArray *apiErrorArray = [apiErrors isKindOfClass:NSArray.class] ? (NSArray *)apiErrors : nil;
  id firstAPIError = apiErrorArray.count > 0 ? apiErrorArray[0] : nil;
  NSDictionary *firstError = [firstAPIError isKindOfClass:NSDictionary.class]
      ? (NSDictionary *)firstAPIError
      : nil;
  NSString *code = firstError[@"error_code"];
  NSString *subcode = firstError[@"error_subcode"];
  if (code.length == 0) {
    return fallback;
  }
  return subcode.length > 0 ? [NSString stringWithFormat:@"%@:%@", code, subcode] : code;
}

NSString *BCOVAggregateQueueErrorCategory(NSArray<NSString *> *codes)
{
  if (codes.count == 0) {
    return @"unknown";
  }
  NSSet<NSString *> *distinct = [NSSet setWithArray:codes];
  return distinct.count == 1 ? distinct.anyObject : @"unknown";
}
