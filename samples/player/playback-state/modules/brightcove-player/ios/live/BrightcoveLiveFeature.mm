#import "BrightcoveLiveFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <CoreMedia/CoreMedia.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static inline BOOL BCOVIsValidDVRSeekableRange(CMTimeRange range)
{
  if (!CMTIMERANGE_IS_VALID(range) || !CMTIME_IS_NUMERIC(range.start) ||
      !CMTIME_IS_NUMERIC(range.duration)) {
    return NO;
  }
  double start = CMTimeGetSeconds(range.start);
  double end = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
  return isfinite(start) && isfinite(end) && start >= 0.0 && end > start &&
      end > 0.0;
}

@implementation BrightcoveLiveFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  __weak id<BCOVPlaybackSession> _session;
  BOOL _sessionReady;
  BOOL _classificationEmitted;
  BOOL _layoutApplied;
  BOOL _isLive;
  BOOL _hasDvr;
  BOOL _videoTypeDetermined;
  BOOL _pendingSeekableRangesReset;
  NSArray *_pendingSeekableRanges;
  NSString *_lastRangeKey;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet set];
}

- (NSSet<NSString *> *)supportedCommands
{
  return [NSSet setWithObject:@"seekToLiveEdge"];
}

- (BOOL)handleCommand:(NSString *)command
{
  if ([command isEqualToString:@"seekToLiveEdge"]) {
    [self performSeekToLiveEdge];
    return YES;
  }
  return NO;
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  // Event-only feature: it owns no props, so the core never routes one here.
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveLiveFeature does not own prop '%@'", name];
}

- (void)onSourceReset
{
  _session = nil;
  _sessionReady = NO;
  _videoTypeDetermined = NO;
  _isLive = NO;
  _hasDvr = NO;
  _classificationEmitted = NO;
  _layoutApplied = NO;
  _pendingSeekableRangesReset = NO;
  _pendingSeekableRanges = nil;
  _lastRangeKey = nil;

  if ([self emitSeekableRanges:@[] liveEdge:0.0]) {
    _lastRangeKey = @"empty";
  } else {
    // Keep the authoritative empty reset until Fabric provides an emitter.
    // Otherwise JavaScript can retain the previous source's DVR window.
    _pendingSeekableRangesReset = YES;
  }
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  _session = session;
  _sessionReady = YES;
  [self emitLiveStatusIfPossible];
  if (_hasDvr && _pendingSeekableRanges == nil) {
    NSArray *ranges = session.player.currentItem.seekableTimeRanges;
    if (ranges.count > 0) {
      _pendingSeekableRanges = [ranges copy];
    }
  }
  [self flushPendingSeekableRanges];
}

- (void)onViewAttached
{
  [self emitLiveStatusIfPossible];
  [self flushPendingSeekableRanges];
}

- (void)onEventEmitterReady
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  [self emitLiveStatusIfPossible];
  [self flushPendingSeekableRanges];
}

- (void)emitLiveStatusIfPossible
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  if (!_sessionReady || !_videoTypeDetermined || _classificationEmitted) {
    return;
  }
  if ([self emitLiveStatus:_isLive hasDvr:_hasDvr]) {
    _classificationEmitted = YES;
  }
}

- (void)flushPendingSeekableRanges
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  if (_pendingSeekableRangesReset) {
    if ([self clearSeekableRanges]) {
      _pendingSeekableRangesReset = NO;
    } else {
      return;
    }
  }
  if (_pendingSeekableRanges == nil) {
    return;
  }
  if (_pendingSeekableRanges.count == 0) {
    if ([self clearSeekableRanges]) {
      _pendingSeekableRanges = nil;
    }
    return;
  }
  if (!_sessionReady) {
    return;
  }
  if (!_videoTypeDetermined) {
    return;
  }
  if (!_hasDvr) {
    if ([self clearSeekableRanges]) {
      _pendingSeekableRanges = nil;
    }
    return;
  }
  if ([self emitSeekableRangesFromValues:_pendingSeekableRanges]) {
    _pendingSeekableRanges = nil;
  }
}

