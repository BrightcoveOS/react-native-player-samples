#import "BrightcoveFreeWheelFeature.h"

#import <BrightcoveFW/BrightcoveFW.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <AdManager/FWSDK.h>

@implementation BrightcoveFreeWheelFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  NSString *_adUrl;
  NSInteger _networkId;
  NSString *_profile;
  NSString *_siteSectionId;
  NSString *_videoAssetId;
  __weak id<BCOVPlaybackSession> _currentSession;
  BOOL _acceptCallbacks;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:
      @"freeWheelAdUrl",
      @"freeWheelNetworkId",
      @"freeWheelProfile",
      @"freeWheelSiteSectionId",
      @"freeWheelVideoAssetId",
      nil];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _acceptCallbacks = NO;
}


// The core already session-checks the ad-sequence hooks it forwards; the
// remaining guard is feature-local acceptance state.
- (BOOL)canEmit
{
  return _host != nil && !_host.isInvalidated && _acceptCallbacks;
}

- (void)setProp:(NSString *)name value:(nullable id)value
{
  if ([name isEqualToString:@"freeWheelAdUrl"]) {
    _adUrl = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"freeWheelNetworkId"]) {
    _networkId = [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value integerValue] : 0;
  } else if ([name isEqualToString:@"freeWheelProfile"]) {
    _profile = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"freeWheelSiteSectionId"]) {
    _siteSectionId = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"freeWheelVideoAssetId"]) {
    _videoAssetId = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveFreeWheelFeature owns no prop '%@'", name];
  }
}

- (BOOL)requiresControllerManagedPlayback
{
  return _adUrl.length > 0 && _networkId > 0 &&
      _profile.length > 0 && _siteSectionId.length > 0;
}

- (nullable id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (nullable id<BCOVPlaybackSessionProvider>)upstream
{
  if (_adUrl.length == 0 || _networkId <= 0 ||
      _profile.length == 0 || _siteSectionId.length == 0) {
    return nil;
  }

  BCOVFWSessionProviderOptions *options = [BCOVFWSessionProviderOptions new];
  options.cuePointProgressPolicy = [BCOVCuePointProgressPolicy
      progressPolicyProcessingCuePoints:BCOVProgressPolicyProcessFinalCuePoint
                   resumingPlaybackFrom:BCOVProgressPolicyResumeFromContentPlayhead
   ignoringPreviouslyProcessedCuePoints:YES];

  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  id<FWAdManager> adManager = newAdManager();
  if (adManager == nil) {
    return nil;
  }
  [adManager setNetworkId:(NSUInteger)_networkId];

  __weak __typeof__(self) weakSelf = self;
  BCOVFWSessionProviderAdContextPolicy policy = ^BCOVFWContext *(BCOVVideo *video, BCOVSource *source, NSTimeInterval duration) {
    __strong __typeof__(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_adUrl.length == 0) {
      return nil;
    }

    id<FWContext> adContext = [adManager newContext];
    if (adContext == nil) {
      return nil;
    }
    UIView *adContainer = strongSelf->_host.playerView.contentOverlayView ?: strongSelf->_host.hostView;
    if (adContainer != nil) {
      [adContext setVideoDisplayBase:adContainer];
    }

    CGSize dimensions = strongSelf->_host.hostView.bounds.size;
    FWRequestConfiguration *config = [[FWRequestConfiguration alloc]
        initWithServerURL:strongSelf->_adUrl
            playerProfile:strongSelf->_profile ?: @""
         playerDimensions:dimensions];

    if (strongSelf->_siteSectionId.length > 0) {
      config.siteSectionConfiguration = [[FWSiteSectionConfiguration alloc]
          initWithSiteSectionId:strongSelf->_siteSectionId
                         idType:FWIdTypeCustom];
    }

    NSString *videoAssetId = strongSelf->_videoAssetId.length > 0
        ? strongSelf->_videoAssetId
        : (video.properties[kBCOVVideoPropertyKeyId] ?: @"video");
    config.videoAssetConfiguration = [[FWVideoAssetConfiguration alloc]
        initWithVideoAssetId:videoAssetId
                      idType:FWIdTypeCustom
                    duration:duration
                durationType:FWVideoAssetDurationTypeExact
                autoPlayType:FWVideoAssetAutoPlayTypeAttended];

    [config addSlotConfiguration:[[FWTemporalSlotConfiguration alloc]
        initWithCustomId:@"preroll"
                  adUnit:FWAdUnitPreroll
            timePosition:0.0]];
    [config addSlotConfiguration:[[FWTemporalSlotConfiguration alloc]
        initWithCustomId:@"postroll"
                  adUnit:FWAdUnitPostroll
            timePosition:0.0]];

    return [[BCOVFWContext alloc] initWithAdContext:adContext requestConfiguration:config];
  };

  return [sdkManager createFWSessionProviderWithAdContextPolicy:policy
                                        upstreamSessionProvider:upstream
                                                        options:options];
}

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  _currentSession = session;
  _acceptCallbacks = YES;

  auto emitter = [_host typedEventEmitter];
  if (!emitter) {
    return;
  }

  if ([lifecycleEvent.eventType isEqualToString:kBCOVFWLifecycleEventAdError]) {
    NSDictionary *info = lifecycleEvent.properties[kBCOVFWLifecycleEventPropertyKeyAdError];
    NSString *message = [info description] ?: @"FreeWheel ad error";
    emitter->onAdError(facebook::react::BrightcovePlayerViewEventEmitter::OnAdError{
      .code = "unknown",
      .message = std::string(message.UTF8String ?: "FreeWheel ad error"),
      .nativeCode = "freewheel_ad_error",
    });
  }
}

