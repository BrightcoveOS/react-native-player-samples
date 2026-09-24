#import "BrightcoveControlsFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

@implementation BrightcoveControlsFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  BOOL _controlsEnabled;
}

- (instancetype)init
{
  if (self = [super init]) {
    _controlsEnabled = YES;
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"controlsEnabled"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"controlsEnabled"]) {
    _controlsEnabled = value ? [value boolValue] : YES;
    return;
  }
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveControlsFeature does not own prop '%@'", name];
}

- (void)onPropsCommitted
{
  [self applyControls];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  [self applyControls];
}

- (void)applyControls
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  BCOVPUIPlayerView *playerView = host.playerView;
  if (playerView == nil) {
    return;
  }
  playerView.controlsContainerView.alpha = _controlsEnabled ? 1.0 : 0.0;
  playerView.controlsContainerView.userInteractionEnabled = _controlsEnabled;
  playerView.controlsContainerView.hidden = !_controlsEnabled;
}

@end
