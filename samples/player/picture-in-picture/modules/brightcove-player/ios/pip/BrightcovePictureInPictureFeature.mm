#import "BrightcovePictureInPictureFeature.h"

#import <AVKit/AVKit.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

using namespace facebook::react;

@implementation BrightcovePictureInPictureFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;

  BOOL _pictureInPictureEnabled;
  BOOL _pictureInPictureActive;
  BOOL _explicitCommandInFlight;
  // Mirrors the core's own _isPlaying, tracked independently here because the
  // core does not expose it: used to gate automatic background PiP entry so a
  // backgrounded, PAUSED player does not slide into a frozen PiP window (see
  // -refreshAutomaticEntry). Starts NO; set true on the content Play event.
  BOOL _isPlaying;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"pictureInPictureEnabled"];
}

- (NSSet<NSString *> *)supportedCommands
{
  return [NSSet setWithObject:@"enterPictureInPicture"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _explicitCommandInFlight = NO;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"pictureInPictureEnabled"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcovePictureInPictureFeature does not own prop '%@'", name];
  }
  BOOL enabled = [value boolValue];
  if (_pictureInPictureEnabled == enabled) {
    return;
  }
  _pictureInPictureEnabled = enabled;

  // pictureInPictureEnabled is initialization-only. showPictureInPictureButton /
  // automaticControlTypeSelection are fixed when the player view is created, so
  // honoring a later toggle would mean rebuilding the controller — which
  // restarts playback (VOD from zero, live jumps to the edge) and loses paused
  // and caption state. Rather than silently restart the video, only the value
  // captured before the player exists takes effect; a later change is recorded
  // (so the state stays truthful) but does not rebuild. If the player has not
  // been built yet, configurePlayerViewOptions will read the new value, so no
  // rebuild is needed there either.
  //
  // (Matches the autoPlay prop, which is likewise applied once at
  // initialization rather than as a live control.)
}

- (BOOL)handleCommand:(NSString *)command
{
  if ([command isEqualToString:@"enterPictureInPicture"]) {
    [self enterPictureInPicture];
    return YES;
  }
  return NO;
}

- (void)enterPictureInPicture
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }

  if (!_pictureInPictureEnabled) {
    [host emitCommandErrorForCommand:@"enterPictureInPicture"
                                code:@"disabled"
                             message:@"Picture-in-Picture is disabled on this player"
                          nativeCode:@"pip_disabled"];
    return;
  }

  if (![AVPictureInPictureController isPictureInPictureSupported]) {
    [host emitCommandErrorForCommand:@"enterPictureInPicture"
                                code:@"unavailable"
                             message:@"Picture-in-Picture is not supported on this device"
                          nativeCode:@"pip_not_supported"];
    return;
  }

  id<BCOVPlaybackController> controller = host.playbackController;
  if (controller == nil) {
    [host emitCommandErrorForCommand:@"enterPictureInPicture"
                                code:@"not_ready"
                             message:@"Cannot enter Picture-in-Picture: playback controller is not ready"
                          nativeCode:@"controller_unavailable"];
    return;
  }

  AVPictureInPictureController *pipController = controller.pictureInPictureController;
  if (pipController == nil) {
    [host emitCommandErrorForCommand:@"enterPictureInPicture"
                                code:@"not_ready"
                             message:@"Cannot enter Picture-in-Picture: pictureInPictureController is not ready"
                          nativeCode:@"pip_controller_nil"];
    return;
  }

  if (pipController.isPictureInPictureActive || _pictureInPictureActive) {
    [host emitCommandErrorForCommand:@"enterPictureInPicture"
                                code:@"invalid_state"
                             message:@"Player is already in Picture-in-Picture mode"
                          nativeCode:@"already_in_pip"];
    return;
  }

  if (!pipController.isPictureInPicturePossible) {
    [host emitCommandErrorForCommand:@"enterPictureInPicture"
                                code:@"invalid_state"
                             message:@"Picture-in-Picture is not possible in the current state"
                          nativeCode:@"pip_not_possible"];
    return;
  }

  _explicitCommandInFlight = YES;
  [pipController startPictureInPicture];
}

- (void)configurePlayerViewOptions:(BCOVPUIPlayerViewOptions *)options
{
  // Let the SDK choose the control layout that includes the PiP button; without
  // this the PiP button is not laid into the default controls. The SDK owns the
  // AVPictureInPictureController and only starts PiP once the system reports it
  // is possible, so the button is the correct, gated entry point.
  options.automaticControlTypeSelection = _pictureInPictureEnabled;
  options.showPictureInPictureButton = _pictureInPictureEnabled;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _isPlaying = NO;
  [self refreshAutomaticEntry];
}

