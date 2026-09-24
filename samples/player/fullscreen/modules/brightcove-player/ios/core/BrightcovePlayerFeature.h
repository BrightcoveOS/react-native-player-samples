#import <AVKit/AVKit.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <UIKit/UIKit.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * BCOVVideo.properties key the core (and any feature that resolves its own
 * catalog videos, e.g. playlists) stamps with the request generation active
 * when the video was resolved, so a stale async callback for a superseded
 * source can be told apart from the current one.
 */
static NSString *const BCOVBridgeRequestGenerationKey = @"com.brightcove.reactnativeplayer.requestGeneration";

/**
 * BCOVVideo.properties key a queue-loading feature (playlists) stamps with
 * each resolved item's position in the original videoIds array, since the
 * native SDK's own queue index can reorder (shuffle) or not directly expose
 * the caller's original ordering.
 */
static NSString *const BCOVBridgeOriginalIndexKey = @"com.brightcove.reactnativeplayer.originalIndex";

@protocol BrightcovePlayerFeature;

/**
 * What the core exposes to features. Deliberately narrow: features must not
 * reach into the core view's internals beyond this surface.
 */
@protocol BrightcovePlayerFeatureHost <NSObject>

@property (nonatomic, readonly, nullable) id<BCOVPlaybackController> playbackController;
@property (nonatomic, readonly, nullable) BCOVPUIPlayerView *playerView;
@property (nonatomic, readonly) UIView *hostView;
@property (nonatomic, readonly) BOOL isInvalidated;

/**
 * The current source's accountId/policyKey props, for a feature that needs
 * its own catalog lookup independent of the current source (preloading
 * resolves a different video while one already plays).
 */
@property (nonatomic, readonly, nullable) NSString *accountId;
@property (nonatomic, readonly, nullable) NSString *policyKey;
@property (nonatomic, readonly, nullable) NSString *videoId;

/** Whether a playback callback belongs to the currently requested source. */
- (BOOL)isCurrentPlaybackSession:(id<BCOVPlaybackSession>)session;

/** Whether a registered feature other than the caller provides the current FairPlay provider. */
- (BOOL)hasFeatureProvidingFairPlayExcludingFeature:(id<BrightcovePlayerFeature>)feature;

/** Whether a registered feature owns the current source load. */
- (BOOL)hasFeatureClaimingSourceLoading;
/**
 * The view controller presenting this player, used by features that must
 * present UI (ads: the IMA ad-container view controller). Nil until the player
 * has been created (it is resolved from the React view hierarchy).
 */
@property (nonatomic, readonly, nullable) UIViewController *presentingViewController;

/**
 * Whether the app is currently in the foreground (UIApplicationStateActive).
 * A feature that keeps playback alive in the background must consult this
 * before disabling itself: the core's own -didMoveToWindow pause path is
 * suppressed while keepsPlaybackAliveInBackground is YES, and it will not
 * run again just because a prop flipped. If the app is not active at the
 * moment such a feature is disabled, playback would otherwise keep running
 * with no background-audio session justifying it: the feature must pause it
 * directly.
 */
@property (nonatomic, readonly) BOOL isHostActive;

/** The typed Fabric event emitter; nil until the view is mounted. */
- (nullable std::shared_ptr<const facebook::react::BrightcovePlayerViewEventEmitter>)typedEventEmitter;

/**
 * Tear the player down and rebuild it on the next update pass, re-applying the
 * current source. For player-view options that are fixed at creation time
 * (e.g. showPictureInPictureButton).
 */
- (void)requestPlayerRebuild;

/** Mark the current source dirty after a source-owning feature prop changes. */
- (void)requestSourceReload;

/** True while requestGeneration still names the active source. */
- (BOOL)isCurrentRequest:(NSUInteger)requestGeneration;

/**
 * The generation of the source currently being loaded or played. A feature
 * inserting a video it resolved asynchronously (preloading) must tag it with
 * this generation at insert time — the load may have started under an older
 * one — or the core's lifecycle guards reject every event the inserted video
 * produces.
 */
@property (nonatomic, readonly) NSUInteger currentRequestGeneration;

/** Tag a feature-resolved video so the core accepts its lifecycle events. */
- (BCOVVideo *)taggedVideo:(BCOVVideo *)video forGeneration:(NSUInteger)requestGeneration;

/**
 * Tag a feature-resolved video AND fold it through every feature's
 * willSetVideo: — the same post-resolution pipeline the core's own catalog
 * path runs (ads stamps the VMAP property; sidecar captions inject tracks).
 * Source-owning features must hand their resolved videos through here so
 * their modes get identical treatment to the core path.
 */
