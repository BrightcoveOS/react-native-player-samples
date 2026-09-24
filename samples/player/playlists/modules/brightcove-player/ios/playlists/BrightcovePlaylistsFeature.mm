#import "BrightcovePlaylistsFeature.h"

#import <CoreMedia/CoreMedia.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

#import "../core/BCOVErrorCategory.h"
#import "BCOVQueueCommandOutcome.h"

using namespace facebook::react;

typedef NS_ENUM(NSInteger, BrightcovePlayerRepeatMode) {
  BrightcovePlayerRepeatModeOff = 0,
  BrightcovePlayerRepeatModeOne = 1,
  BrightcovePlayerRepeatModeAll = 2,
};

/**
 * Loads a Video Cloud queue from the `videoIds` prop instead of a single
 * video. Each ID is resolved from the catalog in order and, once resolved,
 * added to the native SDK's own queue (playbackController setVideos:), which
 * owns normal end-of-item advancement (autoAdvance, set by the core) — this
 * feature layers repeat/shuffle semantics on top rather than building a
 * playback state machine of its own.
 *
 * `videoIds` is core-routed through -setFeatureProp:value:isDefault: exactly
 * like `offlineSourceId`: a non-empty array both selects this feature as the
 * current source's loader (claimsSourceLoading) and supplies the queue
 * contents (setProp("videoIds", ...)). repeatMode and shuffle are ordinary
 * feature-owned props.
 */
@implementation BrightcovePlaylistsFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  BCOVPlaybackService *_playbackService;
  NSUInteger _activeRequestGeneration;

  NSArray<NSString *> *_videoIds;
  NSMutableArray<BCOVVideo *> *_resolvedVideos;
  NSMutableArray<NSNumber *> *_resolvedOriginalIndices;
  NSMutableArray<NSString *> *_failedItemCodes;
  NSMutableArray<NSNumber *> *_playbackOrder;
  NSInteger _currentOrderIndex;
  NSInteger _nativeQueueTailIndex;

  BrightcovePlayerRepeatMode _repeatMode;
  BOOL _shuffle;
  BOOL _shuffleForCurrentLoad;

  BOOL _firstItemEmittedDirectly;
  BOOL _resolutionInProgress;
  BOOL _queueCompletedEmitted;
  BOOL _pendingAdvance;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:@"videoIds", @"repeatMode", @"shuffle", nil];
}

- (NSSet<NSString *> *)supportedCommands
{
  return [NSSet setWithObjects:@"next", @"previous", nil];
}

- (BOOL)handleCommand:(NSString *)command
{
  if ([command isEqualToString:@"next"]) {
    if (![self hasCurrentQueue]) {
      [self emitQueueNotLoadedForCommand:command];
      return YES;
    }
    // Decide the outcome first (the same table Android's handleCommand
    // applies): at-end is the typed rejection from the imperative path only —
    // advanceQueue itself stays silent because it is also the internal retry
    // for a request made earlier, which must not report an error when
    // resolution ends with nothing further to move to.
    if (BCOVNextQueueCommandOutcome(
            _playbackOrder.count,
            _currentOrderIndex,
            _resolutionInProgress,
            _repeatMode == BrightcovePlayerRepeatModeAll) == BCOVQueueCommandOutcomeAtEnd) {
      [self emitQueueAtEndForNextCommand];
      return YES;
    }
    return [self advanceQueue];
  }
  if ([command isEqualToString:@"previous"]) {
    if (![self hasCurrentQueue]) {
      [self emitQueueNotLoadedForCommand:command];
      return YES;
    }
    return [self previousQueueItem];
  }
  return NO;
}

// A queue is loaded for the current request when videoIds is set and a source
// request is active and still current. Anything else is the typed no-queue
// rejection (queue_not_loaded) — the same contract the Android feature
// reports, rather than a generic precondition failure.
- (BOOL)hasCurrentQueue
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return NO;
  }
  if (_videoIds.count == 0 || _activeRequestGeneration == 0) {
    return NO;
  }
  return [host isCurrentRequest:_activeRequestGeneration];
}