// The SDK determined the video type. This is the authoritative live/DVR signal
// (the same value the native DVRLive sample keys its control layout off), so
// report it to JS and switch the controls to the live/DVR layout for a live
// stream. For on-demand content, leave the default (VOD) layout in place.
- (void)onDeterminedVideoType:(BCOVVideoType)videoType forVideo:(BCOVVideo *)video
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }

  BOOL isLive = videoType == BCOVVideoTypeLive || videoType == BCOVVideoTypeLiveDVR;
  BOOL hasDvr = videoType == BCOVVideoTypeLiveDVR;
  _isLive = isLive;
  _hasDvr = hasDvr;
  _videoTypeDetermined = YES;

  [self applyControlLayoutForLive:isLive hasDvr:hasDvr];
  [self emitLiveStatusIfPossible];
  if (hasDvr && _pendingSeekableRanges == nil && _session != nil) {
    NSArray *ranges = _session.player.currentItem.seekableTimeRanges;
    if (ranges.count > 0) {
      _pendingSeekableRanges = [ranges copy];
    }
  }
  [self flushPendingSeekableRanges];
}

- (void)onSeekableRangesChanged:(NSArray *)seekableRanges
                          session:(id<BCOVPlaybackSession>)session
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  if (_session != nil && session != _session) {
    return;
  }
  _session = session;
  _pendingSeekableRanges = [seekableRanges copy];
  [self flushPendingSeekableRanges];
}

- (void)performSeekToLiveEdge
{
  if (_host == nil || _host.isInvalidated || !_sessionReady || !_videoTypeDetermined || _session == nil) {
    // Pre-session/unclassified sources cannot be live-DVR yet.
    [self emitSeekToLiveEdgeUnavailable:@"not_ready"];
    return;
  }
  if (!_hasDvr) {
    // The source IS classified, but not as live-with-DVR — VOD or plain
    // live. Same typed code the Android feature reports for this case.
    [self emitSeekToLiveEdgeUnavailable:@"not_live_dvr"];
    return;
  }
  NSArray *ranges = _session.player.currentItem.seekableTimeRanges;
  CMTime liveEdge = kCMTimeInvalid;
  BOOL hasValidRange = NO;
  for (NSValue *value in ranges) {
    CMTimeRange range = value.CMTimeRangeValue;
    if (BCOVIsValidDVRSeekableRange(range)) {
      hasValidRange = YES;
      CMTime rangeEnd = CMTimeRangeGetEnd(range);
      if (!CMTIME_IS_NUMERIC(liveEdge) || CMTimeCompare(rangeEnd, liveEdge) > 0) {
        liveEdge = rangeEnd;
      }
    }
  }
  if (hasValidRange && CMTIME_IS_NUMERIC(liveEdge) && CMTimeGetSeconds(liveEdge) > 0.0) {
    [_host.playbackController seekToTime:liveEdge completionHandler:nil];
  } else {
    // Live with DVR, but the seekable window is not populated/valid yet.
    // Distinct from not_live_dvr so a caller can tell "wait for ranges"
    // from "this source can never seek to the edge" — the same split the
    // Android feature reports.
    [self emitSeekToLiveEdgeUnavailable:@"no_dvr_range_yet"];
  }
}

// The seekToLiveEdge command contract: every rejection is reported through
// onPlayerCommandError, never dropped — a caller must be able to distinguish
// "not a live-DVR source" (not_ready/not_live_dvr) from "live-DVR but the
// window is not available yet" (no_dvr_range_yet) from success. The two-code
// classification table matches the Android feature's SeekToLiveEdgeOutcome.
- (void)emitSeekToLiveEdgeUnavailable:(NSString *)nativeCode
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) return;
  NSString *message;
  if ([nativeCode isEqualToString:@"no_dvr_range_yet"]) {
    message = @"Cannot seek to the live edge: the DVR seekable range is not available yet";
  } else if ([nativeCode isEqualToString:@"not_live_dvr"]) {
    message = @"Cannot seek to the live edge: the source is not a live stream with DVR";
  } else {
    message = @"Cannot seek to the live edge: the source is not ready";
  }
  [host emitCommandErrorForCommand:@"seekToLiveEdge"
                               code:@"invalid_state"
                            message:message
                         nativeCode:nativeCode];
}

