package com.brightcove.reactnativeplayer.core

import android.app.Activity
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventEmitter
import com.brightcove.player.view.BrightcoveExoPlayerVideoView
import com.facebook.react.bridge.WritableMap

/**
 * The contract between the core player view and an optional feature module
 * (captions, Picture-in-Picture, ads, DRM, ...).
 *
 * A feature is a self-contained directory next to core/ that a sample copies
 * only when it needs it. The sample's FeatureRegistry lists the features its
 * bridge copy contains; the core invokes every registered feature through the
 * hooks below and knows nothing about any concrete feature.
 */
interface PlayerFeature {
  /** Whether this feature owns host background/foreground lifecycle behavior. */
  val keepsPlaybackAliveInBackground: Boolean
    get() = false

  /**
   * The prop names this feature owns (e.g. "captionsEnabled"). The core routes
   * setProp calls for these names to this feature, and raises a descriptive
   * error if a prop arrives that no registered feature owns — a loud signal
   * that the bridge copy is missing the feature's directory.
   */
  val ownedProps: Set<String>

  /**
   * Direct-event names this feature emits, mapped Fabric-style
   * (topX -> onX). Merged into the view manager's exported events.
   */
  val exportedEvents: Map<String, String>

  /**
   * The command names this feature handles (e.g. "enterFullscreen", "enterPictureInPicture").
   */
  val supportedCommands: Set<String>
    get() = emptySet()

  /**
   * Called once from the core view's init, after the video view finished
   * initialization. The host grants access to the video view, the emitter,
   * and JS event dispatch.
   */
  fun attach(host: FeatureHost)

  /**
   * A prop owned by this feature (per ownedProps) changed. Value types match
   * the view manager's setters (Boolean, String?, Double, ...).
   */
  fun setProp(name: String, value: Any?)

  /**
   * Execute a command owned by this feature. Return true if handled.
   */
  fun handleCommand(name: String): Boolean = false

  /** The hosting Activity became available (may happen after attach). */
  fun onActivityBound(activity: Activity) {}

  /** A new source is about to load: reset per-video state. */
  fun onSourceReset() {}

  /** Called before the old source generation is invalidated. */
  fun onSourceWillReset() {}

  /**
   * A source is about to load. [videoId] is the validated numeric id for the
   * core's single-video path, or null when a feature owns source loading
   * (offline, queue, reference id, direct URL). Called for every source so a
   * feature can clear state from the outgoing source even when the new source
   * has no core videoId.
   */
  fun onSourceLoading(videoId: String?) {}

  /**
   * True only while this feature owns the current source. The core still owns
   * source lifecycle/generation guards; a source-loading feature replaces the
   * core's online Catalog fetch for this one request.
   */
  fun claimsSourceLoading(): Boolean = false

  /**
   * Loads the source when claimsSourceLoading() returned true. accountId and
   * policyKey remain available because an offline feature may use the same
   * persisted-video lookup API as the online catalog, but it must not fetch a
   * new online source here. Check isCurrentRequest before every side effect.
   */
  fun loadSource(requestGeneration: Int, accountId: String, policyKey: String) {}

  /**
   * Manual skip to the next item, from the `next` imperative command. Only
   * called on the feature for which claimsSourceLoading() is true. Returns
   * false when no skip happened (nothing loaded, resolution in flight, past
   * the last item without repeat-all); the core reports that through
   * onPlayerCommandError per the command contract. The native SDK's own
   * queue is the single source of truth for whether advancing is possible.
   */
  fun advanceQueue(): Boolean = false

  /**
   * Manual skip to the previous item, from the `previous` imperative command.
   * Only called on the feature for which claimsSourceLoading() is true.
   * Returns false when no skip happened (nothing loaded, at the first item).
   */
  fun previousQueueItem(): Boolean = false

  /**
   * Extra query parameters to add to the Catalog (Playback API) request for the
   * source. The core merges the parameters contributed by every feature into
   * the request. SSAI adds the ad-config id here so VideoCloud returns a
   * VMAP-bearing video. Kept generic so the core never needs a feature-specific
   * request parameter. Default: none.
   */
  fun additionalSourceQueryParameters(): Map<String, String> = emptyMap()

  /**
   * Give a feature the chance to load the resolved video itself instead of the
   * core's default videoView.add(video). Return true if the feature took
   * ownership of processing and adding the video (SSAI hands it to
   * SSAIComponent, which rewrites the source to the server-stitched stream).
   * The core still owns autoplay and starts from the eventual DID_SET_VIDEO
   * event through its attachment/resume gate. Return false to let the core add
   * and start normally. At most one feature may claim a video; the core treats
   * the first claim as authoritative. Default: false (the core adds the video).
   */
  fun willAddVideo(video: com.brightcove.player.model.Video): Boolean = false

