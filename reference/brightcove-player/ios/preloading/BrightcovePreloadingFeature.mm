#import "BrightcovePreloadingFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

#import "../core/BCOVErrorCategory.h"

/**
 * Resolves preloadVideoId in the background while the current source plays,
 * and inserts it into the playback controller's own queue
 * (insertVideo:afterVideoAtIndex:) behind the currently playing video — the
 * SDK's own end-of-item advancement (or an explicit advanceToNext) switches
 * to it on its own. Deliberately not a claimsSourceLoading feature: this
 * augments whatever source is already loaded rather than replacing how it is
 * resolved.
 *
 * BCOVPlaybackController exposes no property for "the currently playing
 * video" or "the current queue index" — only insertVideo:afterVideoAtIndex:
 * and the onSessionReady:/onDidAdvanceToPlaybackSession: notifications this
 * feature already receives. _currentVideoId is this feature's own tracking
 * of the playing video's id, updated from those two hooks, and
 * insertVideo:afterVideoAtIndex:0 always targets "right after whatever is
 * playing right now" rather than a numeric queue position this feature
 * cannot otherwise observe.
 *
 * Platform asymmetry from Android: there is no removal API for a video
 * already inserted into the AVQueuePlayer-backed queue. A superseded preload
 * that has not been inserted yet is simply never inserted (guarded by
 * generation); one already inserted before being superseded remains queued
 * and will still play next — there is no SDK call this feature can make to
 * undo that.
 */
@implementation BrightcovePreloadingFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  NSString *_preloadVideoId;
  BOOL _pendingStart;
  NSUInteger _activeGeneration;
  NSString *_currentVideoId;
  NSString *_queuedVideoId;
  NSString *_previousVideoIdAtQueueTime;
  BCOVPlaybackService *_playbackService;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"preloadVideoId"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _preloadVideoId = @"";
}

