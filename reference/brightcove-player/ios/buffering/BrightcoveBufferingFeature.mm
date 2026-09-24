#import "BrightcoveBufferingFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

@implementation BrightcoveBufferingFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  __weak id<BCOVPlaybackSession> _session;
  BOOL _sessionReady;
  BOOL _hasPlayed;
  BOOL _playRequestedBeforeReady;
  BOOL _rebufferActive;
  BOOL _sourceFailed;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet set];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _sourceFailed = NO;
}

- (void)setProp:(NSString *)name value:(id)value
{
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveBufferingFeature does not own prop '%@'", name];
}

- (void)onSourceReset
{
  _sourceFailed = NO;
  [self finishRebuffer];
  _session = nil;
  _sessionReady = NO;
  _hasPlayed = NO;
  _playRequestedBeforeReady = NO;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _session = session;
  _sessionReady = YES;
}

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  if (_sourceFailed || (_session != nil && _session != session)) {
    return;
  }

  NSString *eventType = lifecycleEvent.eventType;
  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventReady]) {
    _session = session;
    _sessionReady = YES;
    if (_playRequestedBeforeReady) {
      _hasPlayed = YES;
      _playRequestedBeforeReady = NO;
    }
    return;
  }

  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPlay]) {
    if (_sessionReady) {
      _hasPlayed = YES;
    } else {
      _playRequestedBeforeReady = YES;
    }
    return;
  }

  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPlaybackStalled]) {
    // Do not use PlaybackBufferEmpty/LikelyToKeepUp here: the SDK documents
    // those events for initial loading and seeks as well. PlaybackStalled and
    // PlaybackRecovered are the SDK's normal post-start stall pair.
    if (_sessionReady && _hasPlayed && !_rebufferActive) {
      [self startRebuffer];
    }
    return;
  }

  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPlaybackRecovered]) {
    [self finishRebuffer];
    return;
  }

  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPause] ||
      [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventEnd] ||
      [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventTerminate] ||
      [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFail] ||
      [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventError] ||
      [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFailedToPlayToEndTime]) {
    _hasPlayed = NO;
    _playRequestedBeforeReady = NO;
    [self finishRebuffer];
  }
}

- (void)onPlaybackError
{
  [self finishRebuffer];
  _sourceFailed = YES;
}

- (void)onPlayerTearDown
{
  [self finishRebuffer];
  _session = nil;
  _sessionReady = NO;
  _hasPlayed = NO;
  _playRequestedBeforeReady = NO;
}

- (void)onInvalidate
{
  [self onPlayerTearDown];
  _host = nil;
}

- (void)startRebuffer
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }

  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    [NSException raise:NSInternalInconsistencyException
                format:@"BrightcoveBufferingFeature received a stall before its Fabric event emitter was available"];
  }

  _rebufferActive = YES;
  eventEmitter->onRebufferStart(BrightcovePlayerViewEventEmitter::OnRebufferStart{});
}

- (void)finishRebuffer
{
  if (!_rebufferActive) {
    return;
  }

  _rebufferActive = NO;
  if (_host == nil || _host.isInvalidated) {
    return;
  }

  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    [NSException raise:NSInternalInconsistencyException
                format:@"BrightcoveBufferingFeature could not close a stall because its Fabric event emitter was unavailable"];
  }

  eventEmitter->onRebufferEnd(BrightcovePlayerViewEventEmitter::OnRebufferEnd{});
}

@end
