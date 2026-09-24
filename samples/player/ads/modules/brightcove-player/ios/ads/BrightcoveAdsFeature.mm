#import "BrightcoveAdsFeature.h"

// Import the SDK's Swift-interop header first: it declares BCOVPlayerSDKManager,
// BCOVMutableVideo, BCOVComponent, etc. as Objective-C interfaces. BrightcoveIMA's
// headers reference those types (via `@import BrightcovePlayerSDK`, which fails
// here because C++ modules are disabled in this .mm), so they must already be
// visible as plain ObjC declarations before BrightcoveIMA is imported.
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <BrightcoveIMA/BrightcoveIMA.h>
#import <GoogleInteractiveMediaAds/GoogleInteractiveMediaAds.h>
#import <math.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static std::string BCOVAdsStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

// IMA does not surface a stable ad-break index on the event; report -1
// ("unknown"), matching the Android side and the TS contract.
static constexpr int32_t kBCOVAdsUnknownAdBreakIndex = -1;

@implementation BrightcoveAdsFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  // The VMAP ad tag. Copied on each set; empty means no ads.
  NSString *_adTagUrl;
  NSMutableSet<NSString *> *_skippedAdIds;
  IMAAd *_currentAd;
  BOOL _adBreakActive;
  id<BCOVPlaybackSession> _currentSession;
  NSHashTable<id<BCOVPlaybackSession>> *_invalidatedSessions;
}

- (instancetype)init
{
  if (self = [super init]) {
    _adTagUrl = @"";
    _skippedAdIds = [NSMutableSet new];
    _adBreakActive = NO;
    _invalidatedSessions = [NSHashTable weakObjectsHashTable];
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"adTagUrl"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

// IMA coordinates the ad-to-content transition internally, but only when the
// controller drives the start via isAutoPlay. If the core called -play on the
// Ready event it would race the asynchronous ads-manager load and, when Ready
// won, wedge the pre-roll on a black frame. See -requiresControllerManagedPlayback
// in BrightcovePlayerFeature.h.
- (BOOL)requiresControllerManagedPlayback
{
  return _adTagUrl.length > 0;
}

- (NSSet<NSString *> *)supportedCommands
{
  if (_currentSession == nil ||
      ![_currentSession.providerExtension respondsToSelector:@selector(ima_play)] ||
      ![_currentSession.providerExtension respondsToSelector:@selector(ima_pause)]) {
    return [NSSet set];
  }
  return [NSSet setWithObjects:@"play", @"pause", nil];
}

- (BOOL)handleCommand:(NSString *)command
{
  if (![self.supportedCommands containsObject:command]) {
    return NO;
  }
  if ([command isEqualToString:@"play"]) {
    [_currentSession.providerExtension ima_play];
  } else {
    [_currentSession.providerExtension ima_pause];
  }
  return YES;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"adTagUrl"]) {
    _adTagUrl = [(value ?: @"") copy];
    return;
  }
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveAdsFeature does not own prop '%@'", name];
}

- (void)onSourceReset
{
  if (_currentSession != nil) {
    [_invalidatedSessions addObject:_currentSession];
  }
  _currentAd = nil;
  _adBreakActive = NO;
  _currentSession = nil;
  [_skippedAdIds removeAllObjects];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _currentSession = session;
}

- (void)onPlayerTearDown
{
  if (_currentSession != nil) {
    [_invalidatedSessions addObject:_currentSession];
  }
  _currentAd = nil;
  _adBreakActive = NO;
  _currentSession = nil;
  [_skippedAdIds removeAllObjects];
}

- (void)onInvalidate
{
  if (_currentSession != nil) {
    [_invalidatedSessions addObject:_currentSession];
  }
  _currentAd = nil;
  _adBreakActive = NO;
  _currentSession = nil;
  [_invalidatedSessions removeAllObjects];
  [_skippedAdIds removeAllObjects];
}

#pragma mark Session provider chain

