#import "BrightcoveCastFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <BrightcoveGoogleCast/BrightcoveGoogleCast.h>
#import <GoogleCast/GoogleCast.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static std::string BCOVCastStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

@interface BrightcoveCastFeature () <BCOVGoogleCastManagerDelegate>
- (void)tearDownCastIntegration;
@end

@implementation BrightcoveCastFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;

  BOOL _castEnabled;
  BCOVGoogleCastManager *_castManager;
  GCKUICastButton *_castButton;
  BOOL _observingCastState;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"castEnabled"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"castEnabled"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveCastFeature does not own prop '%@'", name];
  }
  _castEnabled = [value boolValue];
  if (_castEnabled) {
    if (_host.playbackController != nil) {
      [self onSessionReady:nil];
    }
  } else {
    [self tearDownCastIntegration];
  }
}

#pragma mark BCOVGoogleCastManagerDelegate required property

// BCOVGoogleCastManagerDelegate declares this a REQUIRED (not @optional)
// property — BCOVGoogleCastManager reads self.delegate.playbackController
// directly to pause/seek/advance-to-next the LOCAL controller around the cast
// hand-off (session start, session end, and cast-side completion). Without
// this method the class still satisfies the compiler (a missing required
// property is only a warning, not an error), but crashes at runtime the first
// time a real Cast session starts: -[BrightcoveCastFeature
// playbackController]: unrecognized selector. Forward live rather than
// caching, since the core can rebuild the controller (source change,
// tear-down/rebuild) while _castManager itself persists.
- (nullable id<BCOVPlaybackController>)playbackController
{
  return _host.playbackController;
}

// GCKCastContext is only usable once the app has initialized it
// (GCKCastContext.setSharedInstanceWith in the sample's AppDelegate). Casting is
// an optional enhancement, so if it was never set up, do nothing rather than
// throw — reading sharedInstance before setup raises. Guarded everywhere the
// context is touched.
- (nullable GCKCastContext *)castContextIfAvailable
{
  if (![GCKCastContext isSharedInstanceInitialized]) {
    return nil;
  }
  return [GCKCastContext sharedInstance];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  if (!_castEnabled || _host == nil || _host.isInvalidated) {
    return;
  }
  GCKCastContext *castContext = [self castContextIfAvailable];
  if (castContext == nil) {
    // No Cast context (e.g. AppDelegate did not initialize it); report the
    // unknown state so JS does not confuse an unavailable Cast context with
    // an initialized context that has no discoverable receivers.
    [self emitCastState:@"unknown"];
    return;
  }

  // Add the cast manager to the controller so it drives the local<->receiver
  // hand-off for the current video. Added once; guarded by the nil check.
  if (_castManager == nil) {
    _castManager = [[BCOVGoogleCastManager alloc] init];
    _castManager.delegate = self;
    [_host.playbackController addSessionConsumer:_castManager];
  }

  [self addCastButtonIfNeeded];

  if (!_observingCastState) {
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(castStateDidChange:)
                                               name:kGCKCastStateDidChangeNotification
                                             object:castContext];
    _observingCastState = YES;
  }
  // Emit the current state immediately so JS starts from the truth.
  [self emitCastState:[self mapCastState:castContext.castState]];
}

// The BCOVPUIPlayerView has no built-in cast control, so overlay a
// GCKUICastButton on the player's controls container (top-right). The button
// itself opens the system Cast device picker.
- (void)addCastButtonIfNeeded
{
  if (_castButton != nil || _host == nil || _host.isInvalidated) {
    return;
  }
  BCOVPUIPlayerView *playerView = _host.playerView;
  if (playerView == nil) {
    return;
  }
  GCKUICastButton *button =
      [[GCKUICastButton alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
  button.tintColor = UIColor.whiteColor;
  button.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *container = playerView.controlsContainerView ?: playerView;
  [container addSubview:button];
  [NSLayoutConstraint activateConstraints:@[
    [button.topAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor
                                     constant:8],
    [button.trailingAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.trailingAnchor
                                          constant:-8],
    [button.widthAnchor constraintEqualToConstant:32],
    [button.heightAnchor constraintEqualToConstant:32],
  ]];
  _castButton = button;
}

- (void)castStateDidChange:(NSNotification *)notification
{
  GCKCastContext *castContext = [self castContextIfAvailable];
  if (castContext == nil) {
    return;
  }
  [self emitCastState:[self mapCastState:castContext.castState]];
}

- (NSString *)mapCastState:(GCKCastState)state
{
  switch (state) {
    case GCKCastStateNoDevicesAvailable:
      return @"no_devices";
    case GCKCastStateNotConnected:
      return @"not_connected";
    case GCKCastStateConnecting:
      return @"connecting";
    case GCKCastStateConnected:
      return @"connected";
  }
  return @"unknown";
}

- (void)emitCastState:(NSString *)state
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  eventEmitter->onCastStateChanged(BrightcovePlayerViewEventEmitter::OnCastStateChanged{
    .state = BCOVCastStdStringFromNSString(state),
  });
}

#pragma mark BCOVGoogleCastManagerDelegate

// The manager reports local<->remote transitions here. The bridge does not need
// to move any UI (the plugin manages remote playback), but connection state is
// surfaced through onCastStateChanged from the GCKCastContext notification, so
// these are intentionally minimal.
- (void)switchedToRemotePlayback
{
}

- (void)switchedToLocalPlayback:(NSTimeInterval)lastKnownStreamPosition
                      withError:(NSError *)error
{
}

- (void)currentCastedVideoDidComplete
{
}

- (void)castedVideoFailedToPlay
{
}

- (void)suitableSourceNotFound
{
}

#pragma mark Teardown

- (void)tearDownCastIntegration
{
  if (_observingCastState) {
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:kGCKCastStateDidChangeNotification
                                                object:nil];
    _observingCastState = NO;
  }
  [_host.playbackController removeSessionConsumer:_castManager];
  [self removeCastButton];
  _castManager.delegate = nil;
  _castManager = nil;
}

- (void)onPlayerTearDown
{
  // The core rebuilds the playback controller on every source change and then
  // fires onSessionReady again. The cast manager was a session consumer of the
  // OLD controller (already released as part of that controller's teardown), so
  // clear our reference here; otherwise the `_castManager == nil` guard in
  // onSessionReady keeps the stale manager and never adds one to the NEW
  // controller, and casting silently stops working after the first videoId
  // change. (removeSessionConsumer: is a defensive no-op — the core has already
  // niled its playbackController by the time this runs.)
  [self tearDownCastIntegration];
}

- (void)onInvalidate
{
  [self tearDownCastIntegration];
  _host = nil;
}

- (void)removeCastButton
{
  [_castButton removeFromSuperview];
  _castButton = nil;
}

@end
