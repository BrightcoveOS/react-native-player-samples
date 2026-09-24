#import "BrightcoveFullscreenFeature.h"

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

@implementation BrightcoveFullscreenFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  BOOL _isFullscreen;
  BOOL _transitionInFlight;
  dispatch_block_t _pendingTearDown;
  NSUInteger _teardownToken;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet set];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _isFullscreen = NO;
  _transitionInFlight = NO;
  _teardownToken = 0;
}

- (void)setProp:(NSString *)name value:(id)value
{
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveFullscreenFeature owns no prop '%@'", name];
}

- (NSSet<NSString *> *)supportedCommands
{
  return [NSSet setWithObjects:@"enterFullscreen", @"exitFullscreen", nil];
}

- (BOOL)handleCommand:(NSString *)command
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (![command isEqualToString:@"enterFullscreen"] &&
      ![command isEqualToString:@"exitFullscreen"]) {
    return NO;
  }
  if (host == nil || host.isInvalidated || host.playerView == nil) {
    // The player view is not built yet (no window/bounds) or is being torn
    // down — the command cannot run; report it rather than reporting success.
    if (host != nil && !host.isInvalidated) {
      [host emitCommandErrorForCommand:command
                                   code:@"not_ready"
                                message:@"Fullscreen is not available until the player is ready"
                             nativeCode:@"player_view_not_available"];
    }
    return YES;
  }
  if (_transitionInFlight) {
    [host emitCommandErrorForCommand:command
                                code:@"invalid_state"
                             message:@"Fullscreen transition is already in flight"
                          nativeCode:@"transition_in_flight"];
    return YES;
  }
  BOOL entering = [command isEqualToString:@"enterFullscreen"];
  if (entering && _isFullscreen) {
    [host emitCommandErrorForCommand:command
                                code:@"invalid_state"
                             message:@"Player is already in fullscreen"
                          nativeCode:@"already_fullscreen"];
    return YES;
  }
  if (!entering && !_isFullscreen) {
    [host emitCommandErrorForCommand:command
                                code:@"invalid_state"
                             message:@"Player is not in fullscreen"
                          nativeCode:@"not_fullscreen"];
    return YES;
  }
  [host.playerView performScreenTransitionWithScreenMode:
      entering ? BCOVPUIScreenModeFull : BCOVPUIScreenModeNormal];
  return YES;
}

- (void)onScreenModeWillChange:(BCOVPUIScreenMode)screenMode
{
  _transitionInFlight = YES;
}

- (BOOL)prepareForPlayerTearDown:(dispatch_block_t)completion
{
  // If a transition is already in flight, do not issue a second request: the
  // SDK can treat Normal as a no-op while its internal mode is still Normal,
  // which would leave core teardown waiting forever. Delegate detachment in
  // completePlayerTearDown prevents the late transition callback reaching JS.
  if (!_isFullscreen && !_transitionInFlight) {
    _isFullscreen = NO;
    _transitionInFlight = NO;
    _pendingTearDown = nil;
    return NO;
  }
  if (_host.playerView == nil || _host.playerView.window == nil) {
    _isFullscreen = NO;
    _transitionInFlight = NO;
    _pendingTearDown = nil;
    return NO;
  }
  _pendingTearDown = [completion copy];
  NSUInteger teardownToken = ++_teardownToken;
  // If entering fullscreen is already in flight, wait for the SDK to report
  // Full and then request Normal. Issuing Normal immediately can be a no-op
  // while the SDK's internal mode is still Normal.
  if (_isFullscreen && !_transitionInFlight) {
    [_host.playerView performScreenTransitionWithScreenMode:BCOVPUIScreenModeNormal];
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (teardownToken != self->_teardownToken || self->_pendingTearDown == nil) {
      return;
    }
    NSLog(@"BrightcoveFullscreenFeature: fullscreen exit callback did not arrive before teardown timeout");
    dispatch_block_t pending = self->_pendingTearDown;
    self->_pendingTearDown = nil;
    self->_isFullscreen = NO;
    self->_transitionInFlight = NO;
    id<BrightcovePlayerFeatureHost> host = self->_host;
    if (host != nil && !host.isInvalidated) {
      auto eventEmitter = [host typedEventEmitter];
      if (eventEmitter) {
        eventEmitter->onFullscreenChanged(BrightcovePlayerViewEventEmitter::OnFullscreenChanged{
          .active = false,
        });
      }
    }
    pending();
  });
  return YES;
}

- (void)onScreenModeChanged:(BCOVPUIScreenMode)screenMode
{
  _isFullscreen = screenMode == BCOVPUIScreenModeFull;
  _transitionInFlight = NO;
  dispatch_block_t completion = nil;
  if (_pendingTearDown != nil && screenMode == BCOVPUIScreenModeFull) {
    [_host.playerView performScreenTransitionWithScreenMode:BCOVPUIScreenModeNormal];
  } else if (!_isFullscreen && _pendingTearDown != nil) {
    _teardownToken += 1;
    completion = _pendingTearDown;
    _pendingTearDown = nil;
  }

  id<BrightcovePlayerFeatureHost> host = _host;
  if (host != nil && !host.isInvalidated) {
    auto eventEmitter = [host typedEventEmitter];
    if (eventEmitter) {
      eventEmitter->onFullscreenChanged(BrightcovePlayerViewEventEmitter::OnFullscreenChanged{
        .active = _isFullscreen,
      });
    }
  }
  if (completion != nil) {
    completion();
  }
}

- (void)onPlayerTearDown
{
  _isFullscreen = NO;
  _transitionInFlight = NO;
}

- (void)onInvalidate
{
  _isFullscreen = NO;
  _transitionInFlight = NO;
}

@end