// The typed messages live in BCOVQueueCommandOutcome so iOS and Android (and
// the web implementation) stay verbatim-identical.
- (void)emitQueueNotLoadedForCommand:(NSString *)command
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil) {
    return;
  }
  NSString *message = [command isEqualToString:@"next"]
      ? BCOVNextQueueNotLoadedMessage()
      : BCOVPreviousQueueNotLoadedMessage();
  [host emitCommandErrorForCommand:command
                              code:@"invalid_state"
                           message:message
                        nativeCode:@"queue_not_loaded"];
}

- (void)emitQueueAtEndForNextCommand
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil) {
    return;
  }
  [host emitCommandErrorForCommand:@"next"
                              code:@"invalid_state"
                           message:BCOVQueueAtEndMessage()
                        nativeCode:@"queue_at_end"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _videoIds = @[];
}

- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"videoIds"]) {
    NSArray<NSString *> *newValue = [value isKindOfClass:NSArray.class] ? (NSArray<NSString *> *)value : @[];
    if (![_videoIds isEqualToArray:newValue]) {
      _videoIds = [newValue copy];
      [_host requestSourceReload];
    }
  } else if ([name isEqualToString:@"repeatMode"]) {
    if (![value isKindOfClass:NSString.class]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"BrightcovePlaylistsFeature requires a String for '%@'", name];
    }
    [self setRepeatModeString:(NSString *)value];
  } else if ([name isEqualToString:@"shuffle"]) {
    if (![value isKindOfClass:NSNumber.class]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"BrightcovePlaylistsFeature requires a Boolean for '%@'", name];
    }
    [self setShuffleEnabled:((NSNumber *)value).boolValue];
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcovePlaylistsFeature does not own prop '%@'", name];
  }
}

- (void)setRepeatModeString:(NSString *)modeStr
{
  BrightcovePlayerRepeatMode newMode;
  if ([modeStr isEqualToString:@"off"] || modeStr.length == 0) {
    newMode = BrightcovePlayerRepeatModeOff;
  } else if ([modeStr isEqualToString:@"one"]) {
    newMode = BrightcovePlayerRepeatModeOne;
  } else if ([modeStr isEqualToString:@"all"]) {
    newMode = BrightcovePlayerRepeatModeAll;
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"Invalid repeatMode '%@', expected 'off', 'one', or 'all'", modeStr];
    return;
  }
  _repeatMode = newMode;
}

