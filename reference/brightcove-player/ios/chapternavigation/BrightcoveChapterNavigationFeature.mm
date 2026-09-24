#import "BrightcoveChapterNavigationFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <limits.h>
#import <math.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

@implementation BrightcoveChapterNavigationFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  __weak id<BCOVPlaybackSession> _session;
  double _chapterSeekTime;
  NSInteger _chapterSeekRequestId;
  NSInteger _lastHandledRequestId;
  NSInteger _pendingRequestId;
  NSUInteger _propSequence;
  BOOL _sessionReady;
  BOOL _sourceFailed;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:@"chapterSeekTime", @"chapterSeekRequestId", nil];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _chapterSeekTime = -1;
  _chapterSeekRequestId = 0;
  _lastHandledRequestId = 0;
  _pendingRequestId = 0;
  _propSequence = 0;
  _sessionReady = NO;
  _sourceFailed = NO;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"chapterSeekTime"] &&
      ![name isEqualToString:@"chapterSeekRequestId"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveChapterNavigationFeature does not own prop '%@'", name];
  }
  if (![value isKindOfClass:NSNumber.class]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveChapterNavigationFeature requires a number for '%@'", name];
  }

  if ([name isEqualToString:@"chapterSeekTime"]) {
    double requested = [(NSNumber *)value doubleValue];
    if (requested != -1.0 && (!isfinite(requested) || requested < 0 ||
                               requested > (double)LLONG_MAX / 1000000000.0)) {
      [NSException raise:NSInvalidArgumentException
                  format:@"BrightcoveChapterNavigationFeature requires -1 or a finite non-negative time"];
    }
    _chapterSeekTime = requested;
  } else {
    NSInteger requestId = [(NSNumber *)value integerValue];
    if (requestId < 0) {
      [NSException raise:NSInvalidArgumentException
                  format:@"BrightcoveChapterNavigationFeature requires a non-negative request id"];
    }
    _chapterSeekRequestId = requestId;
  }

  NSUInteger sequence = ++_propSequence;
  __weak BrightcoveChapterNavigationFeature *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    BrightcoveChapterNavigationFeature *strongSelf = weakSelf;
    if (strongSelf == nil || sequence != strongSelf->_propSequence) {
      return;
    }
    [strongSelf performPendingSeek];
  });
}

- (void)onSourceReset
{
  _propSequence += 1;
  _lastHandledRequestId = _chapterSeekRequestId;
  _pendingRequestId = 0;
  _session = nil;
  _sessionReady = NO;
  _sourceFailed = NO;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  if (_sourceFailed) {
    return;
  }
  _session = session;
  _sessionReady = YES;
  [self performPendingSeek];
}

- (void)onPlaybackError
{
  _sourceFailed = YES;
  _pendingRequestId = 0;
}

- (void)onPlayerTearDown
{
  _propSequence += 1;
  _session = nil;
  _sessionReady = NO;
  _pendingRequestId = 0;
}

- (void)onInvalidate
{
  [self onPlayerTearDown];
  _host = nil;
}

- (void)performPendingSeek
{
  if (_sourceFailed || !_sessionReady || _session == nil || _chapterSeekTime < 0 ||
      _chapterSeekRequestId == 0 || _chapterSeekRequestId == _lastHandledRequestId ||
      _pendingRequestId != 0) {
    return;
  }

  NSInteger requestId = _chapterSeekRequestId;
  double requestedTime = _chapterSeekTime;
  if (![self isSeekTargetValid:requestedTime]) {
    _lastHandledRequestId = requestId;
    [self emitSeekResult:requestId positionSeconds:requestedTime completed:NO];
    return;
  }

  id<BCOVPlaybackController> controller = _host.playbackController;
  if (controller == nil) {
    return;
  }

  id<BCOVPlaybackSession> session = _session;
  _lastHandledRequestId = requestId;
  _pendingRequestId = requestId;
  CMTime target = CMTimeMakeWithSeconds(requestedTime, NSEC_PER_SEC);
  __weak BrightcoveChapterNavigationFeature *weakSelf = self;
  [controller seekToTime:target completionHandler:^(BOOL finished) {
    dispatch_async(dispatch_get_main_queue(), ^{
      BrightcoveChapterNavigationFeature *strongSelf = weakSelf;
      if (strongSelf == nil || strongSelf->_session != session ||
          strongSelf->_pendingRequestId != requestId) {
        return;
      }
      strongSelf->_pendingRequestId = 0;
      double actualTime = requestedTime;
      CMTime currentTime = session.player.currentTime;
      if (CMTIME_IS_NUMERIC(currentTime)) {
        double seconds = CMTimeGetSeconds(currentTime);
        if (isfinite(seconds) && seconds >= 0) {
          actualTime = seconds;
        }
      }
      [strongSelf emitSeekResult:requestId positionSeconds:actualTime completed:finished];
      [strongSelf performPendingSeek];
    });
  }];
}

- (BOOL)isSeekTargetValid:(double)seconds
{
  AVPlayerItem *item = _session.player.currentItem;
  if (item == nil || !CMTIME_IS_NUMERIC(item.duration)) {
    return YES;
  }

  double durationSeconds = CMTimeGetSeconds(item.duration);
  if (!isfinite(durationSeconds) || durationSeconds <= 0) {
    return YES;
  }
  return seconds <= durationSeconds + 0.5;
}

- (void)emitSeekResult:(NSInteger)requestId
       positionSeconds:(double)positionSeconds
             completed:(BOOL)completed
{
  if (_host == nil || _host.isInvalidated) {
    return;
  }
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    [NSException raise:NSInternalInconsistencyException
                format:@"BrightcoveChapterNavigationFeature received a seek result before its Fabric emitter was available"];
  }
  eventEmitter->onChapterSeekCompleted(
    BrightcovePlayerViewEventEmitter::OnChapterSeekCompleted{
      .requestId = static_cast<int32_t>(requestId),
      .positionSeconds = positionSeconds,
      .completed = completed,
    });
}

@end
