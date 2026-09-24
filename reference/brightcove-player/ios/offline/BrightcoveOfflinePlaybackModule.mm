#import "BrightcoveOfflinePlaybackModule.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <React/RCTUtils.h>

#import "BrightcoveOfflinePlaybackStore.h"

#ifdef RCT_NEW_ARCH_ENABLED
using namespace facebook::react;
#endif

static BOOL BCOVOfflineStringContainsOnlyDigits(NSString *value)
{
  if (value.length == 0) {
    return NO;
  }
  NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
  return [value rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

@interface BrightcoveOfflinePlaybackModule () <BrightcoveOfflinePlaybackStoreObserver>
@end

@implementation BrightcoveOfflinePlaybackModule {
  NSMutableSet<BCOVPlaybackService *> *_pendingPlaybackServices;
  // videoId per pending removal, recorded before the delete starts: the
  // store's removed-token notification carries only the token, but the
  // removed-event contract must report the catalog videoId (the same payload
  // shape Android emits for a deleted download).
  NSMutableDictionary<NSString *, NSString *> *_pendingRemovalVideoIds;
}

RCT_EXPORT_MODULE(BrightcoveOfflinePlayback)

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (instancetype)init
{
  if (self = [super init]) {
    _pendingPlaybackServices = [NSMutableSet set];
    _pendingRemovalVideoIds = [NSMutableDictionary dictionary];
    [[BrightcoveOfflinePlaybackStore sharedStore] addObserver:self];
  }
  return self;
}

- (void)invalidate
{
  [[BrightcoveOfflinePlaybackStore sharedStore] removeObserver:self];
  [_pendingPlaybackServices removeAllObjects];
  [_pendingRemovalVideoIds removeAllObjects];
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<TurboModule>)getTurboModule:(const ObjCTurboModule::InitParams &)params
{
  return std::make_shared<NativeBrightcoveOfflinePlaybackSpecJSI>(params);
}
#endif

RCT_EXPORT_METHOD(requestDownload:(NSString *)accountId
                  policyKey:(NSString *)policyKey
                  videoId:(NSString *)videoId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  if (accountId.length == 0 || policyKey.length == 0 || videoId.length == 0 ||
      !BCOVOfflineStringContainsOnlyDigits(accountId) ||
      !BCOVOfflineStringContainsOnlyDigits(videoId)) {
    reject(@"invalid_configuration", @"accountId and videoId must contain only digits, and policyKey must be non-empty", nil);
    return;
  }

  BCOVPlaybackService *service = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
  [_pendingPlaybackServices addObject:service];
  __weak __typeof(self) weakSelf = self;
  [service findVideoWithConfiguration:@{
    [BCOVPlaybackService ConfigurationKeyAssetID]: videoId
  }
                        queryParameters:nil
                             completion:^(BCOVVideo *video, id jsonResponse, NSError *error) {
    void (^complete)(void) = ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf == nil) {
        return;
      }
      [strongSelf->_pendingPlaybackServices removeObject:service];
      if (error != nil) {
        reject([strongSelf codeForError:error], error.localizedDescription ?: @"Unable to retrieve the video for offline download", error);
        return;
      }
      if (video == nil) {
        reject(@"not_found", @"Brightcove returned neither a video nor an error", nil);
        return;
      }
      if (!video.canBeDownloaded) {
        reject(@"not_playable", @"This video is not eligible for iOS offline HLS download", nil);
        return;
      }

      BCOVOfflineVideoManager *manager = [BrightcoveOfflinePlaybackStore sharedStore].manager;
      [manager requestVideoDownload:video
                     mediaSelections:nil
                          parameters:nil
                          completion:^(BCOVOfflineVideoToken token, NSError *downloadError) {
        if (downloadError != nil || token == nil) {
          reject([strongSelf codeForError:downloadError], downloadError.localizedDescription ?: @"Unable to queue the offline download", downloadError);
          return;
        }
        resolve([strongSelf downloadMapForToken:token overrideState:nil]);
      }];
    };
    if (NSThread.isMainThread) {
      complete();
    } else {
      dispatch_async(dispatch_get_main_queue(), complete);
    }
  }];
}

RCT_EXPORT_METHOD(listDownloads:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  BCOVOfflineVideoManager *manager = [BrightcoveOfflinePlaybackStore sharedStore].manager;
  NSMutableArray<NSDictionary *> *downloads = [NSMutableArray array];
  for (BCOVOfflineVideoStatus *status in manager.offlineVideoStatus) {
    if (status.offlineVideoToken != nil) {
      [downloads addObject:[self downloadMapForToken:status.offlineVideoToken overrideState:nil]];
    }
  }
  resolve(downloads);
}