- (id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (id<BCOVPlaybackSessionProvider>)upstream
{
  if (_adTagUrl.length == 0) {
    return nil;
  }

  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil) {
    return nil;
  }

  // The ad container is the player view's content overlay; the IMA UI renders
  // into it. It exists because the core creates the player view before
  // composing this chain (see BrightcovePlayerView -ensurePlayer).
  UIView *adContainer = host.playerView.contentOverlayView;
  UIViewController *viewController = host.presentingViewController;
  if (adContainer == nil || viewController == nil) {
    // Without a container/VC IMA cannot render; contribute nothing rather than
    // create a broken provider. Content still plays through the upstream chain.
    return nil;
  }

  IMASettings *imaSettings = [IMASettings new];
  imaSettings.language = NSLocale.currentLocale.languageCode ?: @"en";

  IMAAdsRenderingSettings *renderSettings = [IMAAdsRenderingSettings new];
  renderSettings.linkOpenerPresentingController = viewController;

  // VMAP ("ad rules"): read the tag from each video's properties (stamped in
  // -willSetVideo:), so a per-view tag is honored. This mirrors the native
  // sample's videoPropertiesVMAPAdTagUrl policy.
  BCOVIMAAdsRequestPolicy *adsRequestPolicy =
      [BCOVIMAAdsRequestPolicy videoPropertiesVMAPAdTagUrlAdsRequestPolicy];

  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  return [sdkManager createIMASessionProviderWithSettings:imaSettings
                                     adsRenderingSettings:renderSettings
                                         adsRequestPolicy:adsRequestPolicy
                                              adContainer:adContainer
                                           viewController:viewController
                                           companionSlots:nil
                                  upstreamSessionProvider:upstream
                                                  options:nil];
}

#pragma mark Ad tag injection

// The IMA VMAP policy reads the ad tag from the video's kBCOVIMAAdTag property.
// The core asks each feature to transform the video before it is set on the
// controller; stamp the current VMAP URL here so IMA requests that schedule.
- (BCOVVideo *)willSetVideo:(BCOVVideo *)video
{
  if (_adTagUrl.length == 0) {
    return video;
  }
  NSString *tag = [_adTagUrl copy];
  return [video update:^(BCOVMutableVideo *mutableVideo) {
    NSMutableDictionary *properties = [mutableVideo.properties mutableCopy];
    properties[kBCOVIMAAdTag] = tag;
    mutableVideo.properties = properties;
  }];
}

#pragma mark Ad lifecycle -> JS events

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  // The core forwards lifecycle events to features before its own teardown
  // bookkeeping; ignore anything arriving after the view was invalidated so a
  // late IMA event cannot emit onto a torn-down emitter. Mirrors the captions
  // feature's isInvalidated guard.
  if (_host == nil || _host.isInvalidated) {
    return;
  }

  if (![self isCurrentSession:session]) {
    return;
  }

  NSString *type = lifecycleEvent.eventType;

  if ([type isEqualToString:kBCOVIMALifecycleEventAdsManagerDidReceiveAdError] ||
      [type isEqualToString:kBCOVIMALifecycleEventAdsLoaderFailed]) {
    id rawError = lifecycleEvent.properties[kBCOVIMALifecycleEventPropertyKeyAdError];
    if (![rawError isKindOfClass:IMAAdError.class]) {
      [self emitAdErrorWithCode:@"unknown"
                         message:@"IMA returned an invalid ad error payload"
                      nativeCode:@"invalid_ad_error_payload"];
      return;
    }

    IMAAdError *adError = (IMAAdError *)rawError;
    NSString *code = [self categoryForAdError:adError];
    NSString *message = adError.message ?: @"Ad request or playback failed";
    NSString *nativeCode = [NSString stringWithFormat:@"%ld", (long)adError.code];
    [self emitAdErrorWithCode:code message:message nativeCode:nativeCode];
    return;
  }

  if ([type isEqualToString:kBCOVIMALifecycleEventAdsManagerDidReceiveAdEvent]) {
    IMAAdEvent *adEvent = lifecycleEvent.properties[kBCOVIMALifecycleEventPropertyKeyAdEvent];
    if (adEvent != nil) {
      [self handleIMAAdEvent:adEvent];
    }
  }
}