  /**
   * The catalog resolved a video for the current request, before any feature
   * decides whether to claim adding it (willAddVideo) and before the core's
   * own videoView.add(video). Called on every registered feature in
   * registration order, each receiving the previous feature's returned
   * Video — a feature that needs to inspect or rewrite a property on the
   * resolved Video (thumbnail-seeking forces preview-thumbnail URLs to HTTPS;
   * 360 video reads the projection format) does it here rather than reaching
   * into the SDK's own add/willAddVideo path. Return the input unchanged for
   * a pure side-effecting read (the default). Return a rewritten Video only
   * if the feature actually needs the core/SDK to see different properties
   * than the catalog returned.
   */
  fun onVideoLoaded(video: com.brightcove.player.model.Video): com.brightcove.player.model.Video = video

  /**
   * All prop setters for the current Fabric update transaction have run. A
   * feature whose behavior depends on several props at once (captions:
   * captionsEnabled + captionTrackId) should act here rather than in setProp,
   * so it applies one coalesced result per commit instead of reacting to each
   * prop independently (which would trigger competing, racing selections).
   */
  fun onPropsCommitted() {}

  /**
   * Called while the core registers the current source's playback listeners.
   * Register feature listeners here via host.registerListener: the host owns
   * the request-generation guard and unregistration, so a listener added this
   * way only fires for the current source and is torn down on source change or
   * dispose. Do not call videoView.eventEmitter.on directly — that bypasses
   * both and leaks.
   */
  fun onRegisterPlaybackListeners() {}

  /** The view's size or position changed. */
  fun onLayoutChanged() {}

  /**
   * Called before the core destroys its native resources. Return true only when
   * the feature must keep the core alive until a real native lifecycle event;
   * it must later call FeatureHost.completeDeferredDispose exactly once.
   */
  fun onDisposeRequested(): Boolean = false

  /**
   * Whether this feature owns (and will itself report) the given SDK ERROR
   * event, so the core must NOT surface it through the content onError contract.
   * The SDK broadcasts some non-content failures on the shared ERROR event —
   * e.g. the IMA plugin re-emits ad failures there as well as on AD_ERROR — and
   * an ad failing is not a content-playback failure. A feature returns true for
   * an error it recognizes as its own; the core stays agnostic and simply skips
   * any error a feature claims. Default false: most features claim nothing.
   *
   * This hook is Android-only by necessity, not an oversight: it exists because
   * the Android IMA plugin multiplexes ad failures onto the shared content ERROR
   * event. The iOS SDK delivers ad failures on their own lifecycle event
   * (kBCOVIMALifecycleEventAdsManagerDidReceiveAdError), distinct from the
   * content failure events the core handles, so the iOS core never confuses the
   * two and needs no equivalent hook.
   */
  fun suppressesPlaybackError(event: Event): Boolean = false

  /** The current source hit a terminal playback error. */
  fun onPlaybackError() {}

  /**
   * The core is attempting to silently recover playback after a transient
   * network failure (re-preparing the existing source, see
   * BrightcovePlayerView.recoverFromTransientNetworkError) rather than
   * reporting a terminal error. Not every recovery attempt succeeds — a
   * feature that reacts here must treat onNetworkRecoveryEnded as the only
   * authoritative "it's over" signal, not an assumption that recovery worked.
   *
   * Purely a notification hook, not a gate: the core decides on its own
   * whether to attempt recovery, features cannot veto it. Default no-op so
   * only a feature that cares about surfacing the stall (buffering) needs to
   * override it.
   */
  fun onNetworkRecoveryStarted() {}

  /**
   * A network recovery attempt (see onNetworkRecoveryStarted) has ended,
   * either because playback resumed or because the recovery itself failed and
   * the core is about to report a terminal error instead.
   */
  fun onNetworkRecoveryEnded() {}

  fun play(): Boolean = false

  fun pause(): Boolean = false

  /** The view is being torn down; release everything. */
  fun onDispose() {}
}

/**
 * What the core exposes to features. Deliberately narrow: features must not
 * reach into the core view's internals beyond this surface.
 */
interface FeatureHost {
  val videoView: BrightcoveExoPlayerVideoView
  val boundActivity: Activity?
  val hostView: android.view.ViewGroup
  val isDisposed: Boolean
  val features: List<PlayerFeature>

  /** The generation associated with the current source request. */
  val currentRequestGeneration: Int

