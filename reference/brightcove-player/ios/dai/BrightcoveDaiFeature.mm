#import "BrightcoveDaiFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <BrightcoveDAI/BrightcoveDAI.h>
#import <GoogleInteractiveMediaAds/GoogleInteractiveMediaAds.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static std::string BCOVDaiStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

static constexpr int32_t kBCOVDaiUnknownAdBreakIndex = -1;

@implementation BrightcoveDaiFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;

  NSString *_daiSourceId;
  NSString *_daiVideoId;
}

- (instancetype)init
{
  if (self = [super init]) {
    _daiSourceId = @"";
    _daiVideoId = @"";
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:@"daiSourceId", @"daiVideoId", nil];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (BOOL)requiresControllerManagedPlayback
{
  return _daiSourceId.length > 0 && _daiVideoId.length > 0;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"daiSourceId"]) {
    _daiSourceId = [(value ?: @"") copy];
    return;
  }
  if ([name isEqualToString:@"daiVideoId"]) {
    _daiVideoId = [(value ?: @"") copy];
    return;
  }
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveDaiFeature does not own prop '%@'", name];
}

- (id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (id<BCOVPlaybackSessionProvider>)upstream
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || _daiSourceId.length == 0 || _daiVideoId.length == 0) {
    return upstream;
  }

  UIView *adContainer = host.playerView.contentOverlayView;
  UIViewController *viewController = host.presentingViewController;
  if (adContainer == nil || viewController == nil) {
    return upstream;
  }

  BCOVDAIAdsRequestPolicy *adsRequestPolicy =
      [BCOVDAIAdsRequestPolicy videoPropertiesAdsRequestPolicy];

  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  return [sdkManager createDAISessionProviderWithSettings:nil
                                     adsRenderingSettings:nil
                                         adsRequestPolicy:adsRequestPolicy
                                              adContainer:adContainer
                                           viewController:viewController
                                           companionSlots:nil
                                  upstreamSessionProvider:upstream];
}

- (BCOVVideo *)willSetVideo:(BCOVVideo *)video
{
  if (_daiSourceId.length == 0 || _daiVideoId.length == 0) {
    return video;
  }

  NSString *sourceId = [_daiSourceId copy];
  NSString *videoId = [_daiVideoId copy];
  return [video update:^(BCOVMutableVideo *mutableVideo) {
    NSMutableDictionary *properties = [mutableVideo.properties mutableCopy];
    properties[kBCOVDAIVideoPropertiesKeySourceId] = sourceId;
    properties[kBCOVDAIVideoPropertiesKeyVideoId] = videoId;
    mutableVideo.properties = properties;
  }];
}

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                  session:(id<BCOVPlaybackSession>)session
{
  if (_host == nil || _host.isInvalidated || ![_host isCurrentPlaybackSession:session]) {
    return;
  }

  NSString *type = lifecycleEvent.eventType;

  if ([type isEqualToString:kBCOVDAILifecycleEventAdsLoaderFailed] ||
      [type isEqualToString:kBCOVDAILifecycleEventAdsManagerDidReceiveAdError]) {
    NSError *error = lifecycleEvent.properties[kBCOVDAILifecycleEventPropertyKeyAdError];
    NSString *code = [type isEqualToString:kBCOVDAILifecycleEventAdsLoaderFailed] ? @"load" : @"playback";
    [self emitAdErrorWithCode:code error:error];
    return;
  }

  if ([type isEqualToString:kBCOVDAILifecycleEventAdsManagerDidReceiveAdEvent]) {
    IMAAdEvent *adEvent = lifecycleEvent.properties[kBCOVDAILifecycleEventPropertyKeyAdEvent];
    if (adEvent != nil) {
      [self handleIMAAdEvent:adEvent];
    }
  }
}

- (void)handleIMAAdEvent:(IMAAdEvent *)adEvent
{
  switch (adEvent.type) {
    case kIMAAdEvent_AD_BREAK_STARTED:
      [self emitAdBreak:YES];
      break;
    case kIMAAdEvent_AD_BREAK_ENDED:
      [self emitAdBreak:NO];
      break;
    case kIMAAdEvent_STARTED:
      [self emitAdStarted:YES ad:adEvent.ad];
      break;
    case kIMAAdEvent_COMPLETE:
      [self emitAdStarted:NO ad:adEvent.ad];
      break;
    default:
      break;
  }
}

- (void)emitAdStarted:(BOOL)started ad:(IMAAd *)ad
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  auto eventEmitter = [host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  std::string adTitle = ad ? BCOVDaiStdStringFromNSString(ad.adTitle ?: @"") : std::string();
  double duration = ad ? ad.duration : 0.0;
  if (started) {
    eventEmitter->onAdStarted(BrightcovePlayerViewEventEmitter::OnAdStarted{
      .adTitle = adTitle,
      .duration = duration,
    });
  } else {
    eventEmitter->onAdCompleted(BrightcovePlayerViewEventEmitter::OnAdCompleted{
      .adTitle = adTitle,
      .duration = duration,
    });
  }
}

- (void)emitAdBreak:(BOOL)started
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  auto eventEmitter = [host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  if (started) {
    eventEmitter->onAdBreakStarted(BrightcovePlayerViewEventEmitter::OnAdBreakStarted{
      .index = kBCOVDaiUnknownAdBreakIndex,
    });
  } else {
    eventEmitter->onAdBreakEnded(BrightcovePlayerViewEventEmitter::OnAdBreakEnded{
      .index = kBCOVDaiUnknownAdBreakIndex,
    });
  }
}

- (void)emitAdErrorWithCode:(NSString *)code error:(NSError *)error
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  auto eventEmitter = [host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  NSString *message = error.localizedDescription ?: @"DAI ad playback failed";
  NSString *nativeCode = error
      ? [NSString stringWithFormat:@"%@:%ld", error.domain, (long)error.code]
      : @"dai_ad_error";
  eventEmitter->onAdError(BrightcovePlayerViewEventEmitter::OnAdError{
    .code = BCOVDaiStdStringFromNSString(code),
    .message = BCOVDaiStdStringFromNSString(message),
    .nativeCode = BCOVDaiStdStringFromNSString(nativeCode),
  });
}

@end