- (void)handleIMAAdEvent:(IMAAdEvent *)adEvent
{
  switch (adEvent.type) {
    case kIMAAdEvent_AD_BREAK_STARTED:
      [self beginAdBreak];
      break;
    case kIMAAdEvent_AD_BREAK_ENDED:
      [self endAdBreak];
      break;
    case kIMAAdEvent_STARTED: {
      _currentAd = adEvent.ad;
      [self emitAdStarted:YES ad:adEvent.ad];
      [self emitAdMetadata:adEvent.ad];
      if (adEvent.ad != nil && !adEvent.ad.isLinear) {
        [self emitAdOverlayState:adEvent.ad.adId visible:YES];
      }
      break;
    }
    case kIMAAdEvent_COMPLETE: {
      IMAAd *ad = [self adForEvent:adEvent];
      if (ad.adId.length > 0 && [_skippedAdIds containsObject:ad.adId]) {
        [_skippedAdIds removeObject:ad.adId];
        return;
      }
      [self emitAdStarted:NO ad:ad];
      if (ad != nil && !ad.isLinear) {
        [self emitAdOverlayState:ad.adId visible:NO];
      }
      _currentAd = nil;
      break;
    }
    case kIMAAdEvent_SKIPPED: {
      IMAAd *ad = [self adForEvent:adEvent];
      if (ad.adId.length > 0) {
        [_skippedAdIds addObject:ad.adId];
      }
      [self emitAdSkipped:ad.adId ?: @""];
      // The existing onAdCompleted contract includes IMA skips. Emit it here
      // because the IMA SKIPPED callback is not forwarded as a separate
      // Brightcove completion event on iOS.
      [self emitAdStarted:NO ad:ad];
      if (ad != nil && !ad.isLinear) {
        [self emitAdOverlayState:ad.adId visible:NO];
      }
      _currentAd = nil;
      break;
    }
    case kIMAAdEvent_PAUSE: {
      IMAAd *ad = [self adForEvent:adEvent];
      [self emitAdPaused:ad.adId ?: @""];
      break;
    }
    case kIMAAdEvent_RESUME: {
      IMAAd *ad = [self adForEvent:adEvent];
      [self emitAdResumed:ad.adId ?: @""];
      break;
    }
    case kIMAAdEvent_FIRST_QUARTILE: {
      IMAAd *ad = [self adForEvent:adEvent];
      [self emitAdQuartile:25 adId:ad.adId ?: @""];
      break;
    }
    case kIMAAdEvent_MIDPOINT: {
      IMAAd *ad = [self adForEvent:adEvent];
      [self emitAdQuartile:50 adId:ad.adId ?: @""];
      break;
    }
    case kIMAAdEvent_THIRD_QUARTILE: {
      IMAAd *ad = [self adForEvent:adEvent];
      [self emitAdQuartile:75 adId:ad.adId ?: @""];
      break;
    }
    case kIMAAdEvent_CLICKED: {
      IMAAd *ad = [self adForEvent:adEvent];
      [self emitAdInteraction:@"clicked" adId:ad.adId ?: @""];
      break;
    }
    case kIMAAdEvent_TAPPED: {
      IMAAd *ad = [self adForEvent:adEvent];
      [self emitAdInteraction:@"tapped" adId:ad.adId ?: @""];
      break;
    }
    case kIMAAdEvent_ALL_ADS_COMPLETED:
      [self emitAllAdsCompleted];
      _currentAd = nil;
      break;
    default:
      break;
  }
}

- (void)onEnterAdSequence
{
  [self beginAdBreak];
}

- (void)onExitAdSequence
{
  [self endAdBreak];
}

- (void)onAdProgress:(BCOVAd *)ad progress:(NSTimeInterval)progress
{
  if (_host == nil || _host.isInvalidated || ad == nil || ad.adId.length == 0) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  if (!isfinite(progress) || progress < 0.0) {
    return;
  }
  double duration = CMTimeGetSeconds(ad.duration);
  if (!isfinite(duration) || duration < 0.0) {
    duration = 0.0;
  }
  eventEmitter->onAdProgress(BrightcovePlayerViewEventEmitter::OnAdProgress{
    .adId = BCOVAdsStdStringFromNSString(ad.adId ?: @""),
    .positionSeconds = progress,
    .durationSeconds = duration,
  });
}

- (void)emitAdPaused:(NSString *)adId
{
  if (_host == nil || _host.isInvalidated || adId.length == 0) return;
  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAdPaused(BrightcovePlayerViewEventEmitter::OnAdPaused{
      .adId = BCOVAdsStdStringFromNSString(adId),
    });
  }
}

- (IMAAd *)adForEvent:(IMAAdEvent *)adEvent
{
  return adEvent.ad ?: _currentAd;
}

- (BOOL)isCurrentSession:(id<BCOVPlaybackSession>)session
{
  if (session == nil || [_invalidatedSessions containsObject:session]) {
    return NO;
  }
  if (_host != nil) {
    // The core's generation tag is authoritative and already rejects stale
    // requests: every loader this repository ships stamps its videos,
    // including preloading's inserted next-up item whose id differs from the
    // videoId prop. The removed id-equality check dropped every ad event for
    // that item; a current-generation session can never name another view's
    // or another request's video.
    return [_host isCurrentPlaybackSession:session];
  }
  return YES;
}

- (void)beginAdBreak
{
  if (_adBreakActive) {
    return;
  }
  _adBreakActive = YES;
  [self emitAdBreak:YES];
}