- (BCOVVideo *)taggedAndTransformedVideo:(BCOVVideo *)video
                           forGeneration:(NSUInteger)requestGeneration;

/**
 * Tag a feature-resolved queue item with both its request generation and its
 * position in the original videoIds array (see BCOVBridgeOriginalIndexKey).
 * Used by a queue-loading feature (playlists) instead of the two-argument
 * -taggedVideo:forGeneration: so item-changed events report the caller's
 * original index rather than a native/shuffled queue position.
 */
- (BCOVVideo *)taggedVideo:(BCOVVideo *)video
              forGeneration:(NSUInteger)requestGeneration
              originalIndex:(NSUInteger)originalIndex;

/**
 * Report a feature-loaded playable source and reset ready/error state. The
 * explicit readyVideoId is authoritative because a persisted SDK Video may not
 * retain its public ID even though the feature knows its source.
 */
- (void)markVideoLoaded:(NSUInteger)requestGeneration readyVideoId:(NSString *)readyVideoId;

/** Emit the normalized terminal player error for a feature-owned source. */
- (void)emitSourceLoadError:(NSUInteger)requestGeneration
                       code:(NSString *)code
                 nativeCode:(NSString *)nativeCode
                    message:(NSString *)message;

/** Emit a typed command error direct event to JS. */
- (void)emitCommandErrorForCommand:(NSString *)command
                              code:(NSString *)code
                           message:(NSString *)message
                        nativeCode:(NSString *)nativeCode;

@end

/**
 * The contract between the core player view and an optional feature module
 * (captions, Picture-in-Picture, ads, DRM, ...).
 *
 * A feature is a self-contained directory next to core/ that a sample copies
 * only when it needs it. The sample's BrightcoveFeatureRegistry lists the
 * features its bridge copy contains; the core invokes every registered feature
 * through the hooks below and knows nothing about any concrete feature.
 */
@protocol BrightcovePlayerFeature <NSObject>

/**
 * The prop names this feature owns (e.g. "captionsEnabled"). The core routes
 * setProp calls for these names to this feature, and raises a descriptive
 * error if a non-default value arrives for a prop no registered feature owns.
 */
- (NSSet<NSString *> *)ownedProps;

/** Called once when the core view is created. */
- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host;

/**
 * A prop owned by this feature changed. Values are boxed (NSNumber for
 * booleans, NSString for strings).
 */
- (void)setProp:(NSString *)name value:(nullable id)value;

@optional

/** Supported command names (e.g. @"enterFullscreen", @"enterPictureInPicture"). */
- (NSSet<NSString *> *)supportedCommands;

/** Handle a command. Returns YES if handled. */
- (BOOL)handleCommand:(NSString *)command;

/** Whether this feature owns playback while the host app is backgrounded. */
- (BOOL)keepsPlaybackAliveInBackground;
/**
 * Contribute a playback session provider to the chain as the player is created.
 * Each feature receives the upstream provider assembled so far (nil for the
 * first contributor) and returns one that wraps it, or nil to add none. The
 * core builds the playback controller from the composed chain.
 *
 * This is how a feature influences how content is *loaded* rather than just
 * reacting to it: ads (IMA) wrap an IMA session provider here, DRM/offline wraps a
 * FairPlay provider. Called after the player view exists, so a feature that
 * needs the ad container (host.playerView.contentOverlayView) or the presenting
 * view controller (host.presentingViewController) can read them here. Kept
 * generic so the core never needs an ads- or DRM-specific hook.
 */
