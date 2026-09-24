#import "BrightcoveSsaiFeature.h"

// Import the SDK's Swift-interop header first so BCOVPlayerSDKManager,
// BCOVAd, etc. are visible as Objective-C declarations before BrightcoveSSAI's
// headers (which reference them) are imported.
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <BrightcoveSSAI/BrightcoveSSAI.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static std::string BCOVSsaiStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

@implementation BrightcoveSsaiFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  // The VideoCloud ad-config id. Copied on each set; empty means no ads.
  NSString *_adConfigId;
}

- (instancetype)init
{
  if (self = [super init]) {
    _adConfigId = @"";
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"adConfigId"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"adConfigId"]) {
    // Trim so a whitespace-only id is treated as "no ads" (plain content),
    // matching Android's ifBlank normalization; otherwise iOS would send a
    // garbage ad_config_id query param and build an SSAI provider for it.
    NSString *trimmed = [(value ?: @"")
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _adConfigId = [trimmed copy];
    return;
  }
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveSsaiFeature does not own prop '%@'", name];
}

#pragma mark Source request + session provider chain

// Add the ad-config id to the Playback API request so VideoCloud returns a
// VMAP-bearing video. With no id, no parameter is added and content plays
// without ads.
- (NSDictionary<NSString *, NSString *> *)additionalSourceQueryParameters
{
  if (_adConfigId.length == 0) {
    return nil;
  }
  return @{[BCOVPlaybackService ParamaterKeyAdConfigId]: [_adConfigId copy]};
}

// SSAI is a session provider that chains like FairPlay/IMA. It takes only the
// upstream provider — no ad container or settings at construction (unlike IMA).
// Contribute one only when SSAI is actually configured, so a blank ad-config
// plays plain content through the upstream chain.
- (id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (id<BCOVPlaybackSessionProvider>)upstream
{
  if (_adConfigId.length == 0) {
    return nil;
  }
  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  return [sdkManager createSSAISessionProviderWithUpstreamSessionProvider:upstream];
}

- (void)configurePlaybackController:(id<BCOVPlaybackController>)controller
{
  if (_adConfigId.length == 0) {
    return;
  }
  BCOVSSAIAdComponentDisplayContainer *displayContainer =
      [[BCOVSSAIAdComponentDisplayContainer alloc] initWithCompanionSlots:nil];
  [controller addSessionConsumer:displayContainer];
}

#pragma mark Ad lifecycle -> JS events

- (void)onEnterAdSequence
{
  [self emitAdBreak:YES];
}

- (void)onExitAdSequence
{
  [self emitAdBreak:NO];
}

- (void)onEnterAd:(BCOVAd *)ad
{
  [self emitAd:YES ad:ad];
}

- (void)onExitAd:(BCOVAd *)ad
{
  [self emitAd:NO ad:ad];
}

// SSAI errors are delivered on the lifecycle channel as kBCOVSSAILifecycleErrorEvent.
- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  if (_host == nil || _host.isInvalidated || ![_host isCurrentPlaybackSession:session]) {
    return;
  }
  // Fatal SSAI timeline/VMAP failures are classified by the core through
  // sourceErrorForLifecycleEvent and must not be emitted as ad-only failures.
}

- (NSError *)sourceErrorForLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                                   session:(id<BCOVPlaybackSession>)session
{
  if (_host == nil || _host.isInvalidated || ![_host isCurrentPlaybackSession:session] ||
      ![lifecycleEvent.eventType isEqualToString:kBCOVSSAILifecycleErrorEvent]) {
    return nil;
  }

  NSError *error = lifecycleEvent.properties[kBCOVSSAILifecycleEventPropertiesKeyError];
  if (error != nil) {
    return error;
  }

  return [NSError errorWithDomain:kBCOVSSAIErrorDomain
                              code:kBCOVSSAIErrorCodeTimelineLoadError
                          userInfo:@{
                            NSLocalizedDescriptionKey: @"Server-side ad insertion failed before playback",
                          }];
}

- (void)emitAd:(BOOL)started ad:(BCOVAd *)ad
{
  // The ad boundaries arrive on the core's ads-delegate channel, which can fire
  // during teardown; ignore anything after the view was invalidated so a late
  // callback cannot emit onto a stale emitter (mirrors onLifecycleEvent and the
  // ads feature).
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  std::string adTitle = ad ? BCOVSsaiStdStringFromNSString(ad.title ?: @"") : std::string();
  // BCOVAd.duration is a CMTime; convert to seconds (0 when indefinite/unset).
  double duration = 0.0;
  if (ad != nil && CMTIME_IS_NUMERIC(ad.duration)) {
    duration = CMTimeGetSeconds(ad.duration);
  }
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
  // No stable ad-break index on this channel; report -1, matching Android and
  // the TS contract.
  if (started) {
    eventEmitter->onAdBreakStarted(BrightcovePlayerViewEventEmitter::OnAdBreakStarted{
      .index = -1,
    });
  } else {
    eventEmitter->onAdBreakEnded(BrightcovePlayerViewEventEmitter::OnAdBreakEnded{
      .index = -1,
    });
  }
}

// There is no onAdError emitter here on purpose. The BrightcoveSSAI iOS SDK
// surfaces SSAI failures only on the lifecycle channel
// (kBCOVSSAILifecycleErrorEvent), with timeline-load / VMAP-missing codes that
// are fatal before the stitched stream exists — those are content errors, not
// per-ad errors. With no recoverable ad-error signal, the SDK cannot back the
// cross-platform onAdError contract on iOS, so the iOS public entry point
// (index.ios.tsx) omits onAdError rather than advertising an event that can
// never fire. See scripts/feature-catalog.sh feature_ios_unsupported_props.

@end