- (void)setShuffleEnabled:(BOOL)shuffle
{
  if (_shuffle == shuffle) {
    return;
  }
  _shuffle = shuffle;
  if (_resolvedVideos.count <= 1 || _resolutionInProgress) {
    return;
  }

  NSUInteger currentResolvedIdx = (_currentOrderIndex >= 0 && _currentOrderIndex < (NSInteger)_playbackOrder.count)
      ? _playbackOrder[_currentOrderIndex].unsignedIntegerValue
      : 0;

  if (_shuffle) {
    NSMutableArray<NSNumber *> *otherIndices = [NSMutableArray new];
    for (NSUInteger i = 0; i < _resolvedVideos.count; i++) {
      if (i != currentResolvedIdx) {
        [otherIndices addObject:@(i)];
      }
    }
    for (NSInteger i = (NSInteger)otherIndices.count - 1; i > 0; i--) {
      NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
      [otherIndices exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    NSMutableArray<NSNumber *> *newOrder = [NSMutableArray new];
    [newOrder addObject:@(currentResolvedIdx)];
    [newOrder addObjectsFromArray:otherIndices];
    _playbackOrder = newOrder;
    _currentOrderIndex = 0;
  } else {
    NSMutableArray<NSNumber *> *newOrder = [NSMutableArray new];
    for (NSUInteger i = 0; i < _resolvedVideos.count; i++) {
      [newOrder addObject:@(i)];
    }
    _playbackOrder = newOrder;
    _currentOrderIndex = (NSInteger)currentResolvedIdx;
  }

  [self applyPlaybackOrderFromCurrentIndexWithAutoPlay:NO
                                                   host:_host
                                      requestGeneration:_activeRequestGeneration];
}

- (void)onSourceReset
{
  _activeRequestGeneration = 0;
  _playbackService = nil;
  _resolvedVideos = [NSMutableArray new];
  _resolvedOriginalIndices = [NSMutableArray new];
  _failedItemCodes = [NSMutableArray new];
  _playbackOrder = [NSMutableArray new];
  _currentOrderIndex = -1;
  _nativeQueueTailIndex = -1;
  _shuffleForCurrentLoad = NO;
  _firstItemEmittedDirectly = NO;
  _resolutionInProgress = NO;
  _queueCompletedEmitted = NO;
  _pendingAdvance = NO;
}

- (void)onPlayerTearDown
{
  [self onSourceReset];
}

- (void)onInvalidate
{
  [self onSourceReset];
}

- (BOOL)claimsSourceLoading
{
  return _videoIds.count > 0;
}

- (void)loadSource:(NSUInteger)requestGeneration
          accountId:(NSString *)accountId
          policyKey:(NSString *)policyKey
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil) {
    return;
  }
  NSArray<NSString *> *videoIds = _videoIds;
  if (videoIds.count == 0) {
    [host emitSourceLoadError:requestGeneration
                          code:@"invalid_configuration"
                    nativeCode:@"playlist_video_ids_missing"
                       message:@"videoIds must be non-empty when loading queue playback"];
    return;
  }

  _activeRequestGeneration = requestGeneration;
  _resolvedVideos = [NSMutableArray new];
  _resolvedOriginalIndices = [NSMutableArray new];
  _failedItemCodes = [NSMutableArray new];
  _playbackOrder = [NSMutableArray new];
  _currentOrderIndex = -1;
  _nativeQueueTailIndex = -1;
  _shuffleForCurrentLoad = _shuffle;
  _firstItemEmittedDirectly = NO;
  _resolutionInProgress = YES;
  _queueCompletedEmitted = NO;
  _pendingAdvance = NO;
  _playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
  [self resolveNextWithRequestGeneration:requestGeneration
                                 videoIds:videoIds
                                    index:0];
}

// Returns YES when the queue moved (or a move was scheduled for when
// resolution completes); NO when nothing is loaded or the queue cannot move —
// the core reports that through onPlayerCommandError.
- (BOOL)advanceQueue
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated || ![host isCurrentRequest:_activeRequestGeneration] || _activeRequestGeneration == 0) {
    return NO;
  }
  if (_playbackOrder.count == 0) {
    _pendingAdvance = YES;
    return YES;
  }

  if (_currentOrderIndex < (NSInteger)_playbackOrder.count - 1) {
    _pendingAdvance = NO;
    _currentOrderIndex += 1;
    [self applyPlaybackOrderFromCurrentIndexWithAutoPlay:YES host:host requestGeneration:_activeRequestGeneration];
    return YES;
  }
  if (_repeatMode == BrightcovePlayerRepeatModeAll && !_resolutionInProgress) {
    _pendingAdvance = NO;
    _currentOrderIndex = 0;
    [self applyPlaybackOrderFromCurrentIndexWithAutoPlay:YES host:host requestGeneration:_activeRequestGeneration];
    return YES;
  }
  if (_resolutionInProgress) {
    // At the last currently-resolved item while more of videoIds might still
    // resolve: defer — a genuine next item could be about to arrive, so this
    // is not at-end yet.
    _pendingAdvance = YES;
    return YES;
  }
  // The queue is at its last item, resolution finished, and repeat will not
  // wrap (repeatMode "off"; "one" loops the current item but never advances
  // past the last one; "all" wrapped above). Silent from this internal path:
  // the typed queue_at_end rejection is emitted only by the imperative
  // handleCommand path, because this method is also the resolution-finished
  // retry for an earlier user request, which must not report a spurious
  // error when nothing further can move.
  _pendingAdvance = YES;
  return YES;
}