- (nullable id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (nullable id<BCOVPlaybackSessionProvider>)upstream;

/** The player view is being created; adjust its options. */
- (void)configurePlayerViewOptions:(BCOVPUIPlayerViewOptions *)options;

/** The playback controller and player view have been created. */
- (void)onPlayerCreated;
- (void)configurePlaybackController:(id<BCOVPlaybackController>)controller;

/**
 * Whether this feature needs the playback controller's own autoPlay to start
 * playback, instead of the core calling -play once the session is ready.
 *
 * Ads (IMA) returns YES: the IMA session provider coordinates the transition
 * between the ad and the content internally, and it only does so when the
 * controller drives the start (isAutoPlay). If the core instead calls -play on
 * the Ready event, that call races the asynchronous ads-manager load
 * (kBCOVIMALifecycleEventAdsLoaderLoaded); when Ready wins the race the pre-roll
 * never starts and the player is stuck on a black frame with no events. The
 * native BrightcoveIMA samples all use isAutoPlay for exactly this reason.
 *
 * When any registered feature returns YES the core sets the controller's
 * autoPlay from the autoPlay prop and does not call -play itself on Ready.
 * Defaults to NO, so samples with no such feature keep the core's own
 * play-on-Ready path unchanged.
 */
- (BOOL)requiresControllerManagedPlayback;

/** A new source is about to load: reset per-video state. */
- (void)onSourceReset;

/** True only while this feature owns the current player source. */
- (BOOL)claimsSourceLoading;

/** Whether this feature contributes a FairPlay session provider. */
- (BOOL)providesFairPlaySessionProvider;

/** Loads a feature-owned source instead of the core's online catalog fetch. */
- (void)loadSource:(NSUInteger)requestGeneration
          accountId:(NSString *)accountId
          policyKey:(NSString *)policyKey;

/**
 * Manual skip to the next item, from the `next` imperative command. Only
 * called on the feature for which -claimsSourceLoading returns YES. Returns
 * YES when the queue moved (or a move was scheduled for when resolution
 * completes); NO when nothing is loaded or the queue cannot move — the core
 * reports that through onPlayerCommandError per the command contract. The
 * native SDK's own queue is the single source of truth for whether advancing
 * is possible.
 */
- (BOOL)advanceQueue;

/**
 * Manual skip to the previous item, from the `previous` imperative command.
 * Only called on the feature for which -claimsSourceLoading returns YES.
 * Returns NO when nothing is loaded or the queue cannot move.
 */
- (BOOL)previousQueueItem;

/**
 * The playback controller advanced to a new session — either the native SDK
 * auto-advanced at end-of-item (autoAdvance) or -advanceQueue/-previousQueueItem
 * was called. Forwarded from the core's BCOVPlaybackControllerDelegate.
 * Playlists uses it to track the queue position and report the new current
 * item; preloading uses it to detect that its preloaded video has become the
 * one actually playing.
 */
- (void)onDidAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session;

/**
 * Fires once after the last item in an autoAdvance queue finishes playing.
 * Forwarded from the core's BCOVPlaybackControllerDelegate. Only meaningful
 * for a queue-loading feature; a single-video source never triggers it (there
 * is nothing after it to advance from).
 */
- (void)onCompletedPlaylist:(NSArray<BCOVVideo *> *)playlist;

/** The native queue rejected a video inserted after a successful catalog lookup. */
- (void)onFailedToInsertVideo:(BCOVVideo *)video;

/**
 * Extra query parameters to add to the Playback API request for the source.
 * The core merges the parameters contributed by every feature into the
 * findVideo request. SSAI adds the ad-config id here so VideoCloud returns a
 * VMAP-bearing video. Kept generic so the core never needs a feature-specific
 * request parameter. Return nil or an empty dictionary to add none.
 */
- (nullable NSDictionary<NSString *, NSString *> *)additionalSourceQueryParameters;
/** Called after the Fabric event emitter becomes available. */
- (void)onEventEmitterReady;

/**
 * All prop setters for the current update transaction have run. A feature whose
 * behavior depends on several props at once (captions: captionsEnabled +
 * captionTrackId) should act here rather than in setProp:value:, so it applies
 * one coalesced result per commit instead of reacting to each prop
 * independently (which would trigger competing selections).
 */
- (void)onPropsCommitted;

/**
 * Transform the resolved video just before it is handed to the playback
 * controller. Return the video to use (return the input unchanged for no-op).
 * Ads stamps the VMAP ad-tag property here so the IMA plugin requests the
 * schedule for this video.
 */
- (nullable BCOVVideo *)willSetVideo:(BCOVVideo *)video;

/** The playback session became ready. */
- (void)onSessionReady:(id<BCOVPlaybackSession>)session;

/** Finite cue points crossed during the current playback/seek interval. */
- (void)onCuePoints:(BCOVCuePointCollection *)cuePoints
       previousTime:(CMTime)previousTime
        currentTime:(CMTime)currentTime;

/** The Brightcove player began a screen-mode transition. */
- (void)onScreenModeWillChange:(BCOVPUIScreenMode)screenMode;

/** The Brightcove player completed a screen-mode transition. */
- (void)onScreenModeChanged:(BCOVPUIScreenMode)screenMode;

/** Prepare for teardown while a screen-mode transition is still active. */
- (BOOL)prepareForPlayerTearDown:(dispatch_block_t)completion;

/**
 * Every playback-session lifecycle event, forwarded verbatim before the core's
 * own generation guard. Used by features that observe SDK/plugin lifecycle
 * events the core does not model itself — ads reads the IMA ad lifecycle
 * events (kBCOVIMALifecycleEvent*) delivered on this channel, playback-events
 * reads play/pause/end, PiP re-arms automatic background entry while playing,
 * and buffering tracks playback stall/recovery events.
 */
- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session;

/**
 * A feature-specific lifecycle failure that prevents the current source from
 * becoming playable. The core emits it through the content onError contract;
 * return nil for non-fatal or unrelated lifecycle events.
 */
- (nullable NSError *)sourceErrorForLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                                            session:(id<BCOVPlaybackSession>)session;

/**
 * Playback advanced to a new position (seconds). Forwarded from the core's
 * BCOVPlaybackControllerDelegate didProgressTo: callback so a feature that
 * reports playback position (playback-events onProgress) reads it here rather
 * than polling. The core does not model progress itself and stays agnostic
 * about why a feature wants it.
 */
- (void)onDidProgressTo:(NSTimeInterval)progress;

/**
 * The SDK determined the video's type (VOD / Live / Live-DVR). Forwarded from
 * the core's determinedVideoType:forVideo: callback so a feature can react to
 * live vs on-demand content (the live feature reports isLive/hasDvr from it).
 * The core does not branch on video type itself.
 */
- (void)onDeterminedVideoType:(BCOVVideoType)videoType forVideo:(BCOVVideo *)video;

/**
 * Ad-sequence and per-ad boundaries, forwarded from the core's
 * BCOVPlaybackControllerAdsDelegate. This is the SDK's typed way to observe
 * ads and carries the BCOVAd directly — used by SSAI, whose stitched ads are
 * reported through this delegate rather than a plugin-specific lifecycle event.
 */
- (void)onEnterAdSequence;
- (void)onExitAdSequence;
- (void)onEnterAd:(BCOVAd *)ad;
- (void)onExitAd:(BCOVAd *)ad;

/**
 * An ad's playback advanced to a new position, forwarded from the core's
 * BCOVPlaybackControllerAdsDelegate didEnterAd/didProgressTo callbacks — the
 * same relay pattern as the ad boundaries above. Only the core is the ads
 * delegate; a feature (ads) that reports per-ad progress reads it here
 * instead of needing its own delegate registration, which would fight the
 * SDK's single-delegate assumption.
 */
- (void)onAdProgress:(BCOVAd *)ad progress:(NSTimeInterval)progress;

/**
 * The core is about to request a catalog source for this video id. Ad
 * features use it to scope their event emission to the current source
 * (Android's PlayerFeature.onSourceLoading counterpart).
 */
- (void)onSourceLoading:(NSString *)videoId;

/**
 * The legible (caption/subtitle) media option changed on the session — from
 * the player's own controls or a programmatic setter. Forwarded from the
 * core's BCOVPlaybackControllerDelegate so a feature can report user-driven
 * caption changes, not just prop-driven ones. Option is nil when captions
 * were turned off.
 */
- (void)onSelectedLegibleMediaOption:(nullable AVMediaSelectionOption *)option;

- (void)onSelectedAudibleMediaOption:(nullable AVMediaSelectionOption *)option;

- (void)onSeekableRangesChanged:(NSArray *)seekableRanges
                          session:(id<BCOVPlaybackSession>)session;

/** The current source hit a terminal playback error. */
- (void)onPlaybackError;

/** A transient network error is being retried without surfacing onError. */
- (void)onNetworkRecoveryStarted;

/** A network recovery attempt ended, either successfully or terminally. */
- (void)onNetworkRecoveryEnded;

/** The player (view + controller) was torn down. */
- (void)onPlayerTearDown;

/** The view is being unmounted; release everything. */
- (void)onInvalidate;

/** The playback controller reported a change to external playback state. */
- (void)onExternalPlaybackChanged:(BOOL)active;

/** Pass-throughs of the BCOVPUIPlayerViewDelegate PiP callbacks. */
- (void)pictureInPictureDidStart;
- (void)pictureInPictureDidStop;
- (void)pictureInPictureFailedToStartWithError:(nullable NSError *)error;

/**
 * Pass-through of the BCOVPUIPlayerViewDelegate 360-navigation callback: the
 * SDK's own player-view UI changed which navigation method (device motion,
 * finger tracking) drives a 360 video, and/or toggled VR-goggles projection
 * itself (e.g. the native VR-goggles button). Used by video360 to keep its
 * reported vrMode/navigationMethod in sync with a change the SDK UI made
 * directly, not just ones the vrMode prop requested.
 */
- (void)didSetVideo360NavigationMethod:(BCOVPUIVideo360NavigationMethod)navigationMethod
                       projectionStyle:(BCOVVideo360ProjectionStyle)projectionStyle;

@end

NS_ASSUME_NONNULL_END