RCT_EXPORT_METHOD(pauseDownload:(NSString *)localId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  BCOVOfflineVideoManager *manager = [BrightcoveOfflinePlaybackStore sharedStore].manager;
  if ([manager offlineVideoStatusForToken:localId] == nil) {
    reject(@"not_found", @"No persisted download exists for this localId", nil);
    return;
  }
  [manager pauseVideoDownload:localId];
  resolve(nil);
  [self emitChangedForToken:localId];
}

RCT_EXPORT_METHOD(resumeDownload:(NSString *)localId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  BCOVOfflineVideoManager *manager = [BrightcoveOfflinePlaybackStore sharedStore].manager;
  if ([manager offlineVideoStatusForToken:localId] == nil) {
    reject(@"not_found", @"No persisted download exists for this localId", nil);
    return;
  }
  [manager resumeVideoDownload:localId];
  resolve(nil);
  [self emitChangedForToken:localId];
}

RCT_EXPORT_METHOD(cancelDownload:(NSString *)localId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  BCOVOfflineVideoManager *manager = [BrightcoveOfflinePlaybackStore sharedStore].manager;
  if ([manager offlineVideoStatusForToken:localId] == nil) {
    reject(@"not_found", @"No persisted download exists for this localId", nil);
    return;
  }
  [manager cancelVideoDownload:localId];
  resolve(nil);
  [self emitChangedForToken:localId];
}

RCT_EXPORT_METHOD(removeDownload:(NSString *)localId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  BrightcoveOfflinePlaybackStore *store = [BrightcoveOfflinePlaybackStore sharedStore];
  if (![store beginRemovalForToken:localId]) {
    reject(@"active_offline_source", @"Switch the player to another source before removing its active offline download", nil);
    return;
  }
  BCOVOfflineVideoManager *manager = store.manager;
  BCOVOfflineVideoStatus *status = [manager offlineVideoStatusForToken:localId];
  if (status == nil) {
    [store finishRemovalForToken:localId];
    reject(@"not_found", @"No persisted download exists for this localId", nil);
    return;
  }
  BCOVVideo *video = [manager videoObjectFromOfflineVideoToken:localId];
  NSString *videoId = video.properties[[BCOVVideo PropertyKeyId]] ?: @"";
  // Record the videoId for the store's removed-token notification, which
  // carries only the token: the removed-event payload must report the catalog
  // videoId (Android's removed events report it too).
  _pendingRemovalVideoIds[localId] = videoId;
  [manager deleteOfflineVideo:localId];
  [self waitForRemovalOfToken:localId
                       videoId:videoId
                         store:store
                       attempt:0
                       resolve:resolve
                       reject:reject];
}

- (void)offlinePlaybackStoreDidChangeToken:(BCOVOfflineVideoToken)token
{
  [self emitChangedForToken:token];
}

- (void)offlinePlaybackStoreDidRemoveToken:(BCOVOfflineVideoToken)token
{
  // A pending removal knows the catalog videoId it recorded before deleting;
  // a removal observed without one (e.g. deleted outside this module) has no
  // videoId to resolve and reports the empty string.
  NSString *videoId = _pendingRemovalVideoIds[token];
  if (videoId == nil) {
    videoId = @"";
  } else {
    [_pendingRemovalVideoIds removeObjectForKey:token];
  }
  [self emitRemovedLocalId:token videoId:videoId];
}

- (void)emitChangedForToken:(BCOVOfflineVideoToken)token
{
  NSDictionary *download = [self downloadMapForToken:token overrideState:nil];
#ifdef RCT_NEW_ARCH_ENABLED
  [self emitOnOfflineDownloadChanged:download];
#endif
}

- (void)emitRemovedLocalId:(NSString *)localId videoId:(NSString *)videoId
{
  NSDictionary *download = @{
    @"localId": localId,
    @"videoId": videoId,
    @"state": @"removed",
    @"progress": @-1,
    @"bytesDownloaded": @0,
    @"totalBytes": @-1,
    @"licenseExpiresAt": @"",
    @"code": @"",
    @"message": @"",
    @"nativeCode": @"",
  };
#ifdef RCT_NEW_ARCH_ENABLED
  [self emitOnOfflineDownloadChanged:download];
#endif
}

