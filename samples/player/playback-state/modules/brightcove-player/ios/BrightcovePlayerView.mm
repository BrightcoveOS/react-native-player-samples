#import "BrightcovePlayerView.h"

#import <cmath>

#import <AVKit/AVKit.h>
#import <CoreMedia/CoreMedia.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <CoreMedia/CMTime.h>
#import <React/UIView+React.h>
#import <TargetConditionals.h>
#include <cmath>
#include <cstdint>

#import <react/renderer/components/BrightcovePlayerViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/Props.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/RCTComponentViewHelpers.h>

#import "BrightcoveFeatureRegistry.h"
#import "core/BCOVErrorCategory.h"
#import "core/BCOVDeferredErrorFlush.h"
#import "core/BCOVPlaybackAdvancePolicy.h"
#import "core/BCOVPlayerTeardown.h"
#import "core/BCOVVideoIdentity.h"
#import "core/BrightcovePlayerFeature.h"

using namespace facebook::react;

static NSString *const BCOVPendingEventKindKey = @"kind";
static NSString *const BCOVPendingEventGenerationKey = @"generation";
static NSString *const BCOVPendingEventReadyKind = @"ready";
static NSString *const BCOVPendingEventErrorKind = @"error";

static NSString *BCOVNSStringFromStdString(const std::string &value)
{
  return [[NSString alloc] initWithBytes:value.data()
                                  length:value.size()
                                encoding:NSUTF8StringEncoding] ?: @"";
}

static std::string BCOVStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

static BOOL BCOVStringContainsOnlyDigits(NSString *value)
{
  if (value.length == 0) {
    return NO;
  }

  NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
  return [value rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

static NSString *BCOVSeekPositionError(double positionSeconds)
{
  if (!std::isfinite(positionSeconds)) {
    return @"positionSeconds must be finite";
  }
  if (positionSeconds < 0.0) {
    return @"positionSeconds must be non-negative";
  }
  if (positionSeconds > static_cast<double>(INT64_MAX) / 1000.0) {
    return @"positionSeconds is too large";
  }
  return nil;
}
@interface BrightcovePlayerView () <RCTBrightcovePlayerViewViewProtocol,
                                    BCOVPlaybackControllerDelegate,
                                    BCOVPlaybackControllerAdsDelegate,
                                    BCOVPUIPlayerViewDelegate,
                                    BrightcovePlayerFeatureHost>
- (void)applyVideoScalingModeToSession:(id<BCOVPlaybackSession>)session;
- (BOOL)attemptNetworkRecoveryForError:(NSError *)error;
- (void)deferPlaybackError:(NSError *)error;
- (void)completePlayerTearDownForToken:(NSUInteger)token;
- (void)scheduleTearDownBackstopForToken:(NSUInteger)token;
@end

// Upper bound a feature may hold teardown open after returning YES from
// -prepareForPlayerTearDown:. The feature owns that wait (fullscreen uses it to
// finish a screen-mode transition); this is the core's last-resort backstop so
// a feature that never calls the completion cannot pin the view, its delegates,
// or [super invalidate] forever. Longer than the fullscreen feature's own 1s
// exit guard so a healthy exit wins and only a misbehaving feature reaches it.
static const NSTimeInterval kBCOVTearDownBackstopInterval = 2.0;

@implementation BrightcovePlayerView {
  BCOVPlaybackService *_playbackService;
  id<BCOVPlaybackController> _playbackController;
  BCOVPUIPlayerView *_playerView;
  // The current session's AVPlayer, captured on Ready, is where volume/muted
  // are actually applied (the SDK has no volume property of its own). Weak:
  // the controller owns the session, which is released on source change /
  // teardown, and this must not extend its life.
  __weak id<BCOVPlaybackSession> _currentSession;

  // The features this bridge copy contains, declared by the sample-owned
  // BrightcoveFeatureRegistry. The core routes feature props/lifecycle through
  // this list and knows nothing about concrete features.
  NSArray<id<BrightcovePlayerFeature>> *_features;

  NSString *_accountId;
  NSString *_policyKey;
  NSString *_videoId;
  NSString *_featureReadyVideoId;
  NSString *_lastConfigurationError;

  NSUInteger _requestGeneration;
  NSUInteger _seekRequestToken;
  BOOL _autoPlay;
  float _playbackRate;
  BOOL _loop;
  double _volume;
  BOOL _muted;
  NSString *_videoScalingMode;
  BOOL _sourceDirty;
  BOOL _readyEmitted;
  BOOL _sessionReady;
  BOOL _sourceFailed;
  NSError *_pendingPlaybackError;
  NSUInteger _pendingPlaybackErrorToken;
  BOOL _networkRecoveryInProgress;
  NSError *_networkRecoveryError;
  BOOL _isPlaying;
  // Intent to play, set when we ask the controller to play and cleared on
  // pause/end. Distinct from _isPlaying (which only flips on the Play event):
  // if the view is detached while still buffering, _isPlaying is false but
  // _playbackRequested is true, so we still resume on re-attach. Mirrors
  // Android's playbackRequested.
  BOOL _playbackRequested;
  BOOL _resumeWhenAttached;
  BOOL _invalidated;
  BOOL _teardownPending;
  // Monotonic identity for the teardown currently waiting on a feature.
  // A completion/backstop from an older teardown must not complete a newer
  // player instance just because _teardownPending became true again.
  NSUInteger _teardownToken;
  NSMutableArray<NSDictionary<NSString *, id> *> *_pendingEvents;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<BrightcovePlayerViewComponentDescriptor>();
}

+ (BOOL)shouldBeRecycled
{
  return NO;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const BrightcovePlayerViewProps>();
    _props = defaultProps;

    _accountId = @"";
    _policyKey = @"";
    _videoId = @"";
    _featureReadyVideoId = nil;
    _autoPlay = defaultProps->autoPlay;
    _playbackRate = defaultProps->playbackRate;
    _loop = defaultProps->loop;
    _volume = defaultProps->volume;
    _muted = defaultProps->muted;
    _videoScalingMode = @"fit";
    _sourceDirty = YES;
    _pendingEvents = [NSMutableArray array];

    _features = [BrightcoveFeatureRegistry installedFeatures];
    for (id<BrightcovePlayerFeature> feature in _features) {
      [feature attachToHost:self];
    }
  }

  return self;
}

#pragma mark BrightcovePlayerFeatureHost

- (id<BCOVPlaybackController>)playbackController
{
  return _playbackController;
}

- (BCOVPUIPlayerView *)playerView
{
  return _playerView;
}

- (UIView *)hostView
{
  return self;
}

- (NSString *)accountId
{
  return _accountId;
}

- (NSString *)policyKey
{
  return _policyKey;
}

- (NSString *)videoId
{
  return _videoId;
}

- (UIViewController *)presentingViewController
{
  return [self reactViewController];
}

- (BOOL)isInvalidated
{
  return _invalidated;
}

- (BOOL)hasFeatureClaimingSourceLoading
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(claimsSourceLoading)] && [feature claimsSourceLoading]) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)hasFeatureProvidingFairPlayExcludingFeature:(id<BrightcovePlayerFeature>)excludedFeature
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if (feature == excludedFeature) {
      continue;
    }
    if ([feature respondsToSelector:@selector(providesFairPlaySessionProvider)] &&
        [feature providesFairPlaySessionProvider]) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)isHostActive
{
  if (NSThread.isMainThread) {
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
  }
  __block BOOL active = NO;
  dispatch_sync(dispatch_get_main_queue(), ^{
    active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
  });
  return active;
}

- (BOOL)isCurrentPlaybackSession:(id<BCOVPlaybackSession>)session
{
  if (_invalidated || session == nil) {
    return NO;
  }

  // A generation tag naming the active request is the sole authority: every
  // video this view loaded carries one — the core's own catalog path, the
  // feature-owned source loaders, and any feature-inserted queue item
  // (preloading's next-up video, tagged at insert). Sessions arrive only
  // from this view's own controller, so a current-generation tag can never
  // name another view's or another request's video. This keeps a
  // feature-inserted video whose id differs from the videoId prop (the
  // preloaded next-up item) fully serviced: ready, playback events, and
  // session-scoped state all apply. An untagged session names nothing this
  // view loaded and is rejected (fail-closed; every in-repo loader tags).
  NSNumber *sessionGeneration = session.video.properties[BCOVBridgeRequestGenerationKey];
  return [sessionGeneration isKindOfClass:NSNumber.class] &&
      sessionGeneration.unsignedIntegerValue == _requestGeneration;
}

- (std::shared_ptr<const BrightcovePlayerViewEventEmitter>)typedEventEmitter
{
  return std::dynamic_pointer_cast<const BrightcovePlayerViewEventEmitter>(_eventEmitter);
}

- (void)requestPlayerRebuild
{
  if (_playerView == nil || _invalidated) {
    return;
  }
  _sourceDirty = YES;
  _readyEmitted = NO;
  _featureReadyVideoId = nil;
  _sessionReady = NO;
  [self tearDownPlayer];
  // finalizeUpdates (already scheduled for the prop change that requested the
  // rebuild) recreates the player with fresh options and re-applies the source.
}

- (void)requestSourceReload
{
  if (_invalidated) {
    return;
  }
  _requestGeneration += 1;
  _seekRequestToken += 1;
  _sourceDirty = YES;
  _readyEmitted = NO;
  _featureReadyVideoId = nil;
  _sessionReady = NO;
  _sourceFailed = NO;
  _networkRecoveryInProgress = NO;
  _networkRecoveryError = nil;
  _pendingPlaybackError = nil;
  _pendingPlaybackErrorToken += 1;
  _isPlaying = NO;
  _playbackRequested = NO;
  _resumeWhenAttached = NO;
  _lastConfigurationError = nil;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onSourceReset)]) {
      [feature onSourceReset];
    }
  }
  _playbackService = nil;
  [self tearDownPlayer];
}

- (BOOL)isCurrentRequest:(NSUInteger)requestGeneration
{
  return !_invalidated && requestGeneration == _requestGeneration;
}