- (void)endAdBreak
{
  if (!_adBreakActive) {
    return;
  }
  _adBreakActive = NO;
  [self emitAdBreak:NO];
}

- (void)emitAdResumed:(NSString *)adId
{
  if (_host == nil || _host.isInvalidated || adId.length == 0) return;
  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAdResumed(BrightcovePlayerViewEventEmitter::OnAdResumed{
      .adId = BCOVAdsStdStringFromNSString(adId),
    });
  }
}

- (void)emitAdSkipped:(NSString *)adId
{
  if (_host == nil || _host.isInvalidated || adId.length == 0) return;
  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAdSkipped(BrightcovePlayerViewEventEmitter::OnAdSkipped{
      .adId = BCOVAdsStdStringFromNSString(adId),
    });
  }
}

- (void)emitAdQuartile:(int32_t)quartile adId:(NSString *)adId
{
  if (_host == nil || _host.isInvalidated || adId.length == 0) return;
  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAdQuartile(BrightcovePlayerViewEventEmitter::OnAdQuartile{
      .adId = BCOVAdsStdStringFromNSString(adId),
      .quartile = quartile,
    });
  }
}

- (void)emitAdInteraction:(NSString *)interaction adId:(NSString *)adId
{
  if (_host == nil || _host.isInvalidated || adId.length == 0) return;
  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAdInteraction(BrightcovePlayerViewEventEmitter::OnAdInteraction{
      .adId = BCOVAdsStdStringFromNSString(adId),
      .interaction = BCOVAdsStdStringFromNSString(interaction),
    });
  }
}

- (void)emitAdMetadata:(IMAAd *)ad
{
  if (_host == nil || _host.isInvalidated || ad == nil) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  eventEmitter->onAdMetadata(BrightcovePlayerViewEventEmitter::OnAdMetadata{
    .adId = BCOVAdsStdStringFromNSString(ad.adId ?: @""),
    .adTitle = BCOVAdsStdStringFromNSString(ad.adTitle ?: @""),
    .advertiserName = BCOVAdsStdStringFromNSString(ad.advertiserName ?: @""),
    .durationSeconds = ad.duration,
    .isLinear = (bool)ad.isLinear,
    .width = (int32_t)ad.width,
    .height = (int32_t)ad.height,
    .isSkippable = (bool)ad.isSkippable,
    .skipTimeOffsetSeconds = ad.skipTimeOffset,
  });
}

- (void)emitAdOverlayState:(NSString *)adId visible:(BOOL)visible
{
  if (_host == nil || _host.isInvalidated || adId.length == 0) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAdOverlayStateChanged(BrightcovePlayerViewEventEmitter::OnAdOverlayStateChanged{
      .adId = BCOVAdsStdStringFromNSString(adId ?: @""),
      .visible = (bool)visible,
    });
  }
}

- (void)emitAdStarted:(BOOL)started ad:(IMAAd *)ad
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  // ad may be nil for an ad event that carries no IMAAd; treat title/duration
  // as empty/zero rather than relying on nil-messaging for one field and a
  // guard for the other.
  std::string adTitle = ad ? BCOVAdsStdStringFromNSString(ad.adTitle ?: @"") : std::string();
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
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  if (started) {
    eventEmitter->onAdBreakStarted(BrightcovePlayerViewEventEmitter::OnAdBreakStarted{
      .index = kBCOVAdsUnknownAdBreakIndex,
    });
  } else {
    eventEmitter->onAdBreakEnded(BrightcovePlayerViewEventEmitter::OnAdBreakEnded{
      .index = kBCOVAdsUnknownAdBreakIndex,
    });
  }
}

- (void)emitAllAdsCompleted
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAllAdsCompleted(BrightcovePlayerViewEventEmitter::OnAllAdsCompleted{
      .completed = true,
    });
  }
}

- (NSString *)categoryForAdError:(IMAAdError *)adError
{
  switch (adError.type) {
    case kIMAAdLoadingFailed:
      return @"load";
    case kIMAAdPlayingFailed:
      return @"playback";
    case kIMAAdUnknownErrorType:
    default:
      return @"unknown";
  }
}

- (void)emitAdErrorWithCode:(NSString *)code
                    message:(NSString *)message
                 nativeCode:(NSString *)nativeCode
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  eventEmitter->onAdError(BrightcovePlayerViewEventEmitter::OnAdError{
    .code = BCOVAdsStdStringFromNSString(code),
    .message = BCOVAdsStdStringFromNSString(message),
    .nativeCode = BCOVAdsStdStringFromNSString(nativeCode),
  });
}

@end
