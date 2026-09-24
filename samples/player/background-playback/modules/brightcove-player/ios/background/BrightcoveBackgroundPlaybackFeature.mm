#import "BrightcoveBackgroundPlaybackFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <MediaPlayer/MediaPlayer.h>

@class BrightcoveBackgroundPlaybackFeature;

@interface BrightcoveBackgroundPlaybackFeature ()
- (BOOL)isEligibleForRemoteCommandOwnership;
- (void)activateRemoteCommandOwnership;
- (void)deactivateRemoteCommandOwnership;
@end

static __weak BrightcoveBackgroundPlaybackFeature *BCOVRemoteCommandOwner;
static NSHashTable<BrightcoveBackgroundPlaybackFeature *> *BCOVRemoteCommandWaiters;

static NSHashTable<BrightcoveBackgroundPlaybackFeature *> *BCOVGetRemoteCommandWaiters(void)
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    BCOVRemoteCommandWaiters = [NSHashTable weakObjectsHashTable];
  });
  return BCOVRemoteCommandWaiters;
}

static void BCOVRequestRemoteCommandOwnership(BrightcoveBackgroundPlaybackFeature *feature)
{
  if (BCOVRemoteCommandOwner == feature) {
    return;
  }
  if (BCOVRemoteCommandOwner == nil) {
    BCOVRemoteCommandOwner = feature;
    [feature activateRemoteCommandOwnership];
    return;
  }
  if (![BCOVRemoteCommandOwner isEligibleForRemoteCommandOwnership]) {
    [BCOVRemoteCommandOwner deactivateRemoteCommandOwnership];
    BCOVRemoteCommandOwner = feature;
    [feature activateRemoteCommandOwnership];
    return;
  }
  [BCOVGetRemoteCommandWaiters() addObject:feature];
}

static void BCOVReleaseRemoteCommandOwnership(BrightcoveBackgroundPlaybackFeature *feature)
{
  NSHashTable *waiters = BCOVGetRemoteCommandWaiters();
  [waiters removeObject:feature];
  if (BCOVRemoteCommandOwner != feature) {
    return;
  }

  [feature deactivateRemoteCommandOwnership];
  BCOVRemoteCommandOwner = nil;
  for (BrightcoveBackgroundPlaybackFeature *candidate in waiters.allObjects) {
    if ([candidate isEligibleForRemoteCommandOwnership]) {
      [waiters removeObject:candidate];
      BCOVRemoteCommandOwner = candidate;
      [candidate activateRemoteCommandOwnership];
      break;
    }
  }
}

static void BCOVPromoteRemoteCommandWaiterIfOwnerPaused(void)
{
  if (BCOVRemoteCommandOwner == nil ||
      [BCOVRemoteCommandOwner isEligibleForRemoteCommandOwnership]) {
    return;
  }

  NSHashTable *waiters = BCOVGetRemoteCommandWaiters();
  for (BrightcoveBackgroundPlaybackFeature *candidate in waiters.allObjects) {
    if ([candidate isEligibleForRemoteCommandOwnership]) {
      [BCOVRemoteCommandOwner deactivateRemoteCommandOwnership];
      BCOVRemoteCommandOwner = candidate;
      [waiters removeObject:candidate];
      [candidate activateRemoteCommandOwnership];
      break;
    }
  }
}

@implementation BrightcoveBackgroundPlaybackFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  id<BCOVPlaybackSession> _session;
  id _timeObserver;
  id _playTarget;
  id _pauseTarget;
  id _seekTarget;
  BOOL _enabled;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"backgroundPlaybackEnabled"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (BOOL)keepsPlaybackAliveInBackground
{
  return _enabled;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"backgroundPlaybackEnabled"] ||
      ![value isKindOfClass:NSNumber.class]) {
    [NSException raise:NSInvalidArgumentException
                format:@"backgroundPlaybackEnabled must be a Boolean"];
  }

  _enabled = [value boolValue];
  if (_enabled) {
    [self configureCurrentSession];
  } else {
    [self disableCurrentSession];
  }
}

- (void)onSourceReset
{
  [self tearDownSessionIntegration];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _session = session;
  [self configureCurrentSession];
}

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  if (!_enabled || _session != session) {
    return;
  }

  NSString *eventType = lifecycleEvent.eventType;
  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPlay]) {
    BCOVRequestRemoteCommandOwnership(self);
    [self updateNowPlayingInfo];
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPause]) {
    [self updateNowPlayingInfo];
    BCOVPromoteRemoteCommandWaiterIfOwnerPaused();
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventReady]) {
    [self updateNowPlayingInfo];
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventEnd] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventTerminate]) {
    [self updateNowPlayingInfo];
    BCOVReleaseRemoteCommandOwnership(self);
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventError] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFail] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFailedToPlayToEndTime]) {
    [self updateNowPlayingInfo];
    BCOVReleaseRemoteCommandOwnership(self);
  }
}

- (void)onPlayerTearDown
{
  [self tearDownSessionIntegration];
}

- (void)onInvalidate
{
  [self tearDownSessionIntegration];
  _host = nil;
}

- (void)configureCurrentSession
{
  if (!_enabled) {
    return;
  }

  id<BCOVPlaybackController> controller = _host.playbackController;
  if (controller != nil) {
    controller.allowsBackgroundAudioPlayback = YES;
  }
  if (_session == nil) {
    return;
  }

  if (_session.player.rate > 0) {
    BCOVRequestRemoteCommandOwnership(self);
  }
}