- (NSUInteger)currentRequestGeneration
{
  return _requestGeneration;
}

- (BCOVVideo *)taggedVideo:(BCOVVideo *)video forGeneration:(NSUInteger)requestGeneration
{
  return [video update:^(BCOVMutableVideo *mutableVideo) {
    NSMutableDictionary *properties = [mutableVideo.properties mutableCopy];
    properties[BCOVBridgeRequestGenerationKey] = @(requestGeneration);
    mutableVideo.properties = properties;
  }];
}

- (BCOVVideo *)taggedAndTransformedVideo:(BCOVVideo *)video
                           forGeneration:(NSUInteger)requestGeneration
{
  // Run the transform chain first, then stamp the generation on the final
  // video. Stamping before the chain relied on every willSetVideo: being
  // property-preserving (the in-repo ones use -update:); a future feature that
  // returns a reconstructed BCOVVideo would silently drop the tag, and the
  // fail-closed identity rule would then service that source with no events at
  // all. Stamping last makes the tag impossible to drop.
  BCOVVideo *transformedVideo = video;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(willSetVideo:)]) {
      BCOVVideo *transformed = [feature willSetVideo:transformedVideo];
      if (transformed != nil) {
        transformedVideo = transformed;
      }
    }
  }
  return [self taggedVideo:transformedVideo forGeneration:requestGeneration];
}

- (BCOVVideo *)taggedVideo:(BCOVVideo *)video
              forGeneration:(NSUInteger)requestGeneration
              originalIndex:(NSUInteger)originalIndex
{
  return [video update:^(BCOVMutableVideo *mutableVideo) {
    NSMutableDictionary *properties = [mutableVideo.properties mutableCopy];
    properties[BCOVBridgeRequestGenerationKey] = @(requestGeneration);
    properties[BCOVBridgeOriginalIndexKey] = @(originalIndex);
    mutableVideo.properties = properties;
  }];
}

- (void)markVideoLoaded:(NSUInteger)requestGeneration readyVideoId:(NSString *)readyVideoId
{
  if (![self isCurrentRequest:requestGeneration]) {
    return;
  }
  _readyEmitted = NO;
  _featureReadyVideoId = [readyVideoId copy];
  _sessionReady = NO;
  _sourceFailed = NO;
}

- (void)emitSourceLoadError:(NSUInteger)requestGeneration
                       code:(NSString *)code
                 nativeCode:(NSString *)nativeCode
                    message:(NSString *)message
{
  if (![self isCurrentRequest:requestGeneration]) {
    return;
  }
  [self emitErrorCategory:code nativeCode:nativeCode message:message];
}

// Routes a feature-owned prop to the feature that owns it. Fails loudly when
// no installed feature owns the prop: that means this bridge copy does not
// include the feature's directory, and silently ignoring the prop would be
// exactly the kind of cross-platform inconsistency this bridge exists to
// prevent. Default values are not routed (the prop was simply not set).
- (void)seekToLiveEdge
{
  [self handleCommand:@"seekToLiveEdge"];
}

- (void)setFeatureProp:(NSString *)name value:(id)value isDefault:(BOOL)isDefault
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([[feature ownedProps] containsObject:name]) {
      [feature setProp:name value:value];
      return;
    }
  }
  if (isDefault) {
    return;
  }
  [NSException raise:NSInternalInconsistencyException
              format:@"The '%@' prop requires a player feature that is not included in this "
                     @"bridge copy. Copy the feature's directory from "
                     @"reference/brightcove-player into modules/brightcove-player and add it "
                     @"to +installedFeatures in BrightcoveFeatureRegistry.mm.", name];
}

// Dispatches an imperative command (see the TS contract's NativeCommands doc
// comment) to this override, which the generated
// RCTBrightcovePlayerViewHandleCommand helper dispatches by name to -next /
// -previous below.
- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTBrightcovePlayerViewHandleCommand(self, commandName, args);
}

- (void)next
{
  [self handleCommand:@"next"];
}

- (void)previous
{
  [self handleCommand:@"previous"];
}

#pragma mark -