// The SDK forwards every content lifecycle event here (Play, Pause, Ready,
// etc.); only Play/Pause/End/Terminate affect automatic PiP entry.
- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  NSString *eventType = lifecycleEvent.eventType;
  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPlay]) {
    _isPlaying = YES;
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPause] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventEnd] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventTerminate] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFail] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventError] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFailedToPlayToEndTime]) {
    _isPlaying = NO;
  } else {
    return;
  }
  [self refreshAutomaticEntry];
}

// Enter PiP automatically when the app is backgrounded while playing inline,
// matching the Android auto-enter behavior — but only while actually playing:
// canStartPictureInPictureAutomaticallyFromInline is not itself play-state
// aware, so leaving it armed while paused would let the OS slide a
// backgrounded, paused player into a frozen PiP window (this is exactly what
// Android's refreshEntryEnabled/setAutoEnterEnabled(isPlaying) exists to
// prevent). Re-evaluated on every Ready/Play/Pause/End/Terminate so the flag
// always reflects the current play state, not just the value at session-ready.
// Available on iOS 14.2+.
- (void)refreshAutomaticEntry
{
  if (!_pictureInPictureEnabled) {
    return;
  }
  // pictureInPictureController is a weak, nullable property: it may not exist
  // yet this early (e.g. right at session-ready). Setting the flag on a nil
  // controller is a silent no-op (auto-enter would never arm with no signal),
  // so guard for nil and log if it is unexpectedly absent rather than quietly
  // doing nothing.
  AVPictureInPictureController *pipController = _host.playbackController.pictureInPictureController;
  if (@available(iOS 14.2, *)) {
    if (pipController != nil) {
      pipController.canStartPictureInPictureAutomaticallyFromInline = _isPlaying;
    } else if (_isPlaying) {
      NSLog(@"[BrightcovePictureInPictureFeature] pictureInPictureController is "
            @"nil while playing; automatic background PiP entry not armed.");
    }
  }
}

- (void)pictureInPictureDidStart
{
  _explicitCommandInFlight = NO;
  [self setPictureInPictureActive:YES];
}

- (void)pictureInPictureDidStop
{
  _explicitCommandInFlight = NO;
  [self setPictureInPictureActive:NO];
}

- (void)pictureInPictureFailedToStartWithError:(NSError *)error
{
  // PiP failing to start is not a playback failure — the source keeps playing
  // inline. This is exactly the reels-feed case customers hit: PiP requested
  // while the player is not in a PiP-ready state.
  [self setPictureInPictureActive:NO];
  id<BrightcovePlayerFeatureHost> host = _host;
  BOOL reportCommandFailure = _explicitCommandInFlight;
  _explicitCommandInFlight = NO;
  if (reportCommandFailure && host != nil && !host.isInvalidated) {
    NSString *nativeCode = error != nil
        ? [NSString stringWithFormat:@"%@:%ld", error.domain, (long)error.code]
        : @"pip_start_failed";
    [host emitCommandErrorForCommand:@"enterPictureInPicture"
                                code:@"failed"
                             message:error.localizedDescription ?: @"Picture-in-Picture failed to start"
                          nativeCode:nativeCode];
  }
}

// Deterministic teardown. When the core releases the player/controller (source
// change or view invalidation) while PiP is active, the disappearing controller
// is not guaranteed to deliver pictureInPictureDidStop, so JS could be left
// believing PiP is still active — and the stale _pictureInPictureActive guard
// would then suppress a legitimate later didStart. Clear and emit active:false
// here so the state is always truthful across a teardown, regardless of whether
// the SDK delivers its own stop callback.
- (void)onPlayerTearDown
{
  _isPlaying = NO;
  _explicitCommandInFlight = NO;
  [self setPictureInPictureActive:NO];
}

- (void)onInvalidate
{
  _isPlaying = NO;
  _explicitCommandInFlight = NO;
  [self setPictureInPictureActive:NO];
}

- (void)setPictureInPictureActive:(BOOL)active
{
  if (_pictureInPictureActive == active) {
    return;
  }
  _pictureInPictureActive = active;

  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onPictureInPictureModeChanged(
      BrightcovePlayerViewEventEmitter::OnPictureInPictureModeChanged{
        .active = static_cast<bool>(active),
      });
  }
}

@end