- (BOOL)previousQueueItem
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated || ![host isCurrentRequest:_activeRequestGeneration] || _activeRequestGeneration == 0) {
    return NO;
  }
  if (_playbackOrder.count == 0) {
    // A loaded-but-empty order (resolution still in flight): no previous item
    // can exist yet, so the restart-current branch below is the truthful
    // outcome — matching Android's RESTART_CURRENT on resolvedCount == 0.
    // Returning NO here would make the core report the generic precondition
    // failure instead.
    [self restartCurrentItem:host];
    return YES;
  }

  if (_currentOrderIndex > 0) {
    _currentOrderIndex -= 1;
    [self applyPlaybackOrderFromCurrentIndexWithAutoPlay:YES host:host requestGeneration:_activeRequestGeneration];
    return YES;
  }
  if (_repeatMode == BrightcovePlayerRepeatModeAll) {
    _currentOrderIndex = (NSInteger)_playbackOrder.count - 1;
    [self applyPlaybackOrderFromCurrentIndexWithAutoPlay:YES host:host requestGeneration:_activeRequestGeneration];
    return YES;
  }
  [self restartCurrentItem:host];
  return YES;
}

- (void)restartCurrentItem:(id<BrightcovePlayerFeatureHost>)host
{
  // Capture the host weakly and re-check it inside the async completion, like
  // every sibling command path (advanceQueue/previousQueueItem). The view can
  // be torn down while the seek is in flight; a strong capture would then
  // restart playback on a dead controller.
  NSUInteger generation = _activeRequestGeneration;
  __weak id<BrightcovePlayerFeatureHost> weakHost = host;
  [host.playbackController seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
    if (!finished) {
      return;
    }
    id<BrightcovePlayerFeatureHost> strongHost = weakHost;
    if (strongHost == nil || strongHost.isInvalidated ||
        ![strongHost isCurrentRequest:generation] || generation == 0) {
      return;
    }
    [strongHost.playbackController play];
  }];
}

- (void)onDidAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated || ![host isCurrentRequest:_activeRequestGeneration] || _activeRequestGeneration == 0) {
    return;
  }
  NSNumber *sessionGeneration = session.video.properties[BCOVBridgeRequestGenerationKey];
  if (![sessionGeneration isKindOfClass:NSNumber.class] ||
      sessionGeneration.unsignedIntegerValue != _activeRequestGeneration) {
    return;
  }

  if (_firstItemEmittedDirectly) {
    _firstItemEmittedDirectly = NO;
    return;
  }

  if (_nativeQueueTailIndex >= 0) {
    _nativeQueueTailIndex -= 1;
  }

  NSNumber *sessionOriginalIndex = session.video.properties[BCOVBridgeOriginalIndexKey];
  if (![sessionOriginalIndex isKindOfClass:NSNumber.class]) {
    return;
  }
  NSUInteger resolvedIdx = [_resolvedOriginalIndices indexOfObject:sessionOriginalIndex];
  if (resolvedIdx == NSNotFound) {
    return;
  }
  NSUInteger newOrderIndex = [_playbackOrder indexOfObject:@(resolvedIdx)];
  if (newOrderIndex == NSNotFound) {
    return;
  }
  _currentOrderIndex = (NSInteger)newOrderIndex;
  [self emitQueueItemChangedForVideo:_resolvedVideos[resolvedIdx]
                               index:sessionOriginalIndex.integerValue];
}

- (void)onCompletedPlaylist:(NSArray<BCOVVideo *> *)playlist
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated || ![host isCurrentRequest:_activeRequestGeneration] || _activeRequestGeneration == 0) {
    return;
  }
  if (_resolutionInProgress || _resolvedVideos.count == 0 || _queueCompletedEmitted) {
    return;
  }

  if (_repeatMode == BrightcovePlayerRepeatModeAll) {
    _currentOrderIndex = 0;
    [self applyPlaybackOrderFromCurrentIndexWithAutoPlay:YES host:host requestGeneration:_activeRequestGeneration];
    return;
  }

  if (_repeatMode == BrightcovePlayerRepeatModeOff) {
    _queueCompletedEmitted = YES;
    auto eventEmitter = [self emitterFromHost:host];
    if (eventEmitter) {
      eventEmitter->onQueueCompleted(BrightcovePlayerViewEventEmitter::OnQueueCompleted{});
    }
  }
}