- (void)didMoveToWindow
{
  [super didMoveToWindow];

  if (_invalidated) {
    return;
  }
  if (self.window == nil) {
    BOOL keepsAliveInBackground = [self keepsPlaybackAliveInBackground];
    // Feature-managed playback (ads/IMA) starts via the controller's own
    // autoPlay, so during a pre-roll neither _isPlaying (set on the content
    // Play event) nor _playbackRequested is set yet — but the ad is playing and
    // must be paused off-window. Treat a ready feature-managed autoPlay view as
    // active so it pauses and resumes like any other.
    BOOL featureManagedActive = _autoPlay && _sessionReady && [self featureManagedPlayback];
    if (!keepsAliveInBackground && (_isPlaying || _playbackRequested || featureManagedActive)) {
      _resumeWhenAttached = YES;
      _playbackRequested = NO;
      [_playbackController pause];
    }
    return;
  }

  [self ensurePlayer];
  [self applyPendingConfiguration];
  [self flushPendingEvents];
  if (_resumeWhenAttached && _sessionReady) {
    _resumeWhenAttached = NO;
    [_playbackController play];
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  if (_invalidated) {
    return;
  }
  // RN sizes this view here. If the player was deferred because bounds were
  // still empty (see ensurePlayer), create it now that they are real; otherwise
  // keep the existing player view tracking the host bounds.
  if (_playerView == nil) {
    [self ensurePlayer];
    [self applyPendingConfiguration];
  } else {
    _playerView.frame = self.bounds;
  }
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &oldViewProps = *std::static_pointer_cast<const BrightcovePlayerViewProps>(_props);
  const auto &newViewProps = *std::static_pointer_cast<const BrightcovePlayerViewProps>(props);

  BOOL sourceChanged = oldViewProps.accountId != newViewProps.accountId ||
      oldViewProps.policyKey != newViewProps.policyKey ||
      oldViewProps.videoId != newViewProps.videoId;

  if (sourceChanged) {
    [self requestSourceReload];
  }

  _accountId = BCOVNSStringFromStdString(newViewProps.accountId);
  _policyKey = BCOVNSStringFromStdString(newViewProps.policyKey);
  _videoId = BCOVNSStringFromStdString(newViewProps.videoId);

  // autoPlay is an initialization-only hint (see the TS contract): it decides
  // whether playback starts when the session first becomes ready (see the
  // Ready lifecycle handler, which reads _autoPlay), not a live play/pause
  // control. Record the value but do not start or stop an already-loaded video
  // on a later toggle — live play/pause is the app's own controls' job. This
  // holds for feature-managed playback (ads) too: only the initial Ready event
  // needs the controller's own autoPlay (to avoid racing the IMA ads-manager
  // load); a later toggle must stay a no-op like every other player.
  _autoPlay = newViewProps.autoPlay;
  BOOL loopChanged = oldViewProps.loop != newViewProps.loop;
  _loop = newViewProps.loop;
  // autoAdvance is derived from _loop (see ensurePlayer). Re-apply it on a live
  // toggle so turning loop on stops the SDK from racing the core's restart to
  // the next queued item; ensurePlayer only runs at creation.
  if (loopChanged && _playbackController != nil) {
    _playbackController.autoAdvance = BCOVShouldAutoAdvance(_loop);
  }

  // volume and muted are live controls (unlike autoPlay): a caller can change
  // them at any time. Record the value and apply it if a session already
  // exists; if not, it is applied once the session becomes ready (see
  // didReceiveLifecycleEvent's Ready case), since AVPlayer does not exist
  // before then.
  if (oldViewProps.volume != newViewProps.volume || oldViewProps.muted != newViewProps.muted) {
    // The TS contract documents out-of-range values as clamped; clamp here
    // (not just at apply time) so _volume itself always holds a valid value,
    // matching Android's setVolume. NaN is not a valid "out of range" value to
    // clamp to an endpoint (NaN compares false to both bounds, so a plain
    // min/max clamp leaves it unchanged and would reach AVPlayer.volume=NaN
    // uncaught) — ignore it and keep the previous volume instead, matching
    // Android's isNaN check in setVolume.
    double requestedVolume = newViewProps.volume;
    if (!isnan(requestedVolume)) {
      _volume = MIN(MAX(requestedVolume, 0.0), 1.0);
    } else {
      NSLog(@"BrightcovePlayerView: ignoring invalid NaN volume request");
    }
    _muted = newViewProps.muted;
    [self applyVolume];
  }

  // A live control (like volume/muted, unlike autoPlay): can be changed at
  // any time, including mid-playback, and is not tied to any one source — not
  // reset in the sourceChanged branch above, matching a customer's
  // expectation that setting 2x once keeps every subsequently loaded video at
  // 2x too. Values <= 0, non-finite values (NaN / +/-Inf), or values exceeding
  // positive finite float bounds are rejected: a rejected value keeps whatever
  // rate was last valid, logged as a warning, matching Android exactly.
  if (oldViewProps.playbackRate != newViewProps.playbackRate) {
    double requestedRate = newViewProps.playbackRate;
    float floatRate = (float)requestedRate;
    if (!std::isfinite(requestedRate) || requestedRate <= 0.0 || !std::isfinite(floatRate) || floatRate <= 0.0f) {
      NSLog(@"BrightcovePlayerView: ignoring invalid playback rate: %f", requestedRate);
    } else {
      _playbackRate = floatRate;
      _playbackController.playbackRate = _playbackRate;
    }
  }

  NSString *newVideoScalingMode = nil;
  switch (newViewProps.videoScalingMode) {
    case BrightcovePlayerViewVideoScalingMode::Fit:
      newVideoScalingMode = @"fit";
      break;
    case BrightcovePlayerViewVideoScalingMode::Fill:
      newVideoScalingMode = @"fill";
      break;
    default:
      // A JS-supplied prop value must never crash the app: throwing here would
      // be an uncaught Objective-C exception unwinding through Fabric's
      // mounting code, rather than a reportable error. Log and keep the last
      // valid mode, matching the playbackRate branch above.
      NSLog(@"BrightcovePlayerView: ignoring unsupported videoScalingMode value");
      break;
  }
  if (newVideoScalingMode != nil &&
      ![_videoScalingMode isEqualToString:newVideoScalingMode]) {
    _videoScalingMode = [newVideoScalingMode copy];
    if (_sessionReady) {
      [self applyVideoScalingModeToSession:_currentSession];
    }
  }
  // Feature props: forwarded only when their value changed, so a bridge copy
  // without a feature only errors if the prop is actually used (non-default).
  if (oldViewProps.controlsEnabled != newViewProps.controlsEnabled) {
    [self setFeatureProp:@"controlsEnabled"
                   value:@(newViewProps.controlsEnabled)
               isDefault:newViewProps.controlsEnabled];
  }
  // BrightcovePlayerViewSidecarTracksStruct only defines operator== under
  // RN_SERIALIZABLE_STATE, so std::vector comparison is unavailable here;
  // compare element-wise instead.
  BOOL sidecarTracksChanged =
      oldViewProps.sidecarTracks.size() != newViewProps.sidecarTracks.size();
  if (!sidecarTracksChanged) {
    for (size_t i = 0; i < newViewProps.sidecarTracks.size(); i++) {
      const auto &oldTrack = oldViewProps.sidecarTracks[i];
      const auto &newTrack = newViewProps.sidecarTracks[i];
      if (oldTrack.url != newTrack.url ||
          oldTrack.language != newTrack.language ||
          oldTrack.label != newTrack.label) {
        sidecarTracksChanged = YES;
        break;
      }
    }
  }
  if (sidecarTracksChanged) {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *tracks =
        [NSMutableArray arrayWithCapacity:newViewProps.sidecarTracks.size()];
    for (const auto &track : newViewProps.sidecarTracks) {
      NSString *label = BCOVNSStringFromStdString(track.label);
      [tracks addObject:@{
        @"url": BCOVNSStringFromStdString(track.url),
        @"language": BCOVNSStringFromStdString(track.language),
        @"label": label.length > 0 ? label : BCOVNSStringFromStdString(track.language),
      }];
    }
    [self setFeatureProp:@"sidecarTracks"
                   value:tracks
               isDefault:tracks.count == 0];
  }
  if (oldViewProps.customCaptionRenderingEnabled != newViewProps.customCaptionRenderingEnabled) {
    [self setFeatureProp:@"customCaptionRenderingEnabled"
                   value:@(newViewProps.customCaptionRenderingEnabled)
               isDefault:!newViewProps.customCaptionRenderingEnabled];
  }
  if (oldViewProps.captionsEnabled != newViewProps.captionsEnabled) {
    [self setFeatureProp:@"captionsEnabled"
                   value:@(newViewProps.captionsEnabled)
               isDefault:!newViewProps.captionsEnabled];
  }
  if (oldViewProps.captionTrackId != newViewProps.captionTrackId) {
    NSString *captionTrackId = BCOVNSStringFromStdString(newViewProps.captionTrackId);
    [self setFeatureProp:@"captionTrackId"
                   value:captionTrackId
               isDefault:captionTrackId.length == 0];
  }
  if (oldViewProps.audioTrackId != newViewProps.audioTrackId) {
    NSString *audioTrackId = BCOVNSStringFromStdString(newViewProps.audioTrackId);
    [self setFeatureProp:@"audioTrackId"
                   value:audioTrackId
               isDefault:audioTrackId.length == 0];
  }
  if (oldViewProps.offlineSourceId != newViewProps.offlineSourceId) {
    NSString *offlineSourceId = BCOVNSStringFromStdString(newViewProps.offlineSourceId);
    [self setFeatureProp:@"offlineSourceId"
                   value:offlineSourceId
               isDefault:offlineSourceId.length == 0];
  }
  if (oldViewProps.videoIds != newViewProps.videoIds) {
    NSMutableArray<NSString *> *videoIds =
        [NSMutableArray arrayWithCapacity:newViewProps.videoIds.size()];
    for (const auto &id : newViewProps.videoIds) {
      [videoIds addObject:BCOVNSStringFromStdString(id)];
    }
    [self setFeatureProp:@"videoIds" value:videoIds isDefault:videoIds.count == 0];
  }
  if (oldViewProps.repeatMode != newViewProps.repeatMode) {
    NSString *repeatMode = BCOVNSStringFromStdString(facebook::react::toString(newViewProps.repeatMode));
    [self setFeatureProp:@"repeatMode"
                   value:repeatMode
               isDefault:newViewProps.repeatMode == facebook::react::BrightcovePlayerViewRepeatMode::Off];
  }
  if (oldViewProps.shuffle != newViewProps.shuffle) {
    [self setFeatureProp:@"shuffle"
                   value:@(newViewProps.shuffle)
               isDefault:!newViewProps.shuffle];
  }
  if (oldViewProps.videoReferenceId != newViewProps.videoReferenceId) {
    NSString *videoReferenceId = BCOVNSStringFromStdString(newViewProps.videoReferenceId);
    [self setFeatureProp:@"videoReferenceId"
                   value:videoReferenceId
               isDefault:videoReferenceId.length == 0];
  }
  if (oldViewProps.playlistId != newViewProps.playlistId) {
    NSString *playlistId = BCOVNSStringFromStdString(newViewProps.playlistId);
    [self setFeatureProp:@"playlistId"
                   value:playlistId
               isDefault:playlistId.length == 0];
  }
  if (oldViewProps.playlistReferenceId != newViewProps.playlistReferenceId) {
    NSString *playlistReferenceId = BCOVNSStringFromStdString(newViewProps.playlistReferenceId);
    [self setFeatureProp:@"playlistReferenceId"
                   value:playlistReferenceId
               isDefault:playlistReferenceId.length == 0];
  }
  if (oldViewProps.sourceUrl != newViewProps.sourceUrl) {
    NSString *sourceUrl = BCOVNSStringFromStdString(newViewProps.sourceUrl);
    [self setFeatureProp:@"sourceUrl"
                   value:sourceUrl
               isDefault:sourceUrl.length == 0];
  }
  if (oldViewProps.pictureInPictureEnabled != newViewProps.pictureInPictureEnabled) {
    [self setFeatureProp:@"pictureInPictureEnabled"
                   value:@(newViewProps.pictureInPictureEnabled)
               isDefault:!newViewProps.pictureInPictureEnabled];
  }
  if (oldViewProps.airPlayEnabled != newViewProps.airPlayEnabled) {
    [self setFeatureProp:@"airPlayEnabled"
                   value:@(newViewProps.airPlayEnabled)
               isDefault:!newViewProps.airPlayEnabled];
  }
  if (oldViewProps.castEnabled != newViewProps.castEnabled) {
    [self setFeatureProp:@"castEnabled"
                   value:@(newViewProps.castEnabled)
               isDefault:!newViewProps.castEnabled];
  }
  if (oldViewProps.backgroundPlaybackEnabled != newViewProps.backgroundPlaybackEnabled) {
    [self setFeatureProp:@"backgroundPlaybackEnabled"
                   value:@(newViewProps.backgroundPlaybackEnabled)
               isDefault:!newViewProps.backgroundPlaybackEnabled];
  }
  if (oldViewProps.audioDescriptionEnabled != newViewProps.audioDescriptionEnabled) {
    [self setFeatureProp:@"audioDescriptionEnabled"
                   value:@(newViewProps.audioDescriptionEnabled)
               isDefault:!newViewProps.audioDescriptionEnabled];
  }
  if (oldViewProps.preferredPeakBitrate != newViewProps.preferredPeakBitrate) {
    [self setFeatureProp:@"preferredPeakBitrate"
                   value:@(newViewProps.preferredPeakBitrate)
               isDefault:newViewProps.preferredPeakBitrate == 0];
  }
  if (oldViewProps.chapterSeekTime != newViewProps.chapterSeekTime) {
    [self setFeatureProp:@"chapterSeekTime"
                   value:@(newViewProps.chapterSeekTime)
               isDefault:newViewProps.chapterSeekTime == -1];
  }
  if (oldViewProps.chapterSeekRequestId != newViewProps.chapterSeekRequestId) {
    [self setFeatureProp:@"chapterSeekRequestId"
                   value:@(newViewProps.chapterSeekRequestId)
               isDefault:newViewProps.chapterSeekRequestId == 0];
  }
  if (oldViewProps.adTagUrl != newViewProps.adTagUrl) {
    NSString *adTagUrl = BCOVNSStringFromStdString(newViewProps.adTagUrl);
    [self setFeatureProp:@"adTagUrl"
                   value:adTagUrl
               isDefault:adTagUrl.length == 0];
    if (_playerView != nil) {
      [self requestPlayerRebuild];
    }
  }
  if (oldViewProps.adConfigId != newViewProps.adConfigId) {
    NSString *adConfigId = BCOVNSStringFromStdString(newViewProps.adConfigId);
    [self setFeatureProp:@"adConfigId"
                   value:adConfigId
               isDefault:adConfigId.length == 0];
    if (_playerView != nil) {
      [self requestPlayerRebuild];
    }
  }
  if (oldViewProps.thumbnailSeekingEnabled != newViewProps.thumbnailSeekingEnabled) {
    [self setFeatureProp:@"thumbnailSeekingEnabled"
                   value:@(newViewProps.thumbnailSeekingEnabled)
               isDefault:!newViewProps.thumbnailSeekingEnabled];
  }
  if (oldViewProps.vrMode != newViewProps.vrMode) {
    [self setFeatureProp:@"vrMode"
                   value:@(newViewProps.vrMode)
               isDefault:!newViewProps.vrMode];
  }
  if (oldViewProps.preloadVideoId != newViewProps.preloadVideoId) {
    NSString *preloadVideoId = BCOVNSStringFromStdString(newViewProps.preloadVideoId);
    [self setFeatureProp:@"preloadVideoId"
                   value:preloadVideoId
               isDefault:preloadVideoId.length == 0];
  }
  if (oldViewProps.freeWheelAdUrl != newViewProps.freeWheelAdUrl) {
    NSString *url = BCOVNSStringFromStdString(newViewProps.freeWheelAdUrl);
    [self setFeatureProp:@"freeWheelAdUrl"
                   value:url
               isDefault:url.length == 0];
  }
  if (oldViewProps.freeWheelNetworkId != newViewProps.freeWheelNetworkId) {
    [self setFeatureProp:@"freeWheelNetworkId"
                   value:@(newViewProps.freeWheelNetworkId)
               isDefault:newViewProps.freeWheelNetworkId == 0];
  }
  if (oldViewProps.freeWheelProfile != newViewProps.freeWheelProfile) {
    NSString *profile = BCOVNSStringFromStdString(newViewProps.freeWheelProfile);
    [self setFeatureProp:@"freeWheelProfile"
                   value:profile
               isDefault:profile.length == 0];
  }
  if (oldViewProps.freeWheelSiteSectionId != newViewProps.freeWheelSiteSectionId) {
    NSString *siteSectionId = BCOVNSStringFromStdString(newViewProps.freeWheelSiteSectionId);
    [self setFeatureProp:@"freeWheelSiteSectionId"
                   value:siteSectionId
               isDefault:siteSectionId.length == 0];
  }
  if (oldViewProps.freeWheelVideoAssetId != newViewProps.freeWheelVideoAssetId) {
    NSString *assetId = BCOVNSStringFromStdString(newViewProps.freeWheelVideoAssetId);
    [self setFeatureProp:@"freeWheelVideoAssetId"
                   value:assetId
               isDefault:assetId.length == 0];
  }
  if (oldViewProps.pulseHost != newViewProps.pulseHost) {
    NSString *host = BCOVNSStringFromStdString(newViewProps.pulseHost);
    [self setFeatureProp:@"pulseHost"
                   value:host
               isDefault:host.length == 0];
  }
  if (oldViewProps.pulseCategory != newViewProps.pulseCategory) {
    NSString *category = BCOVNSStringFromStdString(newViewProps.pulseCategory);
    [self setFeatureProp:@"pulseCategory"
                   value:category
               isDefault:category.length == 0];
  }
  if (oldViewProps.pulseTags != newViewProps.pulseTags) {
    NSString *tags = BCOVNSStringFromStdString(newViewProps.pulseTags);
    [self setFeatureProp:@"pulseTags"
                   value:tags
               isDefault:tags.length == 0];
  }
  if (oldViewProps.pulseContentMetadataTitle != newViewProps.pulseContentMetadataTitle) {
    NSString *title = BCOVNSStringFromStdString(newViewProps.pulseContentMetadataTitle);
    [self setFeatureProp:@"pulseContentMetadataTitle"
                   value:title
               isDefault:title.length == 0];
  }
  if (oldViewProps.pulseMidrollPositions != newViewProps.pulseMidrollPositions) {
    NSString *positions = BCOVNSStringFromStdString(newViewProps.pulseMidrollPositions);
    [self setFeatureProp:@"pulseMidrollPositions"
                   value:positions
               isDefault:positions.length == 0];
  }
  if (oldViewProps.heartbeatTrackingServer != newViewProps.heartbeatTrackingServer) {
    NSString *server = BCOVNSStringFromStdString(newViewProps.heartbeatTrackingServer);
    [self setFeatureProp:@"heartbeatTrackingServer"
                   value:server
               isDefault:server.length == 0];
  }
  if (oldViewProps.heartbeatChannel != newViewProps.heartbeatChannel) {
    NSString *channel = BCOVNSStringFromStdString(newViewProps.heartbeatChannel);
    [self setFeatureProp:@"heartbeatChannel"
                   value:channel
               isDefault:channel.length == 0];
  }
  if (oldViewProps.heartbeatAppVersion != newViewProps.heartbeatAppVersion) {
    NSString *appVersion = BCOVNSStringFromStdString(newViewProps.heartbeatAppVersion);
    [self setFeatureProp:@"heartbeatAppVersion"
                   value:appVersion
               isDefault:appVersion.length == 0];
  }
  if (oldViewProps.heartbeatOvp != newViewProps.heartbeatOvp) {
    NSString *ovp = BCOVNSStringFromStdString(newViewProps.heartbeatOvp);
    [self setFeatureProp:@"heartbeatOvp"
                   value:ovp
               isDefault:ovp.length == 0];
  }
  if (oldViewProps.heartbeatPlayerName != newViewProps.heartbeatPlayerName) {
    NSString *playerName = BCOVNSStringFromStdString(newViewProps.heartbeatPlayerName);
    [self setFeatureProp:@"heartbeatPlayerName"
                   value:playerName
               isDefault:playerName.length == 0];
  }
  if (oldViewProps.heartbeatSsl != newViewProps.heartbeatSsl) {
    [self setFeatureProp:@"heartbeatSsl"
                   value:@(newViewProps.heartbeatSsl)
               isDefault:!newViewProps.heartbeatSsl];
  }
  if (oldViewProps.heartbeatDebugLogging != newViewProps.heartbeatDebugLogging) {
    [self setFeatureProp:@"heartbeatDebugLogging"
                   value:@(newViewProps.heartbeatDebugLogging)
               isDefault:!newViewProps.heartbeatDebugLogging];
  }
  if (oldViewProps.daiSourceId != newViewProps.daiSourceId) {
    NSString *daiSourceId = BCOVNSStringFromStdString(newViewProps.daiSourceId);
    [self setFeatureProp:@"daiSourceId"
                   value:daiSourceId
               isDefault:daiSourceId.length == 0];
  }
  if (oldViewProps.daiVideoId != newViewProps.daiVideoId) {
    NSString *daiVideoId = BCOVNSStringFromStdString(newViewProps.daiVideoId);
    [self setFeatureProp:@"daiVideoId"
                   value:daiVideoId
               isDefault:daiVideoId.length == 0];
  }

  [super updateProps:props oldProps:oldProps];
}

- (void)updateEventEmitter:(const facebook::react::EventEmitter::Shared &)eventEmitter
{
  [super updateEventEmitter:eventEmitter];
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onEventEmitterReady)]) {
      [feature onEventEmitterReady];
    }
  }
}

- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask
{
  [super finalizeUpdates:updateMask];
  [self ensurePlayer];
  [self applyPendingConfiguration];
  // All prop updates for this transaction have been applied; let features act
  // on any behavior that depends on more than one prop as a single coalesced
  // result (captions applies its selection here, not per-prop).
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onPropsCommitted)]) {
      [feature onPropsCommitted];
    }
  }
  [self flushPendingEvents];
}

- (void)invalidate
{
  if (_invalidated) {
    return;
  }

  _invalidated = YES;
  _requestGeneration += 1;
  _seekRequestToken += 1;
  _featureReadyVideoId = nil;
  if (_pendingEvents.count > 0) {
    NSLog(@"Discarding %lu undelivered player events during invalidation", (unsigned long)_pendingEvents.count);
    [_pendingEvents removeAllObjects];
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onInvalidate)]) {
      [feature onInvalidate];
    }
  }
  // Release the service (see updateProps): do not invalidate the possibly
  // shared URL session; the generation guard already ignores late responses.
  _playbackService = nil;
  [self tearDownPlayer];
}

- (void)tearDownPlayer
{
  if (_teardownPending) {
    return;
  }
  _teardownPending = YES;
  NSUInteger token = ++_teardownToken;
  __weak __typeof(self) weakSelf = self;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(prepareForPlayerTearDown:)] &&
        [feature prepareForPlayerTearDown:^{
          [weakSelf completePlayerTearDownForToken:token];
        }]) {
      // The feature owns the wait; bound it so a feature that never invokes the
      // completion cannot latch teardown (and [super invalidate]) forever.
      [self scheduleTearDownBackstopForToken:token];
      return;
    }
  }
  [self completePlayerTearDownForToken:token];
}

- (void)completePlayerTearDownForToken:(NSUInteger)token
{
  if (!BCOVShouldCompletePlayerTearDown(token, _teardownToken, _teardownPending)) {
    return;
  }
  [self completePlayerTearDown];
}

- (void)scheduleTearDownBackstopForToken:(NSUInteger)token
{
  __weak __typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                               (int64_t)(kBCOVTearDownBackstopInterval * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil ||
        !BCOVShouldCompletePlayerTearDown(
            token, strongSelf->_teardownToken, strongSelf->_teardownPending)) {
      return;
    }
    NSLog(@"BrightcovePlayerView: a player feature claimed teardown but did not "
           "complete it within %.1fs; forcing teardown",
          kBCOVTearDownBackstopInterval);
#if DEBUG
    NSAssert(NO, @"A feature returned YES from -prepareForPlayerTearDown: without "
                 @"invoking the completion block within the backstop interval.");
#endif
    [strongSelf completePlayerTearDown];
  });
}

- (void)completePlayerTearDown
{
  if (!_teardownPending) {
    return;
  }
  _teardownPending = NO;
  _playbackController.delegate = nil;
  if (_playerView != nil) {
    _playerView.delegate = nil;
  }
  [_playbackController pause];
  _playerView.playbackController = nil;
  self.contentView = nil;
  _playerView = nil;
  _playbackController = nil;
  _currentSession = nil;
  _isPlaying = NO;
  _playbackRequested = NO;
  _resumeWhenAttached = NO;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onPlayerTearDown)]) {
      [feature onPlayerTearDown];
    }
  }
  if (_invalidated) {
    [super invalidate];
  } else if (_sourceDirty) {
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf == nil || strongSelf->_invalidated) {
        return;
      }
      // Source teardown can complete synchronously from updateProps, before
      // the new C++ props have been copied into _accountId/_videoId. Defer the
      // re-application one main-queue turn so it always reads the final props
      // for that transaction.
      [strongSelf ensurePlayer];
      [strongSelf applyPendingConfiguration];
    });
  }
}

// muted is bridge-level state, not a native SDK concept — AVPlayer only has
// volume — so muting applies 0 while remembering the caller's volume;
// unmuting restores it. A no-op if no session exists yet (e.g. before the
// first source is ready); the Ready path re-applies once one does.
- (void)applyVolume
{
  AVPlayer *player = _currentSession.player;
  if (player == nil) {
    return;
  }
  player.volume = _muted ? 0.0f : (float)_volume;
}