#pragma mark BCOVPlaybackControllerAdsDelegate

- (void)onEnterAdSequence
{
  if (![self canEmit]) {
    return;
  }
  auto emitter = [_host typedEventEmitter];
  if (emitter) {
    emitter->onAdBreakStarted(facebook::react::BrightcovePlayerViewEventEmitter::OnAdBreakStarted{
      .index = -1,
    });
  }
}

- (void)onExitAdSequence
{
  if (![self canEmit]) {
    return;
  }
  auto emitter = [_host typedEventEmitter];
  if (emitter) {
    emitter->onAdBreakEnded(facebook::react::BrightcovePlayerViewEventEmitter::OnAdBreakEnded{
      .index = -1,
    });
  }
}

- (void)onEnterAd:(BCOVAd *)ad
{
  if (![self canEmit]) {
    return;
  }
  auto emitter = [_host typedEventEmitter];
  if (emitter) {
    NSString *title = ad.title ?: @"";
    NSTimeInterval duration = CMTimeGetSeconds(ad.duration);
    emitter->onAdStarted(facebook::react::BrightcovePlayerViewEventEmitter::OnAdStarted{
      .adTitle = std::string(title.UTF8String ?: ""),
      .duration = duration > 0 ? duration : 0.0,
    });
  }
}

- (void)onExitAd:(BCOVAd *)ad
{
  if (![self canEmit]) {
    return;
  }
  auto emitter = [_host typedEventEmitter];
  if (emitter) {
    NSString *title = ad.title ?: @"";
    NSTimeInterval duration = CMTimeGetSeconds(ad.duration);
    emitter->onAdCompleted(facebook::react::BrightcovePlayerViewEventEmitter::OnAdCompleted{
      .adTitle = std::string(title.UTF8String ?: ""),
      .duration = duration > 0 ? duration : 0.0,
    });
  }
}

- (void)onSourceReset
{
  _currentSession = nil;
  _acceptCallbacks = NO;
}

- (void)onPlayerTearDown
{
  _currentSession = nil;
  _acceptCallbacks = NO;
}

- (void)onInvalidate
{
  _currentSession = nil;
  _acceptCallbacks = NO;
}

@end
