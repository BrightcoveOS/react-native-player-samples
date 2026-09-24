#import "BrightcovePulseFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <BrightcovePulse/BrightcovePulse.h>
#import <Pulse/Pulse.h>
#import <math.h>

@interface BrightcovePulseFeature () <BCOVPulsePlaybackSessionDelegate>
@end

@implementation BrightcovePulseFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  NSString *_pulseHost;
  NSString *_pulseCategory;
  NSString *_pulseTags;
  NSString *_pulseContentMetadataTitle;
  NSString *_pulseMidrollPositions;
  __weak id<BCOVPlaybackSession> _currentSession;
  BOOL _acceptCallbacks;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:
      @"pulseHost",
      @"pulseCategory",
      @"pulseTags",
      @"pulseContentMetadataTitle",
      @"pulseMidrollPositions",
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

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  _currentSession = session;
  _acceptCallbacks = YES;
}

- (void)setProp:(NSString *)name value:(nullable id)value
{
  if ([name isEqualToString:@"pulseHost"]) {
    _pulseHost = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"pulseCategory"]) {
    _pulseCategory = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"pulseTags"]) {
    _pulseTags = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"pulseContentMetadataTitle"]) {
    _pulseContentMetadataTitle = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"pulseMidrollPositions"]) {
    _pulseMidrollPositions = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcovePulseFeature owns no prop '%@'", name];
  }
}

- (BOOL)requiresControllerManagedPlayback
{
  return _pulseHost.length > 0;
}

- (nullable id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (nullable id<BCOVPlaybackSessionProvider>)upstream
{
  if (_pulseHost.length == 0) {
    return nil;
  }

  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  OOContentMetadata *contentMetadata = [OOContentMetadata new];
  if (_pulseCategory.length > 0) {
    contentMetadata.category = _pulseCategory;
  }
  if (_pulseTags.length > 0) {
    NSArray *tagList = [_pulseTags componentsSeparatedByString:@","];
    NSMutableArray *trimmedTags = [NSMutableArray array];
    for (NSString *t in tagList) {
      NSString *trimmed = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if (trimmed.length > 0) {
        [trimmedTags addObject:trimmed];
      }
    }
    contentMetadata.tags = trimmedTags;
  }
  if (_pulseContentMetadataTitle.length > 0) {
    contentMetadata.identifier = _pulseContentMetadataTitle;
  }

  OORequestSettings *requestSettings = [OORequestSettings new];
  if (_pulseMidrollPositions.length > 0) {
    requestSettings.linearPlaybackPositions = [self parsedMidrollPositions];
  }
  UIView *adContainer = _host.playerView.contentOverlayView ?: _host.hostView;

  NSDictionary *options = @{
    kBCOVPulseOptionPulsePlaybackSessionDelegateKey: self,
  };

  return [sdkManager createPulseSessionProviderWithPulseHost:_pulseHost
                                             contentMetadata:contentMetadata
                                             requestSettings:requestSettings
                                                 adContainer:adContainer
                                              companionSlots:@[]
                                     upstreamSessionProvider:upstream
                                                     options:options];
}

#pragma mark BCOVPulsePlaybackSessionDelegate

- (id<OOPulseSession>)createSessionForVideo:(BCOVVideo *)video
                              withPulseHost:(NSString *)pulseHost
                            contentMetadata:(OOContentMetadata *)contentMetadata
                            requestSettings:(OORequestSettings *)requestSettings
{
  if (_pulseCategory.length > 0) {
    contentMetadata.category = _pulseCategory;
  }
  if (_pulseTags.length > 0) {
    NSArray *tagList = [_pulseTags componentsSeparatedByString:@","];
    NSMutableArray *trimmedTags = [NSMutableArray array];
    for (NSString *t in tagList) {
      NSString *trimmed = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if (trimmed.length > 0) {
        [trimmedTags addObject:trimmed];
      }
    }
    contentMetadata.tags = trimmedTags;
  }
  contentMetadata.identifier = _pulseContentMetadataTitle.length > 0
      ? _pulseContentMetadataTitle
      : (video.properties[kBCOVVideoPropertyKeyId] ?: @"demo");
  if (_pulseMidrollPositions.length > 0) {
    requestSettings.linearPlaybackPositions = [self parsedMidrollPositions];
  }

  return [OOPulse sessionWithContentMetadata:contentMetadata requestSettings:requestSettings];
}

- (NSArray<NSNumber *> *)parsedMidrollPositions
{
  NSMutableArray<NSNumber *> *positions = [NSMutableArray array];
  for (NSString *rawPosition in [_pulseMidrollPositions componentsSeparatedByString:@","]) {
    NSString *position = [rawPosition stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:position];
    double seconds = 0.0;
    if (position.length == 0 || ![scanner scanDouble:&seconds] ||
        !scanner.isAtEnd || !isfinite(seconds) || seconds < 0.0) {
      [NSException raise:NSInvalidArgumentException
                  format:@"pulseMidrollPositions must contain non-negative finite seconds"];
    }
    [positions addObject:@(seconds)];
  }
  return positions;
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