- (void)ensurePlayer
{
  if (_playerView != nil || _invalidated || self.window == nil) {
    return;
  }
  // Wait for a real layout before creating the player. A feature can capture
  // the ad container at creation time (ads: IMA renders into and sizes its ad
  // request against contentOverlayView), and Fabric may run finalizeUpdates /
  // didMoveToWindow before it has laid this view out — binding IMA to a 0x0
  // container makes the ad silently never render (black screen, no ad events).
  // layoutSubviews calls ensurePlayer again once bounds are real.
  if (CGRectIsEmpty(self.bounds)) {
    return;
  }

  UIViewController *presentingViewController = [self reactViewController];
  if (presentingViewController == nil) {
    [self emitConfigurationError:@"BrightcovePlayerView requires a presenting view controller"];
    return;
  }

  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];

  BCOVPUIPlayerViewOptions *options = [BCOVPUIPlayerViewOptions new];
  options.presentingViewController = presentingViewController;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(configurePlayerViewOptions:)]) {
      [feature configurePlayerViewOptions:options];
    }
  }

  // Create the player view first, with a nil controller. Some features (ads:
  // IMA) build a session provider that needs the player view's adContainer
  // (contentOverlayView) and presenting view controller, and the controller
  // must in turn be built *from* that composed session-provider chain — a
  // cycle. BCOVPUIPlayerView permits a nil controller at init and having the
  // controller assigned later, which breaks the cycle: create the view, let
  // features contribute providers (now that the ad container exists), build the
  // controller from the chain, then attach it below.
  _playerView = [[BCOVPUIPlayerView alloc] initWithPlaybackController:nil
                                                              options:options];
  // The SDK routes AVPictureInPictureController delegate callbacks through
  // BCOVPUIPlayerViewDelegate; the core forwards them to the features.
  _playerView.delegate = self;
  self.contentView = _playerView;

  // Give the player view (and therefore its contentOverlayView) a real size
  // BEFORE composing the session-provider chain. Fabric sizes the mounted view
  // via updateLayoutMetrics, but self.contentView has not been laid out yet at
  // this point in the update, so its subviews are still 0x0 — and a feature
  // that captures the ad container here (ads: IMA renders into
  // contentOverlayView) would bind a zero-sized view, producing a black screen
  // with no visible content or ad. Sizing the player view to the host bounds
  // and forcing a layout pass makes contentOverlayView a real rectangle before
  // it is handed to IMA.
  _playerView.frame = self.bounds;
  [_playerView layoutIfNeeded];

  // Compose the session-provider chain: each feature receives the upstream
  // provider assembled so far (nil for the first contributor) and returns one
  // that wraps it, or nil to add none. This is how a feature influences how
  // content is *loaded* (ads insert an IMA provider, DRM/offline a FairPlay provider)
  // without the core knowing about any concrete feature. With no contributor
  // the chain is empty and a plain controller is used, so non-ads/DRM samples
  // are byte-for-byte unaffected.
  NSUInteger fairPlayProviders = 0;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(providesFairPlaySessionProvider)] &&
        [feature providesFairPlaySessionProvider]) {
      fairPlayProviders++;
    }
  }
  if (fairPlayProviders > 1) {
    [NSException raise:NSInternalInconsistencyException
                format:@"Multiple player features contributed FairPlay session providers. Exactly one FairPlay provider is permitted in the playback controller chain."];
  }

  id<BCOVPlaybackSessionProvider> sessionProvider = nil;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(sessionProviderWithUpstream:)]) {
      id<BCOVPlaybackSessionProvider> contributed =
          [feature sessionProviderWithUpstream:sessionProvider];
      if (contributed != nil) {
        sessionProvider = contributed;
      }
    }
  }

  if (sessionProvider != nil) {
    _playbackController =
        [sdkManager createPlaybackControllerWithSessionProvider:sessionProvider
                                                   viewStrategy:nil];
  } else {
    _playbackController = [sdkManager createPlaybackController];
  }
  _playbackController.delegate = self;
  // A new controller is created on every source change (see tearDownPlayer /
  // sourceChanged above), so playbackRate must be re-applied here too, not
  // just in updateProps — otherwise a rate set before this source would be
  // lost the moment the controller is rebuilt.
  _playbackController.playbackRate = _playbackRate;
  // With a feature that manages its own start (ads: IMA coordinates ad->content
  // via the controller's autoPlay), let the controller start playback so the
  // core does not race the feature's async setup by calling -play on Ready.
  // Otherwise the core keeps full control and drives playback itself.
  _playbackController.autoPlay = [self featureManagedPlayback] ? _autoPlay : NO;
  // Lets the SDK's own queue advance to the next session when the previous
  // one ends, matching Android's ExoPlayer concatenated-source behavior. A
  // no-op for a single-video source (nothing to advance to). Disabled while
  // `loop` is on: `loop` is documented as single-video repeat (not playlist
  // repeat-all), so the SDK must not advance to the next queued item while the
  // core is restarting the finished one — otherwise the two race on the same
  // player. Playlists owns queue repetition through repeatMode instead.
  _playbackController.autoAdvance = BCOVShouldAutoAdvance(_loop);
  _playerView.playbackController = _playbackController;

  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(configurePlaybackController:)]) {
      [feature configurePlaybackController:_playbackController];
    }
  }

  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onPlayerCreated)]) {
      [feature onPlayerCreated];
    }
  }
}