// Forwarded from the core's didReceiveLifecycleEvent: for every session
// (before the core's own generation guard); this feature applies its own
// -isCurrentRequest check. Only kBCOVPlaybackSessionLifecycleEventEnd matters
// here: repeatMode "one" needs to intercept it before the SDK's own
// autoAdvance moves past the current item.
- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                  session:(id<BCOVPlaybackSession>)session
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated || ![host isCurrentRequest:_activeRequestGeneration] || _activeRequestGeneration == 0) {
    return;
  }
  if (![lifecycleEvent.eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventEnd]) {
    return;
  }
  if (_repeatMode != BrightcovePlayerRepeatModeOne) {
    return;
  }

  __weak __typeof(self) weakSelf = self;
  [session.player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    id<BrightcovePlayerFeatureHost> strongHost = strongSelf->_host;
    if (strongHost != nil && !strongHost.isInvalidated &&
        [strongHost isCurrentRequest:strongSelf->_activeRequestGeneration]) {
      [strongHost.playbackController play];
    }
  }];
}

- (void)resolveNextWithRequestGeneration:(NSUInteger)requestGeneration
                                 videoIds:(NSArray<NSString *> *)videoIds
                                    index:(NSUInteger)index
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || ![host isCurrentRequest:requestGeneration] || requestGeneration != _activeRequestGeneration) {
    return;
  }

  if (index >= videoIds.count) {
    _resolutionInProgress = NO;
    if (_resolvedVideos.count == 0) {
      NSString *aggregateCode = BCOVAggregateQueueErrorCategory(_failedItemCodes);
      [host emitSourceLoadError:requestGeneration
                            code:aggregateCode
                      nativeCode:@"playlist_empty_after_resolution"
                         message:@"None of the videos in videoIds could be resolved"];
    } else if (_shuffleForCurrentLoad) {
      _playbackOrder = [NSMutableArray new];
      for (NSUInteger i = 0; i < _resolvedVideos.count; i++) {
        [_playbackOrder addObject:@(i)];
      }
      if (_playbackOrder.count > 1) {
        for (NSInteger i = (NSInteger)_playbackOrder.count - 1; i > 0; i--) {
          NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
          [_playbackOrder exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
      }
      _currentOrderIndex = 0;
      NSUInteger firstResolvedIdx = _playbackOrder[0].unsignedIntegerValue;
      BCOVVideo *firstVideo = _resolvedVideos[firstResolvedIdx];
      NSString *readyVideoId = firstVideo.properties[[BCOVVideo PropertyKeyId]] ?: @"";
      [host markVideoLoaded:requestGeneration readyVideoId:readyVideoId];
      [self applyPlaybackOrderFromCurrentIndexWithAutoPlay:NO host:host requestGeneration:requestGeneration];
      if (_pendingAdvance) {
        _pendingAdvance = NO;
        [self advanceQueue];
      }
    } else if (_pendingAdvance) {
      _pendingAdvance = NO;
      [self advanceQueue];
    }
    return;
  }

  NSString *videoId = videoIds[index];
  __weak __typeof(self) weakSelf = self;
  [_playbackService findVideoWithConfiguration:@{[BCOVPlaybackService ConfigurationKeyAssetID]: videoId}
                                 queryParameters:nil
                                      completion:^(BCOVVideo *video, id jsonResponse, NSError *error) {
    void (^handleCompletion)(void) = ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf == nil) {
        return;
      }
      id<BrightcovePlayerFeatureHost> completionHost = strongSelf->_host;
      if (completionHost == nil ||
          ![completionHost isCurrentRequest:requestGeneration] ||
          requestGeneration != strongSelf->_activeRequestGeneration) {
        return;
      }

      if (error != nil || video == nil) {
        NSString *code = @"unknown";
        if (error != nil) {
          code = BCOVErrorCategory(error);
        }
        [strongSelf->_failedItemCodes addObject:code];
        [strongSelf emitQueueItemFailedForVideoId:videoId
                                             index:index
                                             error:error
                                              host:completionHost];
        [strongSelf resolveNextWithRequestGeneration:requestGeneration
                                             videoIds:videoIds
                                                index:index + 1];
        return;
      }

      BCOVVideo *taggedVideo = [completionHost taggedVideo:video
                                             forGeneration:requestGeneration
                                             originalIndex:index];
      [strongSelf->_resolvedVideos addObject:taggedVideo];
      [strongSelf->_resolvedOriginalIndices addObject:@(index)];

      if (!strongSelf->_shuffleForCurrentLoad) {
        NSUInteger resolvedIdx = strongSelf->_resolvedVideos.count - 1;
        [strongSelf->_playbackOrder addObject:@(resolvedIdx)];
        NSInteger orderIndex = (NSInteger)strongSelf->_playbackOrder.count - 1;
        if (orderIndex == 0) {
          strongSelf->_currentOrderIndex = 0;
          NSString *readyVideoId = taggedVideo.properties[[BCOVVideo PropertyKeyId]] ?: @"";
          [completionHost markVideoLoaded:requestGeneration readyVideoId:readyVideoId];
          [strongSelf applyPlaybackOrderFromCurrentIndexWithAutoPlay:NO
                                                                  host:completionHost
                                                     requestGeneration:requestGeneration];
        } else {
          [strongSelf streamResolvedVideoAtOrderIndex:orderIndex host:completionHost];
        }
        if (strongSelf->_pendingAdvance && strongSelf->_playbackOrder.count > 1) {
          strongSelf->_pendingAdvance = NO;
          [strongSelf advanceQueue];
        }
      }

      [strongSelf resolveNextWithRequestGeneration:requestGeneration
                                           videoIds:videoIds
                                              index:index + 1];
    };

    if (NSThread.isMainThread) {
      handleCompletion();
    } else {
      dispatch_async(dispatch_get_main_queue(), handleCompletion);
    }
  }];
}