  /**
   * The volume currently applied to the content player, in [0, 1], with mute
   * already folded in (0 when muted). Ad features read this to apply the
   * same level to their own ad player — the IMA plugin plays ads on a
   * separate ExoPlayer that does not receive the SDK's SET_VOLUME event, so
   * without this a muted or low-volume app plays ads at full volume.
   */
  val effectiveVolume: Float

  /**
   * Whether the bound Activity is currently resumed (foregrounded). A feature
   * that keeps playback alive in the background must consult this before
   * disabling itself: if playback is only still running because this feature
   * is suppressing the normal onPause/onStop teardown (see
   * keepsPlaybackAliveInBackground), turning the feature off while the host
   * is not resumed must pause playback itself — the core's own lifecycle
   * callbacks already ran with keepsPlaybackAliveInBackground true and will
   * not run again until the next real transition.
   */
  val isHostResumed: Boolean

  /**
   * The current source's accountId/policyKey props, for a feature that needs
   * its own catalog lookup independent of the current source (preloading
   * resolves a different video while one already plays).
   */
  val accountId: String?
  val policyKey: String?
  /** Emit a direct event to JS (latched until the view has a React tag). */
  fun emitEvent(name: String, payload: WritableMap)

  /**
   * Reparents the video view into the Activity-root fullscreen overlay.
   * Returns false when the overlay could not be created (no bound Activity,
   * content root, or view parent) so the caller never reports fullscreen to
   * JavaScript for a presentation that did not happen. Setting up the overlay
   * twice is a no-op that returns true.
   */
  fun enterFullscreenLayout(): Boolean

  /** Restores the video view to its normal parent; a no-op when not fullscreen. */
  fun exitFullscreenLayout()

  /** Emit a command error direct event to JS. */
  fun emitCommandError(command: String, code: String, message: String, nativeCode: String)

  /** Whether the host Activity is currently in Android Picture-in-Picture. */
  val isInPictureInPictureMode: Boolean
    get() = boundActivity?.isInPictureInPictureMode == true
  /** Fail the current source without allowing the core to fall back to plain content. */
  fun failSource(code: String, nativeCode: String, message: String)

  /**
   * Register a playback listener scoped to the current source request: it is
   * auto-unregistered on source change/dispose, and only invoked while its
   * request generation is current.
   */
  fun registerListener(eventType: String, handler: (com.brightcove.player.event.Event) -> Unit)

  /** Register a listener that lives for the whole view (not per-source). */
  fun registerPersistentListener(
    eventType: String,
    handler: (com.brightcove.player.event.Event) -> Unit,
  )

  /** Fold a resolved video through every feature's onVideoLoaded, the same
   * post-resolution pipeline the core's own catalog path runs (thumbnail HTTPS
   * normalization, early 360 projection handling). Source-owning features must
   * call this before adding a video so their modes get the same treatment. */
  fun onVideoLoaded(video: com.brightcove.player.model.Video): com.brightcove.player.model.Video =
    features.fold(video) { current, feature -> feature.onVideoLoaded(current) }

  /** Stamp a feature-owned video so late SDK callbacks remain source-scoped. */
  fun tagVideoForCurrentRequest(video: com.brightcove.player.model.Video): com.brightcove.player.model.Video {
    video.properties["com.brightcove.reactnativeplayer.requestGeneration"] = currentRequestGeneration
    return video
  }

  /** Ask Android to re-run the layout pass (RN skips it for native children). */
  fun requestHostLayout()

  fun reevaluateBackgroundPolicy()

  /** Mark the current player source dirty after a source-owning prop changes. */
  fun requestSourceReload()

  /** True while requestGeneration still names the active source. */
  fun isCurrentRequest(requestGeneration: Int): Boolean

  /**
   * Report a feature-loaded playable source and start pending auto-play. The
   * explicit readyVideoId is authoritative because persisted SDK Video objects
   * can omit their public ID even though the feature still knows its source.
   */
  fun markVideoLoaded(requestGeneration: Int, readyVideoId: String)

  /**
   * Supplies the ready-event identity before the SDK is handed a local Video.
   * add(video) can synchronously emit BUFFERING_COMPLETED, so setting it only
   * in markVideoLoaded would be too late for persisted Android videos.
   */
  fun setReadyVideoId(requestGeneration: Int, readyVideoId: String)

  /** Emit the normalized terminal player error for a feature-owned source. */
  fun emitSourceLoadError(
    requestGeneration: Int,
    code: String,
    nativeCode: String,
    message: String,
  )

  /** Finish a disposal deferred by PlayerFeature.onDisposeRequested. */
  fun completeDeferredDispose()

  val eventEmitter: EventEmitter
    get() = videoView.eventEmitter
}