- (void)applyPendingConfiguration
{
  if (!_sourceDirty || _playerView == nil || _invalidated || _teardownPending) {
    return;
  }

  id<BrightcovePlayerFeature> sourceLoader = nil;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(claimsSourceLoading)] && [feature claimsSourceLoading]) {
      if (sourceLoader != nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Multiple player features claimed the current source"];
      }
      sourceLoader = feature;
    }
  }
  if (sourceLoader != nil && _videoId.length > 0) {
    [self emitConfigurationError:@"videoId and a feature-owned source (offlineSourceId/videoIds) are mutually exclusive; set only one"];
    _sourceDirty = NO;
    return;
  }
  // Catalog credentials are only the core's business for its own single-video
  // path: a source-owning feature decides what its mode needs (DirectUrl
  // needs none — the doc contract says credentials are ignored for it — while
  // reference/playlist modes require both).
  if ((sourceLoader == nil && _accountId.length == 0) ||
      (sourceLoader == nil && _policyKey.length == 0) ||
      (sourceLoader == nil && _videoId.length == 0)) {
    [self emitConfigurationError:@"accountId, policyKey, and videoId are required for an online source"];
    _sourceDirty = NO;
    return;
  }
  if (sourceLoader == nil && !BCOVStringContainsOnlyDigits(_accountId)) {
    [self emitConfigurationError:@"accountId must contain only digits"];
    _sourceDirty = NO;
    return;
  }
  if (sourceLoader == nil && !BCOVStringContainsOnlyDigits(_videoId)) {
    [self emitConfigurationError:@"videoId must contain only digits"];
    _sourceDirty = NO;
    return;
  }

  _sourceDirty = NO;
  _lastConfigurationError = nil;
  _readyEmitted = NO;
  _featureReadyVideoId = nil;
  _sessionReady = NO;
  _sourceFailed = NO;

  NSUInteger generation = _requestGeneration;
  NSString *requestedAccountId = [_accountId copy];
  NSString *requestedPolicyKey = [_policyKey copy];
  NSString *requestedVideoId = [_videoId copy];

  if (sourceLoader != nil) {
    [sourceLoader loadSource:generation
                    accountId:requestedAccountId
                    policyKey:requestedPolicyKey];
    return;
  }

  // Analytics account attribution: unlike Android (where we must call
  // videoView.analytics.setAccount), iOS needs no explicit setter. The
  // BCOVVideo returned by BCOVPlaybackService carries the account, and the SDK
  // analytics beacon reads it from the played video automatically — the same
  // pattern as the native VideoCloudBasicPlayer sample, which sets nothing.
  _playbackService = [[BCOVPlaybackService alloc] initWithAccountId:requestedAccountId
                                                           policyKey:requestedPolicyKey];

  // Merge the query parameters every feature wants on the Playback API request
  // (SSAI adds the ad-config id here). The core stays agnostic about which
  // feature or why; nil is returned as no parameters.
  NSMutableDictionary<NSString *, NSString *> *queryParameters = [NSMutableDictionary dictionary];
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(additionalSourceQueryParameters)]) {
      NSDictionary<NSString *, NSString *> *params = [feature additionalSourceQueryParameters];
      if (params.count > 0) {
        [queryParameters addEntriesFromDictionary:params];
      }
    }
    // Tell ad features which video this load targets before it starts, so
    // ad-lifecycle events can be scoped to the current source (Android's
    // onSourceLoading hook, the iOS counterpart).
    if ([feature respondsToSelector:@selector(onSourceLoading:)]) {
      [feature onSourceLoading:requestedVideoId];
    }
  }

  __weak __typeof(self) weakSelf = self;
  [_playbackService findVideoWithConfiguration:@{
    [BCOVPlaybackService ConfigurationKeyAssetID]: requestedVideoId
  }
                                 queryParameters:queryParameters.count > 0 ? queryParameters : nil
                                      completion:^(BCOVVideo *video, id jsonResponse, NSError *error) {
    void (^handleCompletion)(void) = ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf == nil || strongSelf->_invalidated ||
          generation != strongSelf->_requestGeneration ||
          ![requestedVideoId isEqualToString:strongSelf->_videoId]) {
        return;
      }

      if (error != nil) {
        [strongSelf emitError:error];
        return;
      }
      if (video == nil) {
        [strongSelf emitErrorCategory:@"unknown"
                           nativeCode:@"playback_service_empty_response"
                              message:@"Brightcove returned neither a video nor an error"];
        return;
      }

#if TARGET_OS_SIMULATOR
      if (video.usesFairPlay) {
        [strongSelf emitErrorCategory:@"not_playable"
                           nativeCode:@"fairplay_requires_device"
                              message:@"FairPlay video cannot play in the iOS Simulator"];
        return;
      }
#endif

      BCOVVideo *taggedVideo = [video update:^(BCOVMutableVideo *mutableVideo) {
        NSMutableDictionary *properties = [mutableVideo.properties mutableCopy];
        properties[BCOVBridgeRequestGenerationKey] = @(generation);
        mutableVideo.properties = properties;
      }];
      // Let features transform the video before it is set (ads stamps the VMAP
      // ad-tag property the IMA plugin reads). Each returns the video to use;
      // returning the input unchanged is the no-op default.
      for (id<BrightcovePlayerFeature> feature in strongSelf->_features) {
        if ([feature respondsToSelector:@selector(willSetVideo:)]) {
          BCOVVideo *transformed = [feature willSetVideo:taggedVideo];
          if (transformed != nil) {
            taggedVideo = transformed;
          }
        }
      }
      [strongSelf->_playbackController setVideos:@[ taggedVideo ]];
    };

    if (NSThread.isMainThread) {
      handleCompletion();
    } else {
      dispatch_async(dispatch_get_main_queue(), handleCompletion);
    }
  }];
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
            playbackSession:(id<BCOVPlaybackSession>)session
   didReceiveLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
{
  // Forward every lifecycle event to features before the core's own
  // video-generation guard. Ad (IMA) lifecycle events arrive here too, and a
  // feature that reacts to them (ads, PiP) must see them regardless of the core's
  // content-source bookkeeping; the ads feature applies its own relevance
  // checks.
  if ([self isCurrentPlaybackSession:session]) {
    for (id<BrightcovePlayerFeature> feature in _features) {
      if ([feature respondsToSelector:@selector(sourceErrorForLifecycleEvent:session:)]) {
        NSError *sourceError = [feature sourceErrorForLifecycleEvent:lifecycleEvent session:session];
        if (sourceError != nil) {
          [self emitError:sourceError];
          return;
        }
      }
    }
  }

  if (controller != _playbackController || ![self isCurrentPlaybackSession:session]) {
    return;
  }

  NSString *eventType = lifecycleEvent.eventType;
  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPlay]) {
    _isPlaying = YES;
    _playbackRequested = YES;
    if (_networkRecoveryInProgress) {
      _networkRecoveryInProgress = NO;
      _networkRecoveryError = nil;
      for (id<BrightcovePlayerFeature> feature in _features) {
        if ([feature respondsToSelector:@selector(onNetworkRecoveryEnded)]) {
          [feature onNetworkRecoveryEnded];
        }
      }
    }
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventPause] ||
             [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventTerminate]) {
    _isPlaying = NO;
    _playbackRequested = NO;
  } else if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventEnd]) {
    _isPlaying = NO;
    _playbackRequested = NO;

    AVQueuePlayer *player = session.player;
    if (_loop && player != nil) {
      NSUInteger generation = _requestGeneration;
      NSString *videoId = [_videoId copy];
      __weak __typeof(self) weakSelf = self;
      [player seekToTime:CMTimeMake(0, 1) completionHandler:^(BOOL finished) {
        if (!finished) {
          return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
          __strong __typeof(weakSelf) strongSelf = weakSelf;
          if (strongSelf == nil || strongSelf->_invalidated || strongSelf->_sourceFailed || !strongSelf->_loop ||
              generation != strongSelf->_requestGeneration ||
              ![videoId isEqualToString:strongSelf->_videoId] ||
              player != session.player) {
            return;
          }

          [player play];
        });
      }];
    }
  }

  // Forward the lifecycle event to features (playback-events maps play/pause/end
  // to JS). Placed after the generation guard so features only see events for
  // the current source — playback-events does not itself filter by generation,
  // so it relies on the core to gate stale sessions here.
  //
  // NOTE for the ads feature merge: ads needs lifecycle events even for sessions
  // the core treats as stale (ad sessions carry different generation semantics)
  // and does its own relevance filtering, so on the ads branch this forward runs
  // BEFORE the guard. Reconciling the two branches means moving this forward
  // before the guard AND giving playback-events its own current-source check, so
  // it does not emit play/pause for an outgoing video.
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onLifecycleEvent:session:)]) {
      [feature onLifecycleEvent:lifecycleEvent session:session];
    }
  }

  NSString *sessionVideoId = session.video.properties[[BCOVVideo PropertyKeyId]];
  BOOL featureOwnsSource = NO;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(claimsSourceLoading)] && [feature claimsSourceLoading]) {
      featureOwnsSource = YES;
      break;
    }
  }

  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventReady]) {
    if (_sourceFailed) {
      return;
    }

    // Every new session — including auto-advance within a queue, where
    // onReady was already emitted for the first item — must become
    // _currentSession and re-apply session-scoped state, or volume/muted/
    // scaling later target the terminated session's player.
    _currentSession = session;
    _playbackController.playbackRate = _playbackRate;
    [self applyVolume];
    [self applyVideoScalingModeToSession:session];

    if (_readyEmitted) {
      // A later session in the same source (queue auto-advance, preloaded
      // handoff): the JS onReady event stays once-per-source, but every
      // session-scoped feature must still rebind to the new session —
      // captions, quality, timed metadata, ... observe the session's player
      // and would otherwise keep reporting item one's state. Each
      // implementer clears or replaces its prior session state first.
      [self notifyFeaturesSessionReady:session];
      return;
    }

    _readyEmitted = YES;
    _sessionReady = YES;
    // Re-apply playbackRate on controller and session's AVPlayer, and apply
    // volume/muted before onReady so both platforms expose the requested
    // playback state to an onReady handler.
    [self emitReady:featureOwnsSource ? (_featureReadyVideoId ?: sessionVideoId) : _videoId];
    [self notifyFeaturesSessionReady:session];
    // When a feature manages the start (ads/IMA), the controller's own autoPlay
    // begins playback and coordinates the ad->content transition; calling -play
    // here would race that and wedge the pre-roll. Otherwise the core starts
    // playback itself.
    if (_autoPlay && ![self featureManagedPlayback]) {
      [self requestPlaybackWhenAttached];
    }
    return;
  }

  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventResumeComplete]) {
    if (_networkRecoveryInProgress) {
      _networkRecoveryInProgress = NO;
      _networkRecoveryError = nil;
      for (id<BrightcovePlayerFeature> feature in _features) {
        if ([feature respondsToSelector:@selector(onNetworkRecoveryEnded)]) {
          [feature onNetworkRecoveryEnded];
        }
      }
    }
    return;
  }
  if ([eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventResumeFail]) {
    if (_networkRecoveryInProgress) {
      _networkRecoveryInProgress = NO;
      for (id<BrightcovePlayerFeature> feature in _features) {
        if ([feature respondsToSelector:@selector(onNetworkRecoveryEnded)]) {
          [feature onNetworkRecoveryEnded];
        }
      }
    }
    // Consume the recovery error here, exactly as the ResumeComplete path does.
    // The report below falls back to it for THIS failure; leaving it set lets a
    // later, unrelated failure with a nil error be mislabeled with this
    // attempt's code/nativeCode.
    NSError *resumeError = lifecycleEvent.properties[kBCOVPlaybackSessionEventKeyError];
    NSError *recoveryError = _networkRecoveryError;
    _networkRecoveryError = nil;
    NSError *reportedError = resumeError ?: recoveryError ?: [NSError errorWithDomain:@"BrightcovePlayer" code:1 userInfo:@{
      NSLocalizedDescriptionKey: @"Brightcove playback recovery failed",
    }];
    if (!_sessionReady) {
      [self deferPlaybackError:reportedError];
    } else {
      [self emitError:reportedError];
    }
    return;
  }

  BOOL isFailure = [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFail] ||
      [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventError] ||
      [eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFailedToPlayToEndTime];
  if (isFailure) {
    NSError *error = lifecycleEvent.properties[kBCOVPlaybackSessionEventKeyError];
    if ([self attemptNetworkRecoveryForError:error]) {
      return;
    }
    NSError *reportedError = error ?: _networkRecoveryError ?: [NSError errorWithDomain:@"BrightcovePlayer" code:1 userInfo:@{
      NSLocalizedDescriptionKey: @"Brightcove playback failed",
    }];
    [self emitError:reportedError];
  }
}

- (BOOL)attemptNetworkRecoveryForError:(NSError *)error
{
  if (_networkRecoveryInProgress || !_sessionReady || !_playbackRequested || error == nil) {
    return NO;
  }
  if (![BCOVErrorCategory(error) isEqualToString:@"network"] || _currentSession == nil) {
    return NO;
  }
  id<BCOVPlaybackSession> session = _currentSession;
  AVPlayer *player = session.player;
  if (player == nil) {
    return NO;
  }
  _networkRecoveryInProgress = YES;
  _networkRecoveryError = error;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onNetworkRecoveryStarted)]) {
      [feature onNetworkRecoveryStarted];
    }
  }
  CMTime currentTime = player.currentTime;
  [_playbackController resumeVideoAtTime:currentTime withAutoPlay:YES];
  return YES;
}

- (void)applyVideoScalingModeToSession:(id<BCOVPlaybackSession>)session
{
  AVPlayerLayer *playerLayer = session.playerLayer;
  if (playerLayer == nil) {
    return;
  }

  playerLayer.videoGravity = [_videoScalingMode isEqualToString:@"fill"]
      ? AVLayerVideoGravityResizeAspectFill
      : AVLayerVideoGravityResizeAspect;
}