- (void)setProp:(NSString *)name value:(nullable id)value
{
  if (![name isEqualToString:@"preloadVideoId"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcovePreloadingFeature does not own prop '%@'", name];
    return;
  }
  NSString *newValue = [value isKindOfClass:NSString.class] ? [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
  if ([newValue isEqualToString:_preloadVideoId]) {
    return;
  }

  _activeGeneration += 1;
  _pendingStart = NO;
  _queuedVideoId = nil;
  _previousVideoIdAtQueueTime = nil;
  _preloadVideoId = [newValue copy];
  if (_preloadVideoId.length == 0) {
    return;
  }

  if (_currentVideoId != nil) {
    [self startPreload];
  } else {
    _pendingStart = YES;
  }
}

- (void)onSourceReset
{
  // Invalidate the outgoing source's in-flight lookup and queued identity, but
  // KEEP preloadVideoId. React Native does not resend an unchanged prop after
  // a source swap; clearing it here permanently disabled preloading for every
  // later source. Re-arm the retained request so the next session-ready
  // callback resolves it relative to the new current video. (Android retains
  // the id on source reset and re-arms from its next DID_SET_VIDEO; this
  // deliberately matches Android's keep-the-id behavior for the caller.)
  _activeGeneration += 1;
  _pendingStart = _preloadVideoId.length > 0;
  _currentVideoId = nil;
  _queuedVideoId = nil;
  _previousVideoIdAtQueueTime = nil;
  _playbackService = nil;
}

- (void)onInvalidate
{
  _activeGeneration += 1;
  _playbackService = nil;
  _host = nil;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  [self observeCurrentVideo:session];
}

- (void)onDidAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session
{
  [self observeCurrentVideo:session];
}

- (void)observeCurrentVideo:(id<BCOVPlaybackSession>)session
{
  NSString *newId = session.video.properties[[BCOVVideo PropertyKeyId]];
  if (newId == nil || [newId isEqualToString:_currentVideoId]) {
    return;
  }
  [self checkForHandoff:newId];
  _currentVideoId = newId;

  if (_pendingStart && _preloadVideoId.length > 0) {
    _pendingStart = NO;
    [self startPreload];
  }
}

- (void)checkForHandoff:(NSString *)newVideoId
{
  if (_queuedVideoId == nil || ![newVideoId isEqualToString:_queuedVideoId]) {
    return;
  }

  id<BrightcovePlayerFeatureHost> host = _host;
  auto emitter = [host typedEventEmitter];
  if (emitter != nullptr) {
    emitter->onPreloadHandoff(facebook::react::BrightcovePlayerViewEventEmitter::OnPreloadHandoff{
      .previousVideoId = std::string(_previousVideoIdAtQueueTime.UTF8String ?: ""),
      .currentVideoId = std::string(newVideoId.UTF8String ?: ""),
    });
  }
  _queuedVideoId = nil;
  _previousVideoIdAtQueueTime = nil;
  // The preload slot is consumed: a caller must set a fresh preloadVideoId to
  // preload the next-next video, matching the TS contract's "this is for the
  // next video, not the one already playing".
  _preloadVideoId = @"";
}

- (void)startPreload
{
  id<BrightcovePlayerFeatureHost> host = _host;
  NSString *accountId = host.accountId;
  NSString *policyKey = host.policyKey;
  if (accountId.length == 0 || policyKey.length == 0) {
    return;
  }

  NSUInteger generation = ++_activeGeneration;
  NSString *targetId = [_preloadVideoId copy];
  _playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];

  __weak __typeof(self) weakSelf = self;
  [_playbackService findVideoWithConfiguration:@{
    BCOVPlaybackService.ConfigurationKeyAssetID: targetId,
  }
                                queryParameters:nil
                                     completion:^(BCOVVideo *video, id jsonResponse, NSError *error) {
    // BCOVPlaybackService delivers completions on a background queue; the
    // feature state, controller queue, and Fabric emitter this handler touches
    // are main-thread-only. Hop first, then re-check every guard on main
    // against the CURRENT state — the hop window is another chance for a
    // source reset or prop change to invalidate the result.
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf == nil) return;
      id<BrightcovePlayerFeatureHost> currentHost = strongSelf->_host;
      if (currentHost == nil || generation != strongSelf->_activeGeneration ||
          ![targetId isEqualToString:strongSelf->_preloadVideoId]) {
        return;
      }

      if (error != nil) {
        [strongSelf emitPreloadError:targetId
                                 code:BCOVErrorCategory(error)
                           nativeCode:[NSString stringWithFormat:@"%@:%ld", error.domain ?: @"", (long)error.code]
                              message:error.localizedDescription ?: @"Unable to retrieve the Brightcove video"];
        return;
      }
      if (video == nil) {
        [strongSelf emitPreloadError:targetId
                                 code:@"unknown"
                           nativeCode:@"playback_service_empty_response"
                              message:@"Brightcove returned neither a video nor an error"];
        return;
      }

      strongSelf->_previousVideoIdAtQueueTime = [strongSelf->_currentVideoId copy];
      // Index 0 is always "right after whatever is currently playing": the
      // controller has no queue-position accessor this feature could read
      // instead (see the class doc), and the currently playing item is always
      // at index 0 of its own remaining queue.
      //
      // The video must be tagged with the host's CURRENT generation at insert
      // time — the preload fetch may have started under an earlier one — and
      // folded through willSetVideo: like the core's own catalog path. An
      // untagged insert would fail the core's isCurrentPlaybackSession guard
      // and every event the preloaded video produces would be dropped.
      BCOVVideo *insertableVideo =
          [currentHost taggedAndTransformedVideo:video
                                      forGeneration:currentHost.currentRequestGeneration];
      [currentHost.playbackController insertVideo:insertableVideo afterVideoAtIndex:0];
      strongSelf->_queuedVideoId = video.properties[[BCOVVideo PropertyKeyId]] ?: targetId;

      auto emitter = [currentHost typedEventEmitter];
      if (emitter != nullptr) {
        emitter->onPreloadQueued(facebook::react::BrightcovePlayerViewEventEmitter::OnPreloadQueued{
          .videoId = std::string(targetId.UTF8String ?: ""),
        });
      }
    });
  }];
}

- (void)emitPreloadError:(NSString *)videoId code:(NSString *)code nativeCode:(NSString *)nativeCode message:(NSString *)message
{
  id<BrightcovePlayerFeatureHost> host = _host;
  auto emitter = [host typedEventEmitter];
  if (emitter != nullptr) {
    emitter->onPreloadError(facebook::react::BrightcovePlayerViewEventEmitter::OnPreloadError{
      .videoId = std::string(videoId.UTF8String ?: ""),
      .code = std::string(code.UTF8String ?: ""),
      .nativeCode = std::string(nativeCode.UTF8String ?: ""),
      .message = std::string(message.UTF8String ?: ""),
    });
  }
}

@end
