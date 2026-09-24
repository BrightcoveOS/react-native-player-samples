#import "BrightcoveVideo360Feature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

@implementation BrightcoveVideo360Feature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  BOOL _requestedVrMode;
  BOOL _activeVrMode;
  BOOL _is360Video;
  NSString *_lastReportedModeKey;
  NSNumber *_lastReportedIs360;
  BOOL _sourceResetReported;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"vrMode"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(nullable id)value
{
  if ([name isEqualToString:@"vrMode"]) {
    if (![value isKindOfClass:NSNumber.class]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"BrightcoveVideo360Feature requires a Boolean for '%@'", name];
    }
    BOOL newVrMode = [value boolValue];
    if (_requestedVrMode != newVrMode) {
      _requestedVrMode = newVrMode;
      [self applyVrMode];
    }
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveVideo360Feature does not own prop '%@'", name];
  }
}

- (void)configurePlayerViewOptions:(BCOVPUIPlayerViewOptions *)options
{
  options.automaticControlTypeSelection = YES;
}

- (void)onSourceReset
{
  BCOVVideo360ViewProjection *current = _host.playbackController.viewProjection;
  BOOL nativeVrMode = current != nil &&
      current.projectionStyle == BCOVVideo360ProjectionStyleVRGoggles;
  if (nativeVrMode) {
    BCOVVideo360ViewProjection *projection = [current copy];
    projection.projectionStyle = BCOVVideo360ProjectionStyleNormal;
    _host.playbackController.viewProjection = projection;
  }
  _activeVrMode = NO;
  _is360Video = NO;
  _lastReportedModeKey = nil;
  _lastReportedIs360 = nil;
  if (!_sourceResetReported) {
    [self emitProjectionFormatChanged:@"normal" is360:NO];
    [self emitVideo360ModeChanged:NO projectionStyle:@"normal" navigationMethod:@"none"];
    _sourceResetReported = YES;
  }
}

// Reads the SDK's own projection-format property once the session is ready —
// the SDK stamps this on BCOVVideo.properties itself, so no core-level video
// transform (Android's onVideoLoaded / iOS's willSetVideo:) is needed here.
- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  if (session.video == nil) {
    return;
  }

  NSString *projection = session.video.properties[[BCOVVideo PropertyKeyProjection]];
  BOOL isEquirectangular = [projection isEqualToString:@"equirectangular"];
  _is360Video = isEquirectangular;
  _sourceResetReported = NO;
  _lastReportedIs360 = nil;
  _lastReportedModeKey = nil;

  [self emitProjectionFormatChanged:isEquirectangular ? @"equirectangular" : @"normal"
                              is360:isEquirectangular];

  if (isEquirectangular && !_requestedVrMode) {
    [self emitVideo360ModeChanged:NO
                   projectionStyle:@"normal"
                  navigationMethod:[self navigationMethodString]];
  } else if (_requestedVrMode && isEquirectangular) {
    [self applyVrMode];
  }
}

- (void)didSetVideo360NavigationMethod:(BCOVPUIVideo360NavigationMethod)navigationMethod
                       projectionStyle:(BCOVVideo360ProjectionStyle)projectionStyle
{
  if (!_is360Video) {
    return;
  }
  BOOL vrModeActive = (projectionStyle == BCOVVideo360ProjectionStyleVRGoggles);
  _requestedVrMode = vrModeActive;
  _activeVrMode = vrModeActive;
  NSString *styleString = vrModeActive ? @"vrGoggles" : @"normal";
  NSString *methodString = @"none";
  if (navigationMethod == BCOVPUIVideo360NavigationDeviceMotionTracking) {
    methodString = @"deviceMotion";
  } else if (navigationMethod == BCOVPUIVideo360NavigationFingerTracking) {
    methodString = @"fingerTracking";
  }

  [self emitVideo360ModeChanged:vrModeActive
                projectionStyle:styleString
               navigationMethod:methodString];
}

- (NSString *)navigationMethodString
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host.playerView == nil) {
    return @"unknown";
  }

  switch (host.playerView.video360NavigationMethod) {
    case BCOVPUIVideo360NavigationDeviceMotionTracking:
      return @"deviceMotion";
    case BCOVPUIVideo360NavigationFingerTracking:
      return @"fingerTracking";
    case BCOVPUIVideo360NavigationNone:
      return @"none";
  }
  return @"unknown";
}

- (void)applyVrMode
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.playbackController == nil || (!_is360Video && _requestedVrMode)) {
    return;
  }

  BCOVVideo360ViewProjection *current = host.playbackController.viewProjection;
  if (current == nil) {
    return;
  }

  BOOL targetVrMode = _requestedVrMode && _is360Video;
  BCOVVideo360ViewProjection *projection = [current copy];
  projection.projectionStyle = targetVrMode ? BCOVVideo360ProjectionStyleVRGoggles : BCOVVideo360ProjectionStyleNormal;
  host.playbackController.viewProjection = projection;

  if (_activeVrMode != targetVrMode) {
    _activeVrMode = targetVrMode;
    NSString *style = targetVrMode ? @"vrGoggles" : @"normal";
    [self emitVideo360ModeChanged:targetVrMode
                   projectionStyle:style
                  navigationMethod:[self navigationMethodString]];
  }
}

- (void)emitProjectionFormatChanged:(NSString *)projectionFormat is360:(BOOL)is360
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil) {
    return;
  }

  auto emitter = [host typedEventEmitter];
  if (!emitter || (_lastReportedIs360 != nil && _lastReportedIs360.boolValue == is360)) {
    return;
  }
  _lastReportedIs360 = @(is360);
  emitter->onProjectionFormatChanged(facebook::react::BrightcovePlayerViewEventEmitter::OnProjectionFormatChanged{
    .projectionFormat = std::string(projectionFormat.UTF8String ?: ""),
    .is360 = (bool)is360,
  });
}

- (void)emitVideo360ModeChanged:(BOOL)vrMode
                projectionStyle:(NSString *)projectionStyle
               navigationMethod:(NSString *)navigationMethod
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil) {
    return;
  }

  auto emitter = [host typedEventEmitter];
  if (!emitter) {
    return;
  }

  NSString *modeKey = [NSString stringWithFormat:@"%@|%@|%@",
                       vrMode ? @"1" : @"0",
                       projectionStyle ?: @"",
                       navigationMethod ?: @""];
  if ([_lastReportedModeKey isEqualToString:modeKey]) {
    return;
  }
  _lastReportedModeKey = modeKey;

  emitter->onVideo360ModeChanged(facebook::react::BrightcovePlayerViewEventEmitter::OnVideo360ModeChanged{
    .vrMode = (bool)vrMode,
    .projectionStyle = std::string(projectionStyle.UTF8String ?: ""),
    .navigationMethod = std::string(navigationMethod.UTF8String ?: ""),
  });
}

- (void)onPlayerTearDown
{
  if (_activeVrMode) {
    [self emitVideo360ModeChanged:NO projectionStyle:@"normal" navigationMethod:@"none"];
  }
  _activeVrMode = NO;
  _is360Video = NO;
  _lastReportedModeKey = nil;
  _lastReportedIs360 = nil;
}

- (void)onInvalidate
{
  _host = nil;
  _activeVrMode = NO;
  _is360Video = NO;
  _lastReportedModeKey = nil;
  _lastReportedIs360 = nil;
}

@end