// The SDK's queue advanced to a new session — natural end-of-item or an
// explicit advanceToNext. The core does not itself model a queue beyond the
// current source; forward verbatim so a feature that inserted extra videos
// into the controller's own queue (preloading) can react. Forwarded without
// the core's own isCurrentPlaybackSession gate: features guard themselves
// (playlists matches the session's generation tag and original index;
// preloading compares its queued id), and the core's own per-session state
// is re-pointed in the Ready lifecycle handler, which does run gated.
- (void)playbackController:(id<BCOVPlaybackController>)controller
    didAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onDidAdvanceToPlaybackSession:)]) {
      [feature onDidAdvanceToPlaybackSession:session];
    }
  }
}
- (void)playbackController:(id<BCOVPlaybackController>)controller
            playbackSession:(id<BCOVPlaybackSession>)session
          didPassCuePoints:(NSDictionary *)cuePointInfo
{
  // One identity rule shared with determinedVideoType and
  // noPlayableVideosFound (see BCOVVideoIdentity): a current-generation tag
  // names this request's content — including a feature-inserted preloaded
  // item whose id differs from the videoId prop — and an untagged video
  // falls back to the videoId prop check.
  if (!BCOVVideoIsCurrentRequest(session.video, _requestGeneration)) {
    return;
  }

  NSValue *previousValue = cuePointInfo[kBCOVPlaybackSessionEventKeyPreviousTime];
  NSValue *currentValue = cuePointInfo[kBCOVPlaybackSessionEventKeyCurrentTime];
  BCOVCuePointCollection *cuePoints = cuePointInfo[kBCOVPlaybackSessionEventKeyCuePoints];
  if (![previousValue isKindOfClass:NSValue.class] ||
      ![currentValue isKindOfClass:NSValue.class] ||
      ![cuePoints isKindOfClass:BCOVCuePointCollection.class]) {
    return;
  }
  CMTime previousTime = previousValue.CMTimeValue;
  CMTime currentTime = currentValue.CMTimeValue;
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onCuePoints:previousTime:currentTime:)]) {
      [feature onCuePoints:cuePoints previousTime:previousTime currentTime:currentTime];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
      noPlayableVideosFound:(NSArray<BCOVVideo *> *)unplayableVideos
{
  BCOVVideo *video = unplayableVideos.firstObject;
  // One identity rule shared with the cue-point and video-type guards (see
  // BCOVVideoIdentity).
  if (BCOVVideoIsCurrentRequest(video, _requestGeneration)) {
    [self emitErrorCategory:@"not_playable"
                 nativeCode:@"no_playable_video"
                    message:@"Brightcove found no playable source"];
  }
}

// Fires once after the last item in an autoAdvance queue finishes. Only
// meaningful for a queue-loading feature (playlists); a single-video source
// has nothing after it to advance from.
- (void)playbackController:(id<BCOVPlaybackController>)controller
        didCompletePlaylist:(NSArray<BCOVVideo *> *)playlist
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onCompletedPlaylist:)]) {
      [feature onCompletedPlaylist:playlist];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
        failedToInsertVideo:(BCOVVideo *)video
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onFailedToInsertVideo:)]) {
      [feature onFailedToInsertVideo:video];
    }
  }
}
// The SDK calls this whenever the legible (caption) track changes, whether from
// the player's own controls or a programmatic setter. Forward it to features so
// a caption change made through the native UI is reported to JS, not just
// prop-driven changes. Mirrors Android's SELECT_CLOSED_CAPTION_TRACK path.
//
// Guarded by the same generation/video-id check as the lifecycle-event handler
// and noPlayableVideosFound above: the SDK is a multi-session, queue-based
// architecture (the reason those other callbacks are guarded), so a callback
// for the outgoing session can in principle still be queued when a source
// change lands. Without this guard a stale callback for the previous source
// would resolve against the freshly-rebuilt _options for the NEW source (see
// BrightcoveCaptionsFeature), fail to match, and silently revert a just-applied
// legitimate selection on the new video back to "off".
- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
didChangeExternalPlaybackActive:(BOOL)externalPlaybackActive
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }

  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onExternalPlaybackChanged:)]) {
      [feature onExternalPlaybackChanged:externalPlaybackActive];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
     didChangeSelectedLegibleMediaOption:(AVMediaSelectionOption *)legibleMediaOption
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onSelectedLegibleMediaOption:)]) {
      [feature onSelectedLegibleMediaOption:legibleMediaOption];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
    didChangeSelectedAudibleMediaOption:(AVMediaSelectionOption *)audibleMediaOption
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onSelectedAudibleMediaOption:)]) {
      [feature onSelectedAudibleMediaOption:audibleMediaOption];
    }
  }
}

// Forward playback progress to features. The core does not model progress
// itself; a feature that reports position (playback-events) reads it here.
// Progress fires only for the controller's current session, and a stale late
// callback is harmless (a feature that cares tracks its own source lifecycle
// via onSourceReset), so no extra generation guard is needed here.
- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
              didProgressTo:(NSTimeInterval)progress
{
  if (controller != _playbackController || ![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onDidProgressTo:)]) {
      [feature onDidProgressTo:progress];
    }
  }
}

// The SDK determined the video's type (VOD / Live / Live-DVR). Forward it so a
// feature can react to live content; the core does not branch on video type.
- (void)playbackController:(id<BCOVPlaybackController>)controller
       determinedVideoType:(BCOVVideoType)videoType
                  forVideo:(BCOVVideo *)video
{
  if (controller != _playbackController) {
    return;
  }
  // One identity rule shared with the cue-point and no-playable guards (see
  // BCOVVideoIdentity): a preloaded next item carrying the current
  // generation tag is classified too, while a stale tag is rejected.
  if (!BCOVVideoIsCurrentRequest(video, _requestGeneration)) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onDeterminedVideoType:forVideo:)]) {
      [feature onDeterminedVideoType:videoType forVideo:video];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
    didChangeSeekableRanges:(NSArray *)seekableRanges
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onSeekableRangesChanged:session:)]) {
      [(id)feature onSeekableRangesChanged:seekableRanges session:session];
    }
  }
}

#pragma mark BCOVPlaybackControllerAdsDelegate

// The SDK's typed ad-observation channel. SSAI's server-stitched ads are
// reported here (carrying the BCOVAd directly), so the core forwards these to
// features. The core itself models no ad state — it just relays.

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
        didEnterAdSequence:(BCOVAdSequence *)adSequence
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onEnterAdSequence)]) {
      [feature onEnterAdSequence];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
         didExitAdSequence:(BCOVAdSequence *)adSequence
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onExitAdSequence)]) {
      [feature onExitAdSequence];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
                didEnterAd:(BCOVAd *)ad
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onEnterAd:)]) {
      [feature onEnterAd:ad];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
                 didExitAd:(BCOVAd *)ad
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onExitAd:)]) {
      [feature onExitAd:ad];
    }
  }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller
           playbackSession:(id<BCOVPlaybackSession>)session
                        ad:(BCOVAd *)ad
            didProgressTo:(NSTimeInterval)progress
{
  if (![self isCurrentPlaybackSession:session]) {
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onAdProgress:progress:)]) {
      [feature onAdProgress:ad progress:progress];
    }
  }
}
- (void)playerView:(BCOVPUIPlayerView *)playerView
    willTransitionToScreenMode:(BCOVPUIScreenMode)screenMode
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onScreenModeWillChange:)]) {
      [feature onScreenModeWillChange:screenMode];
    }
  }
}

- (void)playerView:(BCOVPUIPlayerView *)playerView
    didTransitionToScreenMode:(BCOVPUIScreenMode)screenMode
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onScreenModeChanged:)]) {
      [feature onScreenModeChanged:screenMode];
    }
  }
}

#pragma mark BCOVPUIPlayerViewDelegate (Picture-in-Picture pass-throughs)

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(pictureInPictureDidStart)]) {
      [feature pictureInPictureDidStart];
    }
  }
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(pictureInPictureDidStop)]) {
      [feature pictureInPictureDidStop];
    }
  }
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    failedToStartPictureInPictureWithError:(NSError *)error
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(pictureInPictureFailedToStartWithError:)]) {
      [feature pictureInPictureFailedToStartWithError:error];
    }
  }
}

- (void)didSetVideo360NavigationMethod:(BCOVPUIVideo360NavigationMethod)navigationMethod
                       projectionStyle:(BCOVVideo360ProjectionStyle)projectionStyle
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(didSetVideo360NavigationMethod:projectionStyle:)]) {
      [feature didSetVideo360NavigationMethod:navigationMethod projectionStyle:projectionStyle];
    }
  }
}

#pragma mark -

// YES when a registered feature drives playback through the controller's own
// autoPlay (ads/IMA). The core then does not call -play on the Ready event.
- (BOOL)featureManagedPlayback
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(requiresControllerManagedPlayback)] &&
        [feature requiresControllerManagedPlayback]) {
      return YES;
    }
  }
  return NO;
}

// Forward a session-scoped rebind to every feature: called for every Ready
// lifecycle event of the current source, including later sessions inside one
// queue (auto-advance, preloaded handoff), where the JS onReady latch must not
// refire but the features' observers still target the new session's player.
- (void)notifyFeaturesSessionReady:(id<BCOVPlaybackSession>)session
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onSessionReady:)]) {
      [feature onSessionReady:session];
    }
  }
}

- (BOOL)keepsPlaybackAliveInBackground
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(keepsPlaybackAliveInBackground)] &&
        [feature keepsPlaybackAliveInBackground]) {
      return YES;
    }
  }
  return NO;
}

- (void)requestPlaybackWhenAttached
{
  if (self.window == nil) {
    _resumeWhenAttached = YES;
  } else {
    _resumeWhenAttached = NO;
    _playbackRequested = YES;
    [_playbackController play];
  }
}

#pragma mark Imperative player commands

- (BOOL)handleInstalledFeatureCommand:(NSString *)command
{
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(supportedCommands)] &&
        [[feature supportedCommands] containsObject:command] &&
        [feature respondsToSelector:@selector(handleCommand:)]) {
      return [feature handleCommand:command];
    }
  }
  return NO;
}