- (BOOL)isEligibleForRemoteCommandOwnership
{
  return _enabled && _session != nil && _session.player.rate > 0;
}

- (void)activateRemoteCommandOwnership
{
  [self installRemoteCommands];
  [self installTimeObserver];
  [self updateNowPlayingInfo];
}

- (void)deactivateRemoteCommandOwnership
{
  if (_timeObserver != nil && _session.player != nil) {
    [_session.player removeTimeObserver:_timeObserver];
  }
  _timeObserver = nil;
  [self removeRemoteCommands];
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

- (void)disableCurrentSession
{
  BCOVReleaseRemoteCommandOwnership(self);
  id<BCOVPlaybackController> controller = _host.playbackController;
  controller.allowsBackgroundAudioPlayback = NO;
  // The core's own -didMoveToWindow pause path is a no-op while this feature
  // reports keepsPlaybackAliveInBackground=YES, and it will not run again
  // just because backgroundPlaybackEnabled flipped off. If the app is not
  // active right now, playback would otherwise keep running with the
  // background-audio session already torn down above: pause it directly,
  // the same outcome -didMoveToWindow would have produced had this feature
  // not been suppressing it.
  if (![_host isHostActive] && controller != nil) {
    [controller pause];
  }
}

- (void)installRemoteCommands
{
  MPRemoteCommandCenter *center = [MPRemoteCommandCenter sharedCommandCenter];
  __weak __typeof(self) weakSelf = self;
  _playTarget = [center.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(__unused MPRemoteCommandEvent *event) {
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    id<BCOVPlaybackController> controller = strongSelf->_host.playbackController;
    if (controller == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    [controller play];
    return MPRemoteCommandHandlerStatusSuccess;
  }];
  _pauseTarget = [center.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(__unused MPRemoteCommandEvent *event) {
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    id<BCOVPlaybackController> controller = strongSelf->_host.playbackController;
    if (controller == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    [controller pause];
    return MPRemoteCommandHandlerStatusSuccess;
  }];
  _seekTarget = [center.changePlaybackPositionCommand addTargetWithHandler:^(MPRemoteCommandEvent *event) {
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    MPChangePlaybackPositionCommandEvent *positionEvent =
        (MPChangePlaybackPositionCommandEvent *)event;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    id<BCOVPlaybackController> controller = strongSelf->_host.playbackController;
    if (controller == nil || !isfinite(positionEvent.positionTime) || positionEvent.positionTime < 0) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    [controller seekToTime:CMTimeMakeWithSeconds(positionEvent.positionTime, NSEC_PER_SEC)
         completionHandler:nil];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  center.playCommand.enabled = YES;
  center.pauseCommand.enabled = YES;
  center.changePlaybackPositionCommand.enabled = YES;
}

- (void)removeRemoteCommands
{
  MPRemoteCommandCenter *center = [MPRemoteCommandCenter sharedCommandCenter];
  if (_playTarget != nil) {
    [center.playCommand removeTarget:_playTarget];
    _playTarget = nil;
  }
  if (_pauseTarget != nil) {
    [center.pauseCommand removeTarget:_pauseTarget];
    _pauseTarget = nil;
  }
  if (_seekTarget != nil) {
    [center.changePlaybackPositionCommand removeTarget:_seekTarget];
    _seekTarget = nil;
  }
  center.playCommand.enabled = NO;
  center.pauseCommand.enabled = NO;
  center.changePlaybackPositionCommand.enabled = NO;
}

- (void)installTimeObserver
{
  if (_timeObserver != nil || _session.player == nil) {
    return;
  }

  __weak __typeof(self) weakSelf = self;
  _timeObserver = [_session.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                                                  queue:dispatch_get_main_queue()
                                                             usingBlock:^(__unused CMTime time) {
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf != nil && strongSelf->_enabled) {
      [strongSelf updateNowPlayingInfo];
    }
  }];
}

- (void)tearDownSessionIntegration
{
  BCOVReleaseRemoteCommandOwnership(self);
  _session = nil;
}

- (void)updateNowPlayingInfo
{
  if (!_enabled || BCOVRemoteCommandOwner != self || _session == nil || _session.player == nil) {
    return;
  }

  NSDictionary *properties = _session.video.properties;
  NSString *title = properties[BCOVVideo.PropertyKeyName];
  if (title.length == 0) {
    title = properties[BCOVVideo.PropertyKeyId];
  }
  if (title.length == 0) {
    title = @"Brightcove playback";
  }

  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  info[MPMediaItemPropertyTitle] = title;
  info[MPMediaItemPropertyArtist] = @"Brightcove";

  NSTimeInterval duration = CMTimeGetSeconds(_session.player.currentItem.duration);
  NSTimeInterval elapsed = CMTimeGetSeconds(_session.player.currentTime);
  if (isfinite(duration) && duration >= 0) {
    info[MPMediaItemPropertyPlaybackDuration] = @(duration);
  }
  if (isfinite(elapsed) && elapsed >= 0) {
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
  }
  info[MPNowPlayingInfoPropertyPlaybackRate] = @(_session.player.rate);
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

@end