- (void)waitForRemovalOfToken:(BCOVOfflineVideoToken)token
                       videoId:(NSString *)videoId
                         store:(BrightcoveOfflinePlaybackStore *)store
                       attempt:(NSUInteger)attempt
                       resolve:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject
{
  if ([store.manager offlineVideoStatusForToken:token] == nil) {
    if ([store confirmRemovalForToken:token]) {
      [self emitRemovedLocalId:token videoId:videoId];
    }
    resolve(nil);
    return;
  }
  if (attempt == 50) {
    // The deletion did not finish in time. Abandon the removal entirely so
    // the store's later storage-change notification cannot re-discover the
    // token as newly removed and emit a success after this rejection — a
    // terminal outcome must be exactly one of the two.
    [store abandonRemovalForToken:token];
    [_pendingRemovalVideoIds removeObjectForKey:token];
    reject(@"unknown", @"The offline download did not finish deleting", nil);
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)),
                 dispatch_get_main_queue(), ^{
    [self waitForRemovalOfToken:token
                         videoId:videoId
                           store:store
                         attempt:attempt + 1
                         resolve:resolve
                         reject:reject];
  });
}

- (NSDictionary *)downloadMapForToken:(BCOVOfflineVideoToken)token
                         overrideState:(nullable NSString *)overrideState
{
  BCOVOfflineVideoManager *manager = [BrightcoveOfflinePlaybackStore sharedStore].manager;
  BCOVOfflineVideoStatus *status = [manager offlineVideoStatusForToken:token];
  BCOVVideo *video = [manager videoObjectFromOfflineVideoToken:token];
  NSError *error = status.error;
  NSString *videoId = video.properties[[BCOVVideo PropertyKeyId]] ?: @"";
  NSDate *licenseExpiry = [manager fairPlayLicenseExpiration:token];
  NSString *licenseExpiresAt = licenseExpiry == nil ? @"" : [self iso8601:licenseExpiry];
  NSString *state = overrideState ?: [self stateForStatus:status];
  BOOL failed = [state isEqualToString:@"failed"];

  return @{
    @"localId": token,
    @"videoId": videoId,
    @"state": state,
    @"progress": status == nil ? @-1 : @(status.downloadPercent),
    @"bytesDownloaded": @0,
    @"totalBytes": @-1,
    @"licenseExpiresAt": licenseExpiresAt,
    @"code": failed ? [self codeForError:error] : @"",
    @"message": failed ? (error.localizedDescription ?: @"The offline download failed") : @"",
    @"nativeCode": failed ? [self nativeCodeForError:error] : @"",
  };
}

- (NSString *)stateForStatus:(nullable BCOVOfflineVideoStatus *)status
{
  switch (status.downloadState) {
    case BCOVOfflineVideoDownloadStateRequested:
    case BCOVOfflineVideoDownloadStateLicensePreloaded:
      return @"queued";
    case BCOVOfflineVideoDownloadStateDownloading:
      return @"downloading";
    case BCOVOfflineVideoDownloadStateSuspended:
      return @"paused";
    case BCOVOfflineVideoDownloadStateCancelled:
      return @"cancelled";
    case BCOVOfflineVideoDownloadStateCompleted:
      return @"completed";
    case BCOVOfflineVideoDownloadStateError:
      return @"failed";
  }
}

- (NSString *)codeForError:(nullable NSError *)error
{
  if (error == nil) {
    return @"unknown";
  }
  if ([error.domain isEqualToString:NSURLErrorDomain]) {
    return @"network";
  }
  if ([error.domain isEqualToString:BCOVOfflineVideoManager.ErrorDomain]) {
    if (error.code == BCOVOfflineVideoManagerErrorCodeExpiredLicense ||
        error.code == BCOVOfflineVideoManagerErrorCodeInvalidLicense) {
      return @"drm";
    }
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    return [underlying isKindOfClass:NSError.class] ? [self codeForError:underlying] : @"unknown";
  }
  if ([error.domain isEqualToString:BCOVPlaybackService.ErrorDomain]) {
    if (error.code == BCOVPlaybackServiceErrorCodeConnectionError) {
      return @"network";
    }
    if (error.code == BCOVPlaybackServiceErrorCodeAPIError) {
      id status = error.userInfo[BCOVPlaybackService.ErrorKeyAPIHTTPStatusCode];
      if ([status respondsToSelector:@selector(integerValue)] && [status integerValue] == 404) {
        return @"not_found";
      }
    }
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    return [underlying isKindOfClass:NSError.class] ? [self codeForError:underlying] : @"unknown";
  }
  NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
  if ([underlying isKindOfClass:NSError.class]) {
    return [self codeForError:underlying];
  }
  return @"unknown";
}

- (NSString *)nativeCodeForError:(nullable NSError *)error
{
  return error == nil ? @"offline_error" : [NSString stringWithFormat:@"%@:%ld", error.domain, (long)error.code];
}

- (NSString *)iso8601:(NSDate *)date
{
  static NSISO8601DateFormatter *formatter;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
  });
  return [formatter stringFromDate:date];
}

@end
