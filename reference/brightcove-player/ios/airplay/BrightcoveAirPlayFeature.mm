#import "BrightcoveAirPlayFeature.h"

using namespace facebook::react;

@implementation BrightcoveAirPlayFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  BOOL _airPlayEnabled;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"airPlayEnabled"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"airPlayEnabled"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveAirPlayFeature does not own prop '%@'", name];
  }

  _airPlayEnabled = [value boolValue];
  [self applyConfiguration];
}

- (void)onPlayerCreated
{
  [self applyConfiguration];
}

- (void)onSourceReset
{
  [self applyConfiguration];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  [self applyConfiguration];
}

- (void)onExternalPlaybackChanged:(BOOL)active
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }

  auto eventEmitter = [host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onExternalPlaybackChanged(
      BrightcovePlayerViewEventEmitter::OnExternalPlaybackChanged{ .active = active });
  }
}

- (void)onPlayerTearDown
{
  [self resetNativePlaybackState];
}

- (void)onInvalidate
{
  [self resetNativePlaybackState];
  _host = nil;
}

- (void)resetNativePlaybackState
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil) {
    return;
  }

  id<BCOVPlaybackController> playbackController = host.playbackController;
  if (playbackController != nil) {
    playbackController.allowsExternalPlayback = NO;
  }

  BCOVPUIPlayerView *playerView = host.playerView;
  if (playerView != nil) {
    playerView.controlsView.routeDetector.routeDetectionEnabled = NO;
  }
}

- (void)applyConfiguration
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }

  id<BCOVPlaybackController> playbackController = host.playbackController;
  if (playbackController != nil) {
    // Brightcove documents this property as the switch that enables AirPlay on
    // the current session and all subsequent sessions.
    playbackController.allowsExternalPlayback = _airPlayEnabled;
  }

  BCOVPUIPlayerView *playerView = host.playerView;
  if (playerView != nil) {
    // Route detection is separate from the SDK's external-playback state. It
    // powers the built-in route picker and is disabled with the feature so an
    // unused player does not keep scanning for routes.
    playerView.controlsView.routeDetector.routeDetectionEnabled = _airPlayEnabled;
  }
}

@end