- (void)handleCommand:(NSString *)command
{
  if (_invalidated) {
    return;
  }
  if (!NSThread.isMainThread) {
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf != nil && !strongSelf->_invalidated) {
        [strongSelf handleCommand:command];
      }
    });
    return;
  }
  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(supportedCommands)] &&
        [[feature supportedCommands] containsObject:command]) {
      if ([feature respondsToSelector:@selector(handleCommand:)]) {
        // A feature that advertises a command but cannot act on it returns
        // NO; the command contract requires that failure to reach
        // onPlayerCommandError rather than vanish. Features that handle the
        // command fully (including by emitting their own typed error — PiP,
        // fullscreen) return YES.
        if (![feature handleCommand:command]) {
          [self emitCommandErrorForCommand:command
                                       code:@"invalid_state"
                                    message:[NSString stringWithFormat:@"The '%@' command cannot run in the player's current state", command]
                                 nativeCode:@"command_preconditions_not_met"];
        }
        return;
      }
    }
  }

  [self emitCommandErrorForCommand:command
                              code:@"feature_not_installed"
                           message:[NSString stringWithFormat:@"The '%@' command requires a player feature that is not included in this bridge copy", command]
                        nativeCode:@"feature_not_installed"];
}

- (BOOL)ensureCommandReady:(NSString *)command
{
  if (_invalidated) {
    return NO;
  }
  if (_sourceFailed) {
    [self emitCommandErrorForCommand:command
                                code:@"invalid_state"
                             message:[NSString stringWithFormat:@"Cannot execute '%@': the current source failed", command]
                          nativeCode:@"source_failed"];
    return NO;
  }
  if (_playbackController == nil || !_sessionReady) {
    [self emitCommandErrorForCommand:command
                                code:@"not_ready"
                             message:[NSString stringWithFormat:@"Cannot execute '%@': the player source is not ready", command]
                          nativeCode:@"source_not_ready"];
    return NO;
  }
  return YES;
}

- (void)play
{
  if (![self ensureCommandReady:@"play"]) {
    return;
  }
  if ([self handleInstalledFeatureCommand:@"play"]) {
    _playbackRequested = YES;
    return;
  }
  [self requestPlaybackWhenAttached];
}

- (void)pause
{
  if (![self ensureCommandReady:@"pause"]) {
    return;
  }
  _playbackRequested = NO;
  _resumeWhenAttached = NO;
  if ([self handleInstalledFeatureCommand:@"pause"]) {
    return;
  }
  [_playbackController pause];
}

// positionSeconds uses the same unit as the playback lifecycle events. The
// native SDK receives a millisecond-scale CMTime on iOS and milliseconds on
// Android.
- (void)seekTo:(double)positionSeconds
{
  NSString *validationError = BCOVSeekPositionError(positionSeconds);
  if (validationError != nil) {
    [self emitCommandErrorForCommand:@"seekTo"
                                code:@"invalid_argument"
                             message:validationError
                          nativeCode:@"invalid_seek_position"];
    return;
  }
  if (![self ensureCommandReady:@"seekTo"]) {
    return;
  }
  CMTime time = CMTimeMakeWithSeconds(positionSeconds, 1000);
  if (!CMTIME_IS_VALID(time)) {
    [self emitCommandErrorForCommand:@"seekTo"
                                code:@"invalid_argument"
                             message:@"positionSeconds cannot be represented by the player"
                          nativeCode:@"invalid_seek_position"];
    return;
  }
  NSUInteger generation = _requestGeneration;
  NSUInteger seekToken = ++_seekRequestToken;
  __weak __typeof(self) weakSelf = self;
  [_playbackController seekToTime:time completionHandler:^(BOOL finished) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf == nil || strongSelf->_invalidated ||
          generation != strongSelf->_requestGeneration ||
          seekToken != strongSelf->_seekRequestToken) {
        return;
      }
      if (!finished) {
        [strongSelf emitCommandErrorForCommand:@"seekTo"
                                         code:@"failed"
                                      message:@"The player interrupted the seek operation"
                                   nativeCode:@"seek_interrupted"];
      }
    });
  }];
}

- (void)reload
{
  if (_invalidated) {
    return;
  }
  [self requestSourceReload];
}

- (void)enterFullscreen
{
  [self handleCommand:@"enterFullscreen"];
}

- (void)exitFullscreen
{
  [self handleCommand:@"exitFullscreen"];
}

- (void)enterPictureInPicture
{
  [self handleCommand:@"enterPictureInPicture"];
}

- (void)emitCommandErrorForCommand:(NSString *)command
                              code:(NSString *)code
                           message:(NSString *)message
                        nativeCode:(NSString *)nativeCode
{
  if (_invalidated) {
    return;
  }
  auto eventEmitter = std::dynamic_pointer_cast<const BrightcovePlayerViewEventEmitter>(_eventEmitter);
  if (eventEmitter) {
    eventEmitter->onPlayerCommandError(BrightcovePlayerViewEventEmitter::OnPlayerCommandError{
      .command = BCOVStdStringFromNSString(command),
      .code = BCOVStdStringFromNSString(code),
      .message = BCOVStdStringFromNSString(message),
      .nativeCode = BCOVStdStringFromNSString(nativeCode),
    });
  }
}

- (void)emitReady:(NSString *)videoId
{
  auto eventEmitter = std::dynamic_pointer_cast<const BrightcovePlayerViewEventEmitter>(_eventEmitter);
  if (!eventEmitter) {
    [_pendingEvents addObject:@{
      BCOVPendingEventKindKey: BCOVPendingEventReadyKind,
      BCOVPendingEventGenerationKey: @(_requestGeneration),
      @"videoId": videoId ?: @"",
    }];
    return;
  }

  eventEmitter->onReady(BrightcovePlayerViewEventEmitter::OnReady{
    .videoId = BCOVStdStringFromNSString(videoId),
  });
}

- (void)emitError:(NSError *)error
{
  NSString *nativeCode = BCOVNativeErrorCode(error);
  [self emitErrorCategory:BCOVErrorCategory(error)
               nativeCode:nativeCode
                  message:error.localizedDescription];
}

- (void)deferPlaybackError:(NSError *)error
{
  _pendingPlaybackError = error;
  NSUInteger token = ++_pendingPlaybackErrorToken;
  // Snapshot the request generation the error belongs to: a source swap in
  // the next main-loop turn (requestSourceReload) bumps _requestGeneration
  // before the flush runs, and without the generation check the old source's
  // error would be attributed to the new source.
  NSUInteger generation = _requestGeneration;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!BCOVShouldFlushDeferredPlaybackError(
            generation,
            self->_requestGeneration,
            token,
            self->_pendingPlaybackErrorToken,
            self->_sourceFailed,
            self->_invalidated,
            self->_pendingPlaybackError != nil)) {
      return;
    }
    NSError *pending = self->_pendingPlaybackError;
    self->_pendingPlaybackError = nil;
    [self emitError:pending];
  });
}

- (void)emitConfigurationError:(NSString *)message
{
  if (![_lastConfigurationError isEqualToString:message]) {
    _lastConfigurationError = [message copy];
    [self emitErrorCategory:@"invalid_configuration"
                 nativeCode:@"invalid_configuration"
                    message:message];
  }
}

// Emits a bridge-side error that carried no NSError. Prefer the three-arg form
// with a specific nativeCode token (e.g. "fairplay_requires_device") so the
// diagnostic cause survives; this convenience overload, which reuses the
// category as nativeCode, is only for cases with genuinely no finer detail.
- (void)emitErrorCategory:(NSString *)category
                  message:(NSString *)message
{
  [self emitErrorCategory:category nativeCode:category message:message];
}

- (void)emitErrorCategory:(NSString *)category
                nativeCode:(NSString *)nativeCode
                   message:(NSString *)message
{
  _pendingPlaybackError = nil;
  _pendingPlaybackErrorToken += 1;
  if (_sourceFailed) {
    return;
  }

  if (_networkRecoveryInProgress) {
    _networkRecoveryInProgress = NO;
    _networkRecoveryError = nil;
    for (id<BrightcovePlayerFeature> feature in _features) {
      if ([feature respondsToSelector:@selector(onNetworkRecoveryEnded)]) {
        [feature onNetworkRecoveryEnded];
      }
    }
  }

  for (id<BrightcovePlayerFeature> feature in _features) {
    if ([feature respondsToSelector:@selector(onPlaybackError)]) {
      [feature onPlaybackError];
    }
  }

  _sourceFailed = YES;
  auto eventEmitter = std::dynamic_pointer_cast<const BrightcovePlayerViewEventEmitter>(_eventEmitter);
  if (!eventEmitter) {
    [_pendingEvents addObject:@{
      BCOVPendingEventKindKey: BCOVPendingEventErrorKind,
      BCOVPendingEventGenerationKey: @(_requestGeneration),
      @"code": category ?: @"unknown",
      @"message": message ?: @"Brightcove playback failed",
      @"nativeCode": nativeCode ?: @"unknown",
    }];
    return;
  }

  eventEmitter->onError(BrightcovePlayerViewEventEmitter::OnError{
    .code = BCOVStdStringFromNSString(category),
    .message = BCOVStdStringFromNSString(message),
    .nativeCode = BCOVStdStringFromNSString(nativeCode),
  });
}

- (void)flushPendingEvents
{
  if (_pendingEvents.count == 0) {
    return;
  }

  auto eventEmitter = std::dynamic_pointer_cast<const BrightcovePlayerViewEventEmitter>(_eventEmitter);
  if (!eventEmitter) {
    return;
  }

  NSArray<NSDictionary<NSString *, id> *> *pending = [_pendingEvents copy];
  [_pendingEvents removeAllObjects];
  for (NSDictionary<NSString *, id> *event in pending) {
    if ([event[BCOVPendingEventGenerationKey] unsignedIntegerValue] != _requestGeneration) {
      continue;
    }

    NSString *kind = event[BCOVPendingEventKindKey];
    if ([kind isEqualToString:BCOVPendingEventReadyKind]) {
      eventEmitter->onReady(BrightcovePlayerViewEventEmitter::OnReady{
        .videoId = BCOVStdStringFromNSString(event[@"videoId"]),
      });
    } else if ([kind isEqualToString:BCOVPendingEventErrorKind]) {
      eventEmitter->onError(BrightcovePlayerViewEventEmitter::OnError{
        .code = BCOVStdStringFromNSString(event[@"code"]),
        .message = BCOVStdStringFromNSString(event[@"message"]),
        .nativeCode = BCOVStdStringFromNSString(event[@"nativeCode"]),
      });
    }
  }
}

@end