- (void)applyPlaybackOrderFromCurrentIndexWithAutoPlay:(BOOL)autoPlay
                                                  host:(id<BrightcovePlayerFeatureHost>)host
                                     requestGeneration:(NSUInteger)requestGeneration
{
  if (host == nil || host.isInvalidated || ![host isCurrentRequest:requestGeneration] || requestGeneration == 0) {
    return;
  }
  if (_resolvedVideos.count == 0 || _currentOrderIndex < 0 || _currentOrderIndex >= (NSInteger)_playbackOrder.count) {
    return;
  }

  NSMutableArray<BCOVVideo *> *videosToSet = [NSMutableArray new];
  for (NSInteger i = _currentOrderIndex; i < (NSInteger)_playbackOrder.count; i++) {
    NSUInteger resolvedIdx = _playbackOrder[i].unsignedIntegerValue;
    [videosToSet addObject:_resolvedVideos[resolvedIdx]];
  }

  _firstItemEmittedDirectly = YES;
  NSUInteger currentResolvedIdx = _playbackOrder[_currentOrderIndex].unsignedIntegerValue;
  BCOVVideo *currentVideo = _resolvedVideos[currentResolvedIdx];
  NSNumber *originalIndex = _resolvedOriginalIndices[currentResolvedIdx];
  [self emitQueueItemChangedForVideo:currentVideo index:originalIndex.integerValue];

  [host.playbackController setVideos:videosToSet];
  _nativeQueueTailIndex = (NSInteger)videosToSet.count - 1;
  if (autoPlay) {
    [host.playbackController play];
  }
}

