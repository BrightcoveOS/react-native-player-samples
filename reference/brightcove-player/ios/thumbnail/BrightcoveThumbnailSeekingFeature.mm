#import "BrightcoveThumbnailSeekingFeature.h"

@implementation BrightcoveThumbnailSeekingFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  BOOL _enabled;
  BOOL _sourceHasLoaded;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"thumbnailSeekingEnabled"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"thumbnailSeekingEnabled"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveThumbnailSeekingFeature does not own prop '%@'", name];
  }
  if (![value isKindOfClass:NSNumber.class]) {
    [NSException raise:NSInvalidArgumentException
                format:@"thumbnailSeekingEnabled must be a Boolean"];
  }

  BOOL requested = [value boolValue];
  if (requested == _enabled) {
    return;
  }
  if (_sourceHasLoaded) {
    [NSException raise:NSInvalidArgumentException
                format:@"thumbnailSeekingEnabled must be set before the current video is loaded"];
  }

  _enabled = requested;
  id<BCOVPlaybackController> controller = _host.playbackController;
  if (controller != nil) {
    controller.thumbnailSeekingEnabled = _enabled;
  }
}

- (void)configurePlayerViewOptions:(BCOVPUIPlayerViewOptions *)options
{
  (void)options;
  // The core creates the playback controller before asking features to
  // configure the player-view options and before loading the source. Applying
  // the value here is the earliest shared hook for both initial states.
  id<BCOVPlaybackController> controller = _host.playbackController;
  if (controller != nil) {
    controller.thumbnailSeekingEnabled = _enabled;
  }
}

- (void)onSourceReset
{
  _sourceHasLoaded = NO;
}

// The core calls this once the catalog resolves a video for the current
// request, before it is handed to the playback controller — the same point
// Android's DID_SET_VIDEO listener marks sourceHasLoaded at. thumbnailSeekingEnabled
// must be set before this point (see setProp:value: above), matching the
// SDK plugin's own requirement that thumbnail loading is selected before the
// source is set. Returns the video unchanged: this feature only observes the
// timing here, it does not need to rewrite anything on iOS (unlike Android,
// where preview-thumbnail URLs must be forced to HTTPS).
- (nullable BCOVVideo *)willSetVideo:(BCOVVideo *)video
{
  _sourceHasLoaded = YES;
  return video;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  id<BCOVPlaybackController> controller = _host.playbackController;
  if (controller != nil) {
    controller.thumbnailSeekingEnabled = _enabled;
  }
}

- (void)onPlayerTearDown
{
  _sourceHasLoaded = NO;
}

@end
