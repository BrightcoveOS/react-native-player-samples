#import "BrightcovePlaybackEventsFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <QuartzCore/QuartzCore.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

// ~4 progress updates per second: enough for a smooth progress bar, bounded so
// the JS thread is not flooded. Matches the Android feature's cadence.
static const NSTimeInterval kProgressIntervalSeconds = 0.25;

@implementation BrightcovePlaybackEventsFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  // The current session, captured on ready, read during progress to resolve the
  // item duration. Weak: the controller owns the session, and it is released on
  // source change/teardown — we must not extend its life.
  __weak id<BCOVPlaybackSession> _session;
  // didProgressTo: fires many times per second; forwarding every one across the
  // RN bridge floods the JS thread. Throttle onProgress to one emit per
  // kProgressIntervalSeconds. Reset per source in onSourceReset.
  NSTimeInterval _lastProgressEmit;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet set];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  // Event-only feature: it owns no props, so the core never routes one here.
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcovePlaybackEventsFeature does not own prop '%@'", name];
}

- (void)onSourceReset
{
  _session = nil;
  _lastProgressEmit = 0;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _session = session;
}

// Play / pause / end arrive on the lifecycle channel — the same events the core
// uses to track its own playback state. Report them to JS.
- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  auto eventEmitter = [self emitter];
  if (!eventEmitter) {
    return;
  }
  NSString *eventType = lifecycleEvent.eventType;
  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPlay]) {
    eventEmitter->onPlay(BrightcovePlayerViewEventEmitter::OnPlay{});
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPause]) {
    eventEmitter->onPause(BrightcovePlayerViewEventEmitter::OnPause{});
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventEnd]) {
    eventEmitter->onEnded(BrightcovePlayerViewEventEmitter::OnEnded{});
  }
}

- (void)onDidProgressTo:(NSTimeInterval)progress
{
  // Throttle to ~4 emits/sec (see the Android feature's matching cadence) so a
  // high-frequency progress callback does not flood the JS thread. Checked
  // before resolving the emitter so a throttled tick does no other work.
  NSTimeInterval now = CACurrentMediaTime();
  if (now - _lastProgressEmit < kProgressIntervalSeconds) {
    return;
  }

  auto eventEmitter = [self emitter];
  if (!eventEmitter) {
    return;
  }
  _lastProgressEmit = now;

  // progress is the current time in seconds. A negative/NaN progress (seen for
  // an unprepared item) is reported as 0 rather than a nonsense value.
  double currentTime = (progress > 0 && !isnan(progress)) ? progress : 0.0;
  eventEmitter->onProgress(BrightcovePlayerViewEventEmitter::OnProgress{
    .currentTime = currentTime,
    .duration = [self currentDurationSeconds],
  });
}

// Resolve the item duration in seconds from the captured session's player. A
// live stream has an indefinite duration (CMTIME is indefinite/NaN); report 0
// so JS never sees a nonsense total, matching the Android contract.
- (double)currentDurationSeconds
{
  AVPlayerItem *item = _session.player.currentItem;
  if (item == nil) {
    return 0.0;
  }
  CMTime duration = item.duration;
  if (!CMTIME_IS_NUMERIC(duration)) {
    return 0.0;
  }
  double seconds = CMTimeGetSeconds(duration);
  return (seconds > 0 && !isnan(seconds)) ? seconds : 0.0;
}

- (std::shared_ptr<const BrightcovePlayerViewEventEmitter>)emitter
{
  // A late lifecycle/progress callback can fire during teardown; ignore anything
  // after the view was invalidated so it cannot emit onto a stale emitter.
  if (_host == nil || _host.isInvalidated) {
    return nullptr;
  }
  return [_host typedEventEmitter];
}

@end