- (void)streamResolvedVideoAtOrderIndex:(NSInteger)orderIndex
                                    host:(id<BrightcovePlayerFeatureHost>)host
{
  if (_nativeQueueTailIndex < 0) {
    return;
  }
  NSInteger expectedOrderIndex = _currentOrderIndex + _nativeQueueTailIndex + 1;
  if (orderIndex != expectedOrderIndex) {
    return;
  }
  NSUInteger resolvedIdx = _playbackOrder[orderIndex].unsignedIntegerValue;
  [host.playbackController insertVideo:_resolvedVideos[resolvedIdx]
                    afterVideoAtIndex:(NSUInteger)_nativeQueueTailIndex];
  _nativeQueueTailIndex += 1;
}

- (void)onFailedToInsertVideo:(BCOVVideo *)video
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated || ![host isCurrentRequest:_activeRequestGeneration] || _activeRequestGeneration == 0) {
    return;
  }
  NSNumber *originalIndex = video.properties[BCOVBridgeOriginalIndexKey];
  if (![originalIndex isKindOfClass:NSNumber.class]) {
    return;
  }
  NSUInteger resolvedIdx = [_resolvedOriginalIndices indexOfObject:originalIndex];
  if (resolvedIdx == NSNotFound) {
    return;
  }
  NSUInteger orderIndex = [_playbackOrder indexOfObject:@(resolvedIdx)];
  if (orderIndex == NSNotFound) {
    return;
  }
  [_playbackOrder removeObjectAtIndex:orderIndex];
  if ((NSInteger)orderIndex <= _currentOrderIndex) {
    _currentOrderIndex -= 1;
  }
  if (_nativeQueueTailIndex >= 0) {
    _nativeQueueTailIndex -= 1;
  }
  [self emitQueueItemFailedForVideoId:video.properties[[BCOVVideo PropertyKeyId]] ?: @""
                                 index:originalIndex.unsignedIntegerValue
                                 error:[NSError errorWithDomain:@"com.brightcove.reactnativeplayer.playlists"
                                                             code:0
                                                         userInfo:@{NSLocalizedDescriptionKey: @"The native queue rejected this video after resolution"}]
                                  host:host];
}

- (void)emitQueueItemChangedForVideo:(BCOVVideo *)video index:(NSInteger)index
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  auto eventEmitter = [self emitterFromHost:host];
  if (!eventEmitter) {
    return;
  }
  NSString *videoId = video.properties[[BCOVVideo PropertyKeyId]];
  eventEmitter->onQueueItemChanged(BrightcovePlayerViewEventEmitter::OnQueueItemChanged{
    .videoId = std::string(videoId.UTF8String ?: ""),
    .index = static_cast<int>(index),
  });
}

- (void)emitQueueItemFailedForVideoId:(NSString *)videoId
                                 index:(NSUInteger)index
                                 error:(nullable NSError *)error
                                  host:(id<BrightcovePlayerFeatureHost>)host
{
  auto eventEmitter = [self emitterFromHost:host];
  if (!eventEmitter) {
    return;
  }
  NSString *code = @"unknown";
  NSString *nativeCode = @"catalog_error";
  NSString *message = @"Unable to retrieve the Brightcove video";
  if (error != nil) {
    nativeCode = BCOVNativeErrorCode(error);
    message = error.localizedDescription ?: message;
    code = BCOVErrorCategory(error);
  }
  eventEmitter->onQueueItemFailed(BrightcovePlayerViewEventEmitter::OnQueueItemFailed{
    .videoId = std::string(videoId.UTF8String ?: ""),
    .index = static_cast<int>(index),
    .code = std::string(code.UTF8String),
    .message = std::string(message.UTF8String ?: ""),
    .nativeCode = std::string(nativeCode.UTF8String ?: ""),
  });
}

- (std::shared_ptr<const BrightcovePlayerViewEventEmitter>)emitterFromHost:(id<BrightcovePlayerFeatureHost>)host
{
  if (host.isInvalidated) {
    return nullptr;
  }
  return [host typedEventEmitter];
}

@end