- (BOOL)emitSeekableRangesFromValues:(NSArray *)seekableRanges
{
  NSMutableArray<NSDictionary *> *ranges = [NSMutableArray array];
  double liveEdge = 0.0;
  for (NSValue *value in seekableRanges) {
    CMTimeRange range = value.CMTimeRangeValue;
    if (!BCOVIsValidDVRSeekableRange(range)) {
      continue;
    }
    double start = CMTimeGetSeconds(range.start);
    double end = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
    [ranges addObject:@{
      @"startTime": @(start),
      @"endTime": @(end),
    }];
    liveEdge = MAX(liveEdge, end);
  }
  if (ranges.count == 0) {
    return [self clearSeekableRanges];
  }
  NSMutableString *key = [NSMutableString string];
  for (NSDictionary *range in ranges) {
    [key appendFormat:@"%.3f:%.3f;",
                      [range[@"startTime"] doubleValue],
                      [range[@"endTime"] doubleValue]];
  }
  [key appendFormat:@"%.3f", liveEdge];
  if ([key isEqualToString:_lastRangeKey]) {
    return YES;
  }
  if ([self emitSeekableRanges:ranges liveEdge:liveEdge]) {
    _lastRangeKey = key;
    return YES;
  }
  return NO;
}

- (BOOL)clearSeekableRanges
{
  if ([@"empty" isEqualToString:_lastRangeKey]) {
    return YES;
  }
  if ([self emitSeekableRanges:@[] liveEdge:0.0]) {
    _lastRangeKey = @"empty";
    return YES;
  }
  return NO;
}

- (BOOL)emitSeekableRanges:(NSArray<NSDictionary *> *)ranges liveEdge:(double)liveEdge
{
  auto eventEmitter = [self emitter];
  if (!eventEmitter) {
    return NO;
  }
  std::vector<BrightcovePlayerViewEventEmitter::OnSeekableRangesChangedRanges> nativeRanges;
  for (NSDictionary *range in ranges) {
    nativeRanges.push_back({
      .startTime = [range[@"startTime"] doubleValue],
      .endTime = [range[@"endTime"] doubleValue],
    });
  }
  eventEmitter->onSeekableRangesChanged(
      BrightcovePlayerViewEventEmitter::OnSeekableRangesChanged{
        .ranges = nativeRanges,
        .liveEdge = liveEdge,
      });
  return YES;
}

- (void)applyControlLayoutForLive:(BOOL)isLive hasDvr:(BOOL)hasDvr
{
  if (!isLive || _layoutApplied) {
    return;
  }
  BCOVPUIBasicControlView *controlsView = _host.playerView.controlsView;
  if (controlsView == nil) {
    return;
  }
  controlsView.layout = hasDvr
      ? [BCOVPUIControlLayout basicLiveDVRControlLayout]
      : [BCOVPUIControlLayout basicLiveControlLayout];
  _layoutApplied = YES;
}

- (BOOL)emitLiveStatus:(BOOL)isLive hasDvr:(BOOL)hasDvr
{
  auto eventEmitter = [self emitter];
  if (!eventEmitter) {
    return NO;
  }
  eventEmitter->onLiveStatus(BrightcovePlayerViewEventEmitter::OnLiveStatus{
    .isLive = static_cast<bool>(isLive),
    .hasDvr = static_cast<bool>(hasDvr),
  });
  return YES;
}

- (void)onPlayerTearDown
{
  _session = nil;
  _sessionReady = NO;
  _videoTypeDetermined = NO;
  _isLive = NO;
  _hasDvr = NO;
  _classificationEmitted = NO;
  _layoutApplied = NO;
  _pendingSeekableRanges = nil;
  _lastRangeKey = nil;
}

- (void)onInvalidate
{
  _host = nil;
  _session = nil;
  _sessionReady = NO;
  _videoTypeDetermined = NO;
  _isLive = NO;
  _hasDvr = NO;
  _classificationEmitted = NO;
  _layoutApplied = NO;
  _pendingSeekableRanges = nil;
  _lastRangeKey = nil;
}

- (std::shared_ptr<const BrightcovePlayerViewEventEmitter>)emitter
{
  if (_host == nil || _host.isInvalidated) {
    return nullptr;
  }
  return [_host typedEventEmitter];
}

@end
