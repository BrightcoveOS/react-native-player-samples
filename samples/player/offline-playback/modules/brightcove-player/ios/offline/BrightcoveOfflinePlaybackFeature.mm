#import "BrightcoveOfflinePlaybackFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

#import "BrightcoveOfflinePlaybackStore.h"

@implementation BrightcoveOfflinePlaybackFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  NSString *_offlineSourceId;
  NSString *_activeSourceId;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"offlineSourceId"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _offlineSourceId = @"";
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"offlineSourceId"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"Unexpected offline prop '%@'", name];
  }
  NSString *newValue = [value isKindOfClass:NSString.class] ? value : @"";
  if (![_offlineSourceId isEqualToString:newValue]) {
    _offlineSourceId = [newValue copy];
    // The provider chain is fixed when the controller is created. Reloading
    // tears down that controller so the next update composes the chain for the
    // new online/offline mode before its source is loaded.
    [_host requestSourceReload];
  }
}

- (BOOL)claimsSourceLoading
{
  return _offlineSourceId.length > 0;
}

- (BOOL)providesFairPlaySessionProvider
{
  return _offlineSourceId.length > 0;
}

- (void)onSourceReset
{
  if (_activeSourceId != nil) {
    [[BrightcoveOfflinePlaybackStore sharedStore] deactivateToken:_activeSourceId];
    _activeSourceId = nil;
  }
}

- (void)onInvalidate
{
  [self onSourceReset];
}

// Only add the offline FairPlay provider when this view is actually loading an
// offline source. Online DRM is handled by BrightcoveDrmFeature; adding both
// FairPlay providers to one controller causes AVContentKeySession to receive a
// duplicate content-key recipient and the SDK aborts during source loading.
// Local offline HLS content can still be FairPlay-encrypted, so the provider must
// still be part of the controller's chain at creation time for offline sources.
- (id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (id<BCOVPlaybackSessionProvider>)upstream
{
  if (_offlineSourceId.length == 0) {
    return upstream;
  }

  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  BCOVBasicSessionProviderOptions *options = [BCOVBasicSessionProviderOptions new];
  options.sourceSelectionPolicy = [BCOVBasicSourceSelectionPolicy sourceSelectionHLSWithScheme:@"https"];
  id<BCOVPlaybackSessionProvider> basic = [sdkManager createBasicSessionProviderWithOptions:options];
  return [sdkManager createFairPlaySessionProviderWithApplicationCertificate:nil
                                                            authorizationProxy:[BrightcoveOfflinePlaybackStore sharedStore].authProxy
                                                          upstreamSessionProvider:upstream ?: basic];
}

- (void)loadSource:(NSUInteger)requestGeneration
          accountId:(NSString *)accountId
          policyKey:(NSString *)policyKey
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || ![host isCurrentRequest:requestGeneration]) {
    return;
  }
  BCOVOfflineVideoManager *manager = [BrightcoveOfflinePlaybackStore sharedStore].manager;
  BCOVVideo *video = [manager videoObjectFromOfflineVideoToken:_offlineSourceId];
  if (video == nil) {
    [host emitSourceLoadError:requestGeneration
                         code:@"not_found"
                   nativeCode:@"offline_source_not_found"
                      message:[NSString stringWithFormat:@"No persisted download exists for offlineSourceId '%@'", _offlineSourceId]];
    return;
  }
  BCOVOfflineVideoStatus *status = [manager offlineVideoStatusForToken:_offlineSourceId];
  if (status == nil) {
    [host emitSourceLoadError:requestGeneration
                         code:@"not_found"
                   nativeCode:@"offline_source_status_not_found"
                      message:[NSString stringWithFormat:@"No persisted download status exists for offlineSourceId '%@'", _offlineSourceId]];
    return;
  }
  if (status.downloadState != BCOVOfflineVideoDownloadStateCompleted) {
    [host emitSourceLoadError:requestGeneration
                         code:@"not_playable"
                   nativeCode:@"offline_source_not_complete"
                      message:@"The persisted download is not complete"];
    return;
  }

#if TARGET_OS_SIMULATOR
  if (video.usesFairPlay) {
    [host emitSourceLoadError:requestGeneration
                         code:@"not_playable"
                   nativeCode:@"fairplay_requires_device"
                      message:@"FairPlay offline playback cannot run in the iOS Simulator"];
    return;
  }
#endif

  BCOVVideo *taggedVideo = [host taggedVideo:video forGeneration:requestGeneration];
  if (![[BrightcoveOfflinePlaybackStore sharedStore] acquireToken:_offlineSourceId]) {
    [host emitSourceLoadError:requestGeneration
                         code:@"not_playable"
                   nativeCode:@"offline_source_removing"
                      message:@"The persisted download is being removed"];
    return;
  }
  NSString *readyVideoId = video.properties[[BCOVVideo PropertyKeyId]] ?: _offlineSourceId;
  [host markVideoLoaded:requestGeneration readyVideoId:readyVideoId];
  [host.playbackController setVideos:@[ taggedVideo ]];
  _activeSourceId = [_offlineSourceId copy];
}

@end
