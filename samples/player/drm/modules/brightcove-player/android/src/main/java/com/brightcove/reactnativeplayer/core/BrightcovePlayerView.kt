package com.brightcove.reactnativeplayer.core

import android.app.Activity
import android.content.ComponentCallbacks
import android.content.res.Configuration
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.media3.common.PlaybackException
import androidx.media3.exoplayer.drm.DrmSession
import com.brightcove.player.display.ExoPlayerVideoDisplayComponent
import com.brightcove.player.edge.Catalog
import com.brightcove.player.edge.CatalogError
import com.brightcove.player.edge.VideoListener
import com.brightcove.player.network.HttpRequestConfig
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventEmitter
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.player.util.LifecycleUtil
import com.brightcove.player.view.BrightcoveExoPlayerVideoView
import com.brightcove.reactnativeplayer.BrightcovePlayerEvent
import com.brightcove.reactnativeplayer.FeatureRegistry
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.WritableMap
import kotlin.math.roundToLong

import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper

private enum class VideoScalingMode {
  FIT,
  FILL,
}

class BrightcovePlayerView(
  private val reactContext: ThemedReactContext,
) : FrameLayout(reactContext), DefaultLifecycleObserver, ComponentCallbacks, FeatureHost {
  // A Fabric view can be created while the ReactContext has no current
  // activity (host backgrounded / mid-transition). Bind lazily and retry on
  // attach/commit instead of requiring an activity at construction: an
  // unbound LifecycleUtil would never pause/release the ExoPlayer, which is
  // the leak this bridge exists to prevent.
  private var activity: Activity? = null
  override val videoView = BrightcoveExoPlayerVideoView(reactContext)
  override val boundActivity: Activity? get() = activity
  override val hostView: android.view.ViewGroup get() = this
  override val isDisposed: Boolean get() = disposed
  override val currentRequestGeneration: Int get() = requestGeneration
  override val effectiveVolume: Float get() = if (muted) 0f else volume.toFloat()
  override val isHostResumed: Boolean get() = hostResumed
  override val isInPictureInPictureMode: Boolean
    get() = activity?.isInPictureInPictureMode == true

  // The features this bridge copy contains, declared by the sample-owned
  // FeatureRegistry. The core routes feature props/lifecycle through this
  // list and knows nothing about concrete features.
  override val features: List<PlayerFeature> = FeatureRegistry.createFeatures()
  private val keepsPlaybackAliveInBackground: Boolean
    get() = features.any { it.keepsPlaybackAliveInBackground }
  private val reactLifecycleListener = object : LifecycleEventListener {
    override fun onHostResume() {
      bindLifecycleIfNeeded()
      startPendingPlayback()
    }

    override fun onHostPause() = Unit

    override fun onHostDestroy() {
      dispose()
    }
  }

  // Assigned in init after videoView.finishInitialization(), which is what
  // creates the EventEmitter LifecycleUtil needs. Bound to videoView once and
  // kept for the view's whole life: it is driven through the full activity
  // lifecycle (onCreate → onDestroy) and the videoView it wraps is reused
  // across source swaps, so it must not be recreated mid-life or it would miss
  // the current lifecycle state.
  private lateinit var lifecycleUtil: LifecycleUtil
  // (eventType, token) pairs, not a Map keyed by eventType: more than one
  // listener can be registered for the same event (core plus a feature, or two
  // features), and each needs its own token to be removed. A map would let a
  // later registration overwrite an earlier one's token and leak that listener.
  // Per-source listeners are cleared on every source change; persistent ones
  // live for the whole view and are cleared only on dispose.
  private val sourceListenerTokens = mutableListOf<Pair<String, Int>>()
  private val persistentListenerTokens = mutableListOf<Pair<String, Int>>()
  // Events produced before the view has a React tag, held until it does so a
  // pre-tag error/ready is never silently dropped.
  private val pendingEvents = mutableListOf<PendingEvent>()
  // Feature props are buffered until onAfterUpdateTransaction. A source change
  // and a feature selection can arrive in the same Fabric update; resetting a
  // feature after immediately applying its prop erases an incoming request
  // (for example, captionTrackId="es" on the initial source). The transaction
  // boundary lets the core reset first and apply all new feature props second,
  // without relying on the order React Native happens to invoke setters.
  private val pendingFeatureProps = linkedMapOf<PlayerFeature, LinkedHashMap<String, Any?>>()

  override var accountId: String? = null
    private set
  override var policyKey: String? = null
    private set
  private var videoId: String? = null
  private var autoPlay = true
  private var playbackRate = 1.0
  private var loop = false
  private var volume = 1.0
  private var muted = false
  // The SDK's SET_VOLUME event calls exoPlayer.setVolume(...) with no null
  // check, and exoPlayer does not exist until the first source is added and
  // prepared. Defer the first apply until the player has reached ready (the
  // same point autoPlay's pendingAutoPlay waits for), then apply immediately;
  // the player instance persists across later source changes, so no further
  // deferral is needed after the first one.
  private var pendingVolumeApply = true
  // Set by setVolume/setMuted; consumed once, in commitConfiguration, so a
  // transaction that changes both props applies exactly once instead of once
  // per setter (see setVolume's comment for why that matters).
  private var volumeApplyPending = false
  private var videoScalingMode = VideoScalingMode.FIT

  private var sourceDirty = true
  // Tracks the feature source-reset owed for the transition in flight. Starts
  // pending so the initial source receives the same reset as a later
  // replacement; markSourceDirty arms it for each subsequent change and
  // commitConfiguration flushes it once before and once after feature props.
  private val sourceReset = SourceResetScheduler(initiallyPending = true)
  private var configurationCommitted = false
  private var activeSource: VideoSource? = null
  private var requestGeneration = 0
  private var videoLoaded = false
  private var readyEmitted = false
  private var featureReadyVideoId: String? = null
  private var sourceFailed = false
  private var pendingUntypedErrorToken = 0
  // Exactly one recovery attempt per stall: set for the duration of a
  // silent re-prepare after a transient IO error (see
  // recoverFromTransientNetworkError), so a second error arriving while that
  // attempt is still in flight falls through to the normal terminal path
  // instead of restarting recovery. Cleared on the next successful
  // BUFFERING_COMPLETED (recovery worked) or explicitly if recovery itself
  // gives up (see emitSourceError).
  private var networkRecoveryInProgress = false
  private var pendingAutoPlay = false
  private var playbackRequested = false
  private var pendingSeekGeneration: Int? = null
  private var resumeWhenAttached = false
  private var hostResumed = false
  private var hostStopped = false
  private var disposed = false
  private var fullscreenOverlay: FrameLayout? = null
  private var fullscreenVideoLayoutParams: ViewGroup.LayoutParams? = null
  private var fullscreenReparentSequence = 0
  private var pendingFullscreenResumeSequence: Int? = null
  // React Native can drop the view while Android still presents it in a system
  // PiP window. In that case PiP must retain the Activity, video view, and SDK
  // exit listener until the real system exit; disposeRequested blocks new work
  // without pretending the native resources are already gone.
  private var disposeRequested = false
  private var lastConfigurationError: String? = null

  // React Native lays views out itself and does not run Android's layout pass
  // when a native child changes later (e.g. the media controls appearing on
  // tap). Re-run measure/layout manually so those children become visible.
  // Declared before init: addView there already triggers requestLayout.
  private val measureAndLayout = Runnable {
    measure(
      MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY),
    )
    layout(left, top, right, bottom)
  }

  init {
    addView(
      videoView,
      LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
    )
    videoView.finishInitialization()
    applyVideoScalingMode()
    lifecycleUtil = LifecycleUtil(videoView)
    features.forEach { it.attach(this) }
    reactContext.addLifecycleEventListener(reactLifecycleListener)
    bindLifecycleIfNeeded()
  }

  private fun bindLifecycleIfNeeded() {
    if (disposed) return

    val currentActivity = reactContext.currentActivity ?: return
    if (activity === currentActivity) return

    unbindLifecycle()
    val lifecycleOwner = currentActivity as? LifecycleOwner
      ?: error("BrightcovePlayerView requires a LifecycleOwner Activity")
    activity = currentActivity
    currentActivity.application.registerComponentCallbacks(this)
    lifecycleOwner.lifecycle.addObserver(this)
    features.forEach { it.onActivityBound(currentActivity) }
  }

  private fun unbindLifecycle() {
    val boundActivity = activity ?: return
    boundActivity.application.unregisterComponentCallbacks(this)
    (boundActivity as LifecycleOwner).lifecycle.removeObserver(this)
    activity = null
  }

  override fun requestLayout() {
    super.requestLayout()
    // RN calls requestLayout frequently (and measureAndLayout below itself
    // lays out, which can trigger more). Coalesce to a single posted pass per
    // frame instead of scheduling one per call, or the view re-measures many
    // times over redundantly.
    removeCallbacks(measureAndLayout)
    post(measureAndLayout)
  }

  override fun requestHostLayout() {
    requestLayout()
  }

  override fun enterFullscreenLayout(): Boolean {
    if (fullscreenOverlay != null) return true
    val shouldResumeAfterReparent = playbackRequested || videoView.isPlaying
    val activity = boundActivity ?: return false
    val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return false
    val playerParent = videoView.parent as? ViewGroup ?: return false
    fullscreenVideoLayoutParams = videoView.layoutParams
    playerParent.removeView(videoView)
    fullscreenOverlay = FrameLayout(activity).apply {
      setBackgroundColor(android.graphics.Color.BLACK)
      addView(videoView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }
    content.addView(fullscreenOverlay, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    resumeAfterFullscreenReparent(shouldResumeAfterReparent)
    requestLayout()
    return true
  }

  override fun exitFullscreenLayout() {
    val overlay = fullscreenOverlay ?: return
    val shouldResumeAfterReparent = playbackRequested || videoView.isPlaying
    val playerParent = this
    overlay.removeView(videoView)
    playerParent.addView(videoView, fullscreenVideoLayoutParams ?: LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    (overlay.parent as? ViewGroup)?.removeView(overlay)
    fullscreenOverlay = null
    fullscreenVideoLayoutParams = null
    resumeAfterFullscreenReparent(shouldResumeAfterReparent)
    requestLayout()
  }

  /**
   * Detaches the fullscreen overlay without reporting state.
   *
   * PiP owns the window while it is active, so the feature skips the normal
   * exit layout to avoid fighting it. On teardown that leaves the overlay
   * attached to the Activity root holding a player we are about to destroy —
   * the deferred PiP-exit cleanup cannot help once the host is disposed. The
   * core therefore removes the overlay itself as part of dispose.
   */
  private fun forceDetachFullscreenOverlay() {
    val overlay = fullscreenOverlay ?: return
    if (videoView.parent === overlay) {
      overlay.removeView(videoView)
    }
    (overlay.parent as? ViewGroup)?.removeView(overlay)
    fullscreenOverlay = null
    fullscreenVideoLayoutParams = null
  }

  private fun resumeAfterFullscreenReparent(shouldResume: Boolean) {
    if (!shouldResume) return
    // The reparent detaches the video's surface, which the SDK reports as a
    // pause. Mark the transition window with a sequence token so that pause
    // does not clear the caller's play intent, then restart only if this exact
    // transition is still current (same token, source generation, live view,
    // foregrounded host). An explicit pause or a newer transition supersedes
    // this token and cancels the restart.
    val sequence = ++fullscreenReparentSequence
    pendingFullscreenResumeSequence = sequence
    val capturedGeneration = requestGeneration
    videoView.post {
      // A newer reparent (or an explicit play/pause) supersedes this token; the
      // stale runnable must not resume on its behalf.
      val transitionStillCurrent = pendingFullscreenResumeSequence == sequence
      if (transitionStillCurrent) {
        pendingFullscreenResumeSequence = null
      }
      val shouldStillResume = transitionStillCurrent &&
        FullscreenReparentPolicy.shouldResumeAfterReparent(
          playbackRequested = playbackRequested,
          capturedGeneration = capturedGeneration,
          currentGeneration = requestGeneration,
          disposed = disposed,
          disposeRequested = disposeRequested,
          hostResumed = hostResumed,
          attachedToWindow = isAttachedToWindow,
        )
      if (shouldStillResume && !videoView.isPlaying) {
        videoView.start()
        playbackRequested = true
      }
    }
  }

  /**
   * Whether the SDK's surface-detach pause during a fullscreen reparent
   * belongs to the transition currently in flight and must not clear the
   * caller's play intent.
   */
  private val inFullscreenReparentWindow: Boolean
    get() = pendingFullscreenResumeSequence != null

  override fun completeDeferredDispose() {
    if (disposeRequested && !disposed) {
      completeDispose()
    }
  }

  // Manual queue skip for the `next`/`previous` imperative commands (see the
  // TS contract's NativeCommands doc comment). Dispatched through
  // handleCommand so the playlists feature owns the full outcome contract:
  // it emits its own typed errors for the no-queue (queue_not_loaded) and
  // at-end (queue_at_end) cases — the same pattern as live/PiP — and
  // handleCommand's fallbacks cover a missing feature. The bridge adds no
  // separate queue state machine — the native SDK's own queue is the single
  // source of truth for whether advancing is possible.
  fun nextQueueItem() {
    handleCommand("next")
  }

  fun previousQueueItem() {
    handleCommand("previous")
  }

  fun setAccountId(value: String?) {
    if (accountId != value) {
      accountId = value
      markSourceDirty()
    }
  }

  fun setPolicyKey(value: String?) {
    if (policyKey != value) {
      policyKey = value
      markSourceDirty()
    }
  }

  fun setVideoId(value: String?) {
    if (videoId != value) {
      videoId = value
      markSourceDirty()
    }
  }

  fun setAutoPlay(value: Boolean) {
    // autoPlay is an initialization-only hint (see the TS contract): it decides
    // whether playback starts when the source first becomes ready, and is not a
    // live play/pause control. Record the value — the ready path reads it to
    // seed pendingAutoPlay — but do not start or stop an already-loaded video on
    // a later toggle. Live play/pause is the app's own controls' job.
    autoPlay = value
  }

  fun setLoop(value: Boolean) {
    loop = value
  }

  // volume and muted are live controls (unlike autoPlay): a caller can adjust
  // them at any time, on either platform. muted is bridge-level state, not a
  // native SDK concept — the SDK only has volume — so muting stores the
  // caller's volume and applies 0; unmuting restores it. If a new volume
  // arrives while muted, it is recorded and takes effect only once unmuted, so
  // it cannot un-mute the player as a side effect of an unrelated prop update.
  fun setVolume(value: Double) {
    // coerceIn does not clamp NaN: NaN compares false to both bounds (IEEE 754),
    // so it falls through coerceIn's <min/>max checks unchanged and would reach
    // exoPlayer.setVolume(NaN)/AVPlayer.volume=NaN uncaught by any layer below
    // this — ExoPlayer's own internal clamp (Math.min/Math.max) has the exact
    // same NaN-passthrough gap. A NaN volume (e.g. from an upstream 0/0 in the
    // calling app) is not a valid "out of range" value to clamp to an endpoint;
    // treat it as no update, matching "ignore an invalid request" rather than
    // silently propagating a NaN to the native player.
    if (value.isNaN()) {
      Log.w(TAG, "Ignoring invalid NaN volume request")
      return
    }
    val clamped = value.coerceIn(0.0, 1.0)
    if (volume == clamped) return
    volume = clamped
    // Defer the actual apply to commitConfiguration (see there) rather than
    // calling applyVolume directly here: volume and muted are two independent
    // @ReactProp setters, so a single JS update that changes both in one
    // transaction would otherwise apply twice — once un-muted at the old mute
    // state right after this setter runs, then again once setMuted runs —
    // producing a real, audible momentary volume blip at the wrong level for
    // one frame. Applying once, after every prop in the transaction has been
    // recorded, is the atomic, correct-to-either-order result.
    volumeApplyPending = true
  }

  fun setMuted(value: Boolean) {
    if (muted == value) return
    muted = value
    volumeApplyPending = true
  }

  private fun applyVolume() {
    // dispose() destroys the player (exoPlayer.release(); exoPlayer = null),
    // but does not unregister the SDK's own internal SET_VOLUME listener (it
    // is not one of ours, so unregisterPlaybackListeners/
    // unregisterPersistentListeners cannot reach it). That listener calls
    // exoPlayer.setVolume(...) with no null check, so emitting after dispose
    // would NPE inside the SDK. A caller can set this prop at any time,
    // including in the same update as unmount, so this must guard itself
    // rather than rely on the caller never calling it post-dispose.
    if (disposed || pendingVolumeApply) return
    emitSetVolume(if (muted) 0.0 else volume)
  }

  // The SDK's SET_VOLUME listener (registered internally by ExoMediaPlayback)
  // calls exoPlayer.setVolume(...) unconditionally, with no null check; the
  // player is not created until the first source is added. Emitting before
  // then would risk an NPE inside the SDK, so this is only called once the
  // player has reached ready (see the BUFFERING_COMPLETED handler).
  private fun emitSetVolume(effectiveVolume: Double) {
    videoView.eventEmitter.emit(
      EventType.SET_VOLUME,
      mapOf(Event.VOLUME to effectiveVolume.toFloat()),
    )
  }

  // A live control (like volume/muted, unlike autoPlay): a caller can change
  // it at any time, including mid-playback, and is not tied to any one source —
  // it is not reset on source change, matching a customer's expectation that
  // setting 2x once keeps every subsequently loaded video at 2x too, the same
  // way volume is not reset per source.
  fun setPlaybackRate(value: Double) {
    val validatedRate = PlaybackRateValidator.validate(value)
    if (validatedRate == null) {
      Log.w(TAG, "Ignoring invalid playback rate: $value")
      return
    }
    val doubleRate = validatedRate.toDouble()
    if (playbackRate == doubleRate) return
    playbackRate = doubleRate
    applyPlaybackRate()
  }

  private fun applyPlaybackRate() {
    // Mirrors applyVolume's guard: dispose() releases the ExoPlayer instance,
    // and getPlayback()?.getPlayer() is null both before the first source is
    // prepared and again after dispose. A caller can set this prop at any
    // time, including in the same update as unmount, so this must guard
    // itself rather than rely on the caller never calling it post-dispose or
    // pre-ready.
    if (disposed) return
    videoView.playback?.player?.setPlaybackSpeed(playbackRate.toFloat())
  }

  fun setVideoScalingMode(value: String?) {
    // A JS-supplied prop value must never crash the app: an invalid enum string
    // is a value error (like an invalid playbackRate), not a contract
    // violation. Log and keep the last valid mode, matching setPlaybackRate and
    // the iOS branch, rather than throwing from a @ReactProp setter.
    val mode = when (value) {
      null, "fit" -> VideoScalingMode.FIT
      "fill" -> VideoScalingMode.FILL
      else -> {
        Log.w(TAG, "Ignoring invalid videoScalingMode: $value")
        return
      }
    }
    videoScalingMode = mode
    applyVideoScalingMode()
  }

  private fun applyVideoScalingMode() {
    // RenderView owns the native video surface's aspect-preserving fit/crop
    // behavior. ZoomController is intentionally not used: it also tracks
    // gesture/fullscreen state, which is unrelated to this declarative prop.
    val renderView = videoView.renderView ?: return
    when (videoScalingMode) {
      VideoScalingMode.FIT -> renderView.zoomOut()
      VideoScalingMode.FILL -> renderView.zoomIn()
    }
  }
  /**
   * Queues a feature-owned prop for its owner at the end of the current Fabric
   * transaction. Fails loudly when no installed feature owns the prop: that
   * means this bridge copy does not include the feature's directory, and
   * silently ignoring the prop would be exactly the kind of cross-platform
   * inconsistency this bridge exists to prevent. Default values are not routed
   * when no feature owns them (the prop was simply not set).
   */
  fun setFeatureProp(name: String, value: Any?, isDefault: Boolean) {
    val owner = features.firstOrNull { name in it.ownedProps }
    if (owner != null) {
      pendingFeatureProps.getOrPut(owner) { linkedMapOf() }[name] = value
      return
    }
    if (isDefault) return
    throw IllegalStateException(
      "The '$name' prop requires a player feature that is not included in " +
        "this bridge copy. Copy the feature's directory from " +
        "reference/brightcove-player into modules/brightcove-player and add " +
        "it to FeatureRegistry.createFeatures().",
    )
  }

  fun hasFeatureProp(name: String): Boolean = features.any { name in it.ownedProps }

  fun seekToLiveEdge() {
    handleCommand("seekToLiveEdge")
  }

  fun handleCommand(name: String) {
    if (disposed) return

    if (android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) {
      post { handleCommand(name) }
      return
    }

    val feature = features.firstOrNull { name in it.supportedCommands }
    if (feature != null) {
      // A feature that advertises a command but cannot act on it (not the
      // right state, precondition missing) returns false; the command
      // contract requires that failure to reach onPlayerCommandError rather
      // than vanish. Features that handle the command fully (including by
      // emitting their own typed error — PiP, live, playlists) return true.
      if (!feature.handleCommand(name)) {
        emitCommandError(
          command = name,
          code = "invalid_state",
          message = "The '$name' command cannot run in the player's current state",
          nativeCode = "command_preconditions_not_met",
        )
      }
      return
    }

    emitCommandError(
      command = name,
      code = "feature_not_installed",
      message = "The '$name' command requires a player feature that is not included in this bridge copy",
      nativeCode = "feature_not_installed",
    )
  }

  // ---- Imperative playback commands -----------------------------------------
  // Commands validate the bridge-owned lifecycle boundary, then delegate the
  // actual transport operation to the Brightcove SDK.

  fun play() {
    if (!ensureCommandReady("play")) return
    pendingFullscreenResumeSequence = null
    playbackRequested = true
    if (features.any { it.play() }) return
    videoView.start()
  }

  fun pause() {
    if (!ensureCommandReady("pause")) return
    pendingFullscreenResumeSequence = null
    playbackRequested = false
    if (features.any { it.pause() }) return
    videoView.pause()
  }

  fun seekTo(positionSeconds: Double) {
    if (disposed) return
    val validationError = seekPositionError(positionSeconds)
    if (validationError != null) {
      emitCommandError(
        command = "seekTo",
        code = "invalid_argument",
        nativeCode = "invalid_seek_position",
        message = validationError,
      )
      return
    }
    if (!ensureCommandReady("seekTo")) return
    pendingSeekGeneration = requestGeneration
    videoView.seekTo((positionSeconds * 1000.0).roundToLong())
  }

  // Deliberately NOT gated on ensureCommandReady: reload is precisely how a
  // caller recovers from sourceFailed, so refusing it in that state would be
  // backwards. It re-runs the full source pipeline, which re-validates
  // configuration on its own.
  fun reload() {
    if (disposed) return
    markSourceDirty()
    // markSourceDirty arms the source reset, and reload applies no buffered
    // props through applyPendingFeatureProps, so the single flush here is the
    // whole story. Without it reload() skips every feature's onSourceReset: the
    // offline feature's active-source refcount leaks (later removals are
    // rejected as active_offline_source), and the reset would instead fire
    // later on an unrelated prop commit, mid-playback. Flush before re-applying
    // the source.
    resetFeaturesForPendingSource()
    applyPendingConfiguration()
  }

  private fun ensureCommandReady(command: String): Boolean {
    if (disposed) return false
    if (sourceFailed) {
      emitCommandError(
        command = command,
        code = "invalid_state",
        nativeCode = "source_failed",
        message = "Cannot execute '$command': the current source failed",
      )
      return false
    }
    if (!videoLoaded || !readyEmitted) {
      emitCommandError(
        command = command,
        code = "not_ready",
        nativeCode = "source_not_ready",
        message = "Cannot execute '$command': the player source is not ready",
      )
      return false
    }
    return true
  }

  override fun emitCommandError(
    command: String,
    code: String,
    message: String,
    nativeCode: String,
  ) {
    if (disposed) return

    emitEvent(
      EVENT_COMMAND_ERROR,
      Arguments.createMap().apply {
        putString("command", command)
        putString("code", code)
        putString("message", message)
        putString("nativeCode", nativeCode)
      },
    )
  }
  fun commitConfiguration() {
    bindLifecycleIfNeeded()
    if (disposeRequested) return

    configurationCommitted = true
    // Flush any reset armed at setter time by a core source prop
    // (accountId/policyKey/videoId) before feature props are applied, so a
    // feature-owned selection set in the same transaction (captionTrackId,
    // playlists) is stamped against the new source, not the one it replaces
    // (see CaptionsFeature.setProp).
    resetFeaturesForPendingSource()
    applyPendingFeatureProps()
    // A feature-owned source prop (offlineSourceId, videoIds, videoReferenceId,
    // playlistId, playlistReferenceId, sourceUrl) requests a reload from inside
    // setProp above, after the first flush already ran. Flush that debt here —
    // still before the new source loads — so the outgoing source's
    // onSourceReset runs in this commit (releasing the offline feature's
    // active-source refcount) instead of surviving and firing against the next,
    // already-playing source on an unrelated prop update.
    resetFeaturesForPendingSource()
    applyPendingConfiguration()
    if (volumeApplyPending) {
      volumeApplyPending = false
      applyVolume()
    }
    // All prop setters for this transaction have run; let features apply any
    // behavior that depends on more than one prop as a single coalesced result.
    features.forEach { it.onPropsCommitted() }
    flushPendingEvents()
  }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    if (disposeRequested) return

    bindLifecycleIfNeeded()
    applyPendingConfiguration()
    flushPendingEvents()

    if (resumeWhenAttached && hostResumed) {
      resumeWhenAttached = false
      playbackRequested = true
      videoView.start()
    } else {
      startPendingPlayback()
    }
  }

  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    super.onLayout(changed, l, t, r, b)
    if (changed) {
      features.forEach { it.onLayoutChanged() }
    }
  }

  override fun onDetachedFromWindow() {
    // A React Native unmount detaches the view even while Android is still
    // displaying it in the system PiP window. Pausing here would freeze PiP;
    // defer the whole native teardown until the real PiP exit instead.
    val inSystemPictureInPicture = activity?.isInPictureInPictureMode == true
    if (!keepsPlaybackAliveInBackground && !disposed && !inSystemPictureInPicture && (playbackRequested || videoView.isPlaying)) {
      resumeWhenAttached = true
      playbackRequested = false
      videoView.pause()
    }
    super.onDetachedFromWindow()
  }

  override fun onCreate(owner: LifecycleOwner) {
    if (keepsPlaybackAliveInBackground) return
    activity?.let { lifecycleUtil.onCreate(null, it) }
  }

  override fun onStart(owner: LifecycleOwner) {
    if (keepsPlaybackAliveInBackground) return
    if (hostStopped) {
      lifecycleUtil.onRestart()
      hostStopped = false
    }
    lifecycleUtil.activityOnStart()
  }

  override fun onResume(owner: LifecycleOwner) {
    hostResumed = true
    if (keepsPlaybackAliveInBackground) {
      startPendingPlayback()
      return
    }
    lifecycleUtil.activityOnResume()
    startPendingPlayback()
  }

  override fun onPause(owner: LifecycleOwner) {
    hostResumed = false
    reevaluateBackgroundPolicy()
  }

  override fun onStop(owner: LifecycleOwner) {
    if (keepsPlaybackAliveInBackground) return
    lifecycleUtil.activityOnStop()
    hostStopped = true
  }

  override fun reevaluateBackgroundPolicy() {
    if (disposed || keepsPlaybackAliveInBackground || hostResumed) return
    lifecycleUtil.activityOnPause()
  }

  override fun onDestroy(owner: LifecycleOwner) {
    activity?.let { lifecycleUtil.onActivityDestroyed(it) }
    if (disposeRequested && activity?.isInPictureInPictureMode != true) {
      // If Android destroys the Activity after PiP has already ended, complete
      // a deferred drop even if the exit event could not reach the view.
      completeDeferredDispose()
    } else {
      dispose()
    }
  }

  override fun onConfigurationChanged(newConfig: Configuration) {
    if (!disposed) {
      lifecycleUtil.onConfigurationChanged(newConfig)
    }
  }

  @Suppress("OVERRIDE_DEPRECATION")
  override fun onLowMemory() = Unit

  fun dispose() {
    if (disposed || disposeRequested) return

    disposeRequested = true
    if (features.any { it.onDisposeRequested() }) {
      return
    }

    completeDispose()
  }

  private fun completeDispose() {
    if (disposed) return

    requestGeneration += 1
    // Close feature-owned observations before marking the host disposed so a
    // final paired event can still be dispatched or logged with the teardown.
    features.forEach { it.onDispose() }
    pendingFullscreenResumeSequence = null
    forceDetachFullscreenOverlay()
    disposed = true

    // A view can be created, emit an error (e.g. invalid_configuration), and be
    // dropped without ever attaching — so flushPendingEvents never runs.
    // Surface those latched events in the log before discarding them; the
    // bridge's contract is that a failure is never lost without a trace.
    if (pendingEvents.isNotEmpty()) {
      pendingEvents.forEach { event ->
        Log.w(TAG, "Discarding undelivered '${event.name}' event: view disposed before it was mounted")
      }
      pendingEvents.clear()
    }

    reactContext.removeLifecycleEventListener(reactLifecycleListener)
    unbindLifecycle()
    unregisterPlaybackListeners(videoView.eventEmitter)
    unregisterPersistentListeners(videoView.eventEmitter)
    pendingFeatureProps.clear()
    videoView.brightcoveMediaController?.removeListeners()
    videoView.stopPlayback()
    videoView.clear()
    videoView.playback.destroyPlayer()
    removeAllViews()
  }

  private fun applyPendingConfiguration() {
    if (disposed || disposeRequested || !sourceDirty || !configurationCommitted || !isAttachedToWindow) return

    val source = createVideoSource() ?: return
    if (source == activeSource) {
      sourceDirty = false
      return
    }

    sourceDirty = false
    lastConfigurationError = null
    activeSource = source
    requestGeneration += 1
    val generation = requestGeneration
    videoLoaded = false
    readyEmitted = false
    featureReadyVideoId = null
    sourceFailed = false
    networkRecoveryInProgress = false
    features.forEach { feature -> feature.onSourceLoading(source.videoId) }
    pendingAutoPlay = false
    playbackRequested = false
    resumeWhenAttached = false
    videoView.stopPlayback()
    videoView.clear()
    videoView.analytics.setAccount(source.accountId)
    registerPlaybackListeners(videoView.eventEmitter, generation, source)

    source.loader?.let { loader ->
      loader.loadSource(generation, source.accountId, source.policyKey)
      return
    }

    // Build the Catalog on videoView.eventEmitter — the same emitter the SDK's
    // own samples use — so its ANALYTICS_CATALOG_REQUEST/RESPONSE events reach
    // the SDK Analytics component (catalog beacons + load_time_ms). Catalog
    // only emits, never registers listeners, so reusing the shared emitter
    // across source swaps leaks nothing. Stale in-flight requests are rejected
    // by the request-generation guard in the callbacks, not by tearing down an
    // emitter (which would take the analytics listeners down with it).
    val catalog = Catalog.Builder(videoView.eventEmitter, source.accountId)
      .setPolicy(source.policyKey)
      .build()

    // Merge the query parameters every feature wants on the Playback API
    // request (SSAI adds the ad-config id here). The core stays agnostic about
    // which feature or why.
    val queryParameters = buildMap {
      features.forEach { putAll(it.additionalSourceQueryParameters()) }
    }
    val httpRequestConfig = HttpRequestConfig.Builder().apply {
      queryParameters.forEach { (key, value) -> addQueryParameter(key, value) }
    }.build()

    catalog.findVideoByID(checkNotNull(source.videoId), httpRequestConfig, object : VideoListener() {
      override fun onVideo(video: Video) {
        if (!isCurrentRequest(generation, source)) return

        videoLoaded = true
        video.properties[REQUEST_GENERATION_KEY] = generation
        // Give every feature a chance to inspect or rewrite the resolved video
        // (thumbnail-seeking normalizes preview-thumbnail URLs to HTTPS; 360
        // video reads the projection format) before ownership/add decisions
        // below. Each feature receives the previous one's returned Video.
        val loadedVideo = features.fold(video) { current, feature -> feature.onVideoLoaded(current) }
        // Let a feature take ownership of loading the video (SSAI routes it
        // through the plugin, which asynchronously fetches the VMAP and adds the
        // server-stitched stream). The core retains the autoplay intent and
        // starts only after the plugin's eventual DID_SET_VIDEO event, through
        // the same attachment/resume gate used by ordinary sources.
        pendingAutoPlay = autoPlay
        val claimed = features.any { it.willAddVideo(loadedVideo) }
        if (claimed) {
          // The feature owns processing, not lifecycle. Its asynchronous
          // callback will add the stitched video and emit DID_SET_VIDEO; the
          // core listener then decides whether it is safe to start.
          return
        }
        videoView.add(loadedVideo)
        applyVideoScalingMode()
        startPendingPlayback()
      }

      override fun onError(errors: List<CatalogError>) {
        if (!isCurrentRequest(generation, source)) return

        emitCatalogError(errors.firstOrNull())
      }
    })
  }

  // A catalog failure has two distinct shapes in the SDK (see EdgeTask): an
  // error the Playback API returned (a JSON error array, which carries a
  // catalogErrorCode like NOT_FOUND) and a transport exception thrown before
  // any response (IOException / SocketTimeoutException on an offline device),
  // which arrives with an empty catalogErrorCode and the real cause only in
  // getThrowable(). Map each on its own terms so an offline failure is
  // reported as network — not unknown — and the exception class is preserved
  // for diagnostics instead of a meaningless "catalog_error" placeholder.
  private fun emitCatalogError(error: CatalogError?) {
    val throwable = error?.throwable
    val catalogCode = error?.catalogErrorCode?.ifBlank { null }

    if (catalogCode == null && throwable != null) {
      emitSourceError(
        code = if (throwable is java.io.IOException) "network" else "unknown",
        nativeCode = throwable.javaClass.simpleName,
        message = throwable.localizedMessage
          ?: error.message?.ifBlank { null }
          ?: "Unable to retrieve the Brightcove video",
      )
      return
    }

    val nativeCode = catalogCode ?: "catalog_error"
    emitSourceError(
      code = PlayerErrorClassifier.catalogErrorCategory(nativeCode),
      nativeCode = nativeCode,
      message = error?.message?.ifBlank { null } ?: "Unable to retrieve the Brightcove video",
    )
  }

  private fun createVideoSource(): VideoSource? {
    val sourceLoaders = features.filter { it.claimsSourceLoading() }
    if (sourceLoaders.size > 1) {
      throw IllegalStateException("Multiple player features claimed the current source")
    }
    val sourceLoader = sourceLoaders.singleOrNull()

    if (sourceLoader != null && !videoId.isNullOrBlank()) {
      emitConfigurationError("videoId and a feature-owned source (offlineSourceId/videoIds) are mutually exclusive; set only one")
      return null
    }

    // Catalog credentials (accountId/policyKey) are only the core's business
    // for its own single-video path: a source-owning feature decides what its
    // mode needs (DirectUrl needs none — the doc contract says credentials
    // are ignored for it — while reference/playlist modes need both).
    val missingProps = buildList {
      if (sourceLoader == null && accountId.isNullOrBlank()) add("accountId")
      if (sourceLoader == null && policyKey.isNullOrBlank()) add("policyKey")
      if (sourceLoader == null && videoId.isNullOrBlank()) add("videoId")
    }
    if (missingProps.isNotEmpty()) {
      val message = "Missing required player properties: ${missingProps.joinToString()}"
      emitConfigurationError(message)
      return null
    }

    if (sourceLoader == null && !checkNotNull(accountId).all(Char::isDigit)) {
      emitConfigurationError("accountId must contain only digits")
      return null
    }
    if (sourceLoader == null && !checkNotNull(videoId).all(Char::isDigit)) {
      emitConfigurationError("videoId must contain only digits")
      return null
    }

    return VideoSource(
      accountId = accountId ?: "",
      policyKey = policyKey ?: "",
      videoId = if (sourceLoader == null) checkNotNull(videoId) else null,
      loader = sourceLoader,
    )
  }

  private fun isCurrentRequest(generation: Int, source: VideoSource): Boolean =
    !disposed && generation == requestGeneration && source == activeSource

  override fun isCurrentRequest(requestGeneration: Int): Boolean =
    !disposed && requestGeneration == this.requestGeneration

  override fun requestSourceReload() {
    markSourceDirty()
  }

  override fun markVideoLoaded(requestGeneration: Int, readyVideoId: String) {
    if (!isCurrentRequest(requestGeneration)) return

    setReadyVideoId(requestGeneration, readyVideoId)
    videoLoaded = true
    pendingAutoPlay = autoPlay
    startPendingPlayback()
  }

  override fun setReadyVideoId(requestGeneration: Int, readyVideoId: String) {
    if (!isCurrentRequest(requestGeneration)) return
    featureReadyVideoId = readyVideoId
  }

  override fun emitSourceLoadError(
    requestGeneration: Int,
    code: String,
    nativeCode: String,
    message: String,
  ) {
    if (!isCurrentRequest(requestGeneration)) return
    emitSourceError(code, nativeCode, message)
  }

  private fun isCurrentVideo(generation: Int, event: Event): Boolean {
    val video = event.properties[Event.VIDEO] as? Video ?: videoView.currentVideo ?: return true
    val videoGeneration = video.properties[REQUEST_GENERATION_KEY] as? Int ?: return true
    if (videoGeneration == generation) return true

    // A feature-owned asynchronous handoff can add an old video after a source
    // reset. Clear it before it can start or emit ready for the new request.
    if (videoView.currentVideo === video) {
      videoView.clear()
    }
    return false
  }
  private fun startPendingPlayback() {
    if (!disposed && !disposeRequested && pendingAutoPlay && videoLoaded && isAttachedToWindow && hostResumed) {
      pendingAutoPlay = false
      playbackRequested = true
      videoView.start()
    }
  }

  // ---- FeatureHost listener plumbing ----------------------------------------

  override fun emitEvent(name: String, payload: WritableMap) {
    if (disposed) return

    // A Fabric view can produce an event (e.g. an invalid_configuration error)
    // before it has been assigned a React tag. Dispatching then would silently
    // drop the event — the exact failure this bridge exists to surface — so
    // latch it and flush once the tag arrives (see onAttachedToWindow).
    if (id == NO_ID) {
      pendingEvents.add(PendingEvent(requestGeneration, name, payload))
      return
    }

    val eventDispatcher = UIManagerHelper.getEventDispatcher(reactContext)
    if (eventDispatcher == null) {
      pendingEvents.add(PendingEvent(requestGeneration, name, payload))
      return
    }

    eventDispatcher.dispatchEvent(
      BrightcovePlayerEvent(
        surfaceId = UIManagerHelper.getSurfaceId(this),
        viewId = id,
        name = name,
        payload = payload,
      ),
    )
  }

  override fun failSource(code: String, nativeCode: String, message: String) {
    if (disposed) return
    emitSourceError(code, nativeCode, message)
  }

  override fun registerListener(eventType: String, handler: (Event) -> Unit) {
    val generation = requestGeneration
    val source = activeSource
    val token = videoView.eventEmitter.on(eventType) { event ->
      if (source != null && isCurrentRequest(generation, source)) {
        handler(event)
      }
    }
    sourceListenerTokens.add(eventType to token)
  }

  override fun registerPersistentListener(eventType: String, handler: (Event) -> Unit) {
    val token = videoView.eventEmitter.on(eventType) { event ->
      if (!disposed) handler(event)
    }
    persistentListenerTokens.add(eventType to token)
  }

  // ---------------------------------------------------------------------------

  private fun registerPlaybackListeners(
    eventEmitter: EventEmitter,
    generation: Int,
    source: VideoSource,
  ) {
    sourceListenerTokens.add(
      EventType.ERROR to eventEmitter.on(EventType.ERROR) { event ->
        // Some non-content failures are broadcast on the shared ERROR event
        // (e.g. the IMA plugin re-emits ad failures here as well as on
        // AD_ERROR). Let any feature claim an error it owns so it is not also
        // surfaced through the content onError contract; the core stays agnostic
        // about which feature, or why.
        if (isCurrentRequest(generation, source) &&
          features.none { it.suppressesPlaybackError(event) }
        ) {
          emitPlaybackError(event)
        }
      },
    )
    // A source-selection failure (NoSourceFoundException) emits SOURCE_NOT_FOUND
    // and then a generic, untyped EventType.ERROR. SOURCE_NOT_FOUND is the
    // authoritative signal for "the video resolved but has no usable source", so
    // classify it here (as not_playable) and let it latch the source failed —
    // this is what prevents the UI from being stuck on Loading. The untyped
    // ERROR that follows carries no typed code, so emitPlaybackError ignores it
    // regardless (and here it is a no-op duplicate anyway, since sourceFailed is
    // already set).
    sourceListenerTokens.add(
      EventType.SOURCE_NOT_FOUND to eventEmitter.on(EventType.SOURCE_NOT_FOUND) {
        // The SDK emits SOURCE_NOT_FOUND with only Event.VIDEO (no Event.ERROR /
        // ERROR_MESSAGE), so there is no native detail to forward.
        if (isCurrentRequest(generation, source)) {
          emitSourceError(
            code = "not_playable",
            nativeCode = "source_not_found",
            message = "No playable source was found for the Brightcove video",
          )
        }
      },
    )
    // Ready parity with iOS. iOS fires onReady from the session's Ready
    // lifecycle event, which means "the media item is prepared" — decoded
    // enough to play, independent of whether playback has started. The Android
    // analogue is ExoPlayer reaching STATE_READY for the first time, which the
    // SDK surfaces as the first BUFFERING_COMPLETED. The player is prepared when
    // the video is added (not when start() is called), so this fires even with
    // autoPlay=false — matching iOS. Earlier candidates were wrong: DID_SET_VIDEO
    // fires before a rendition is even selected (too early), and
    // VIDEO_DURATION_CHANGED never fires for live/DVR (never, for some content).
    // The readyEmitted guard keeps this once-only, so later re-buffers (seek,
    // stall) do not re-emit.
    sourceListenerTokens.add(
      EventType.BUFFERING_COMPLETED to eventEmitter.on(EventType.BUFFERING_COMPLETED) { event ->
        if (isCurrentRequest(generation, source) &&
          isCurrentVideo(generation, event) &&
          !readyEmitted &&
          !sourceFailed
        ) {
          val readyVideoId = source.videoId?.takeIf { it.isNotBlank() }
            ?: featureReadyVideoId
            ?: (event.properties[Event.VIDEO] as? Video)?.id
          if (readyVideoId != null) {
            readyEmitted = true
            // The player (exoPlayer) now exists — apply playbackRate and volume/muted
            // state before onReady so both platforms expose the requested playback
            // state to an onReady handler.
            applyPlaybackRate()
            if (pendingVolumeApply) {
              pendingVolumeApply = false
              applyVolume()
            }
            applyVideoScalingMode()
            emitReady(readyVideoId)
          }
        }
        // A network-recovery re-prepare reaches BUFFERING_COMPLETED again
        // after readyEmitted is already true (the first-ready branch above is
        // a no-op the second time), which is exactly the signal that the
        // recovery attempt succeeded: playback is prepared again on the
        // recovered connection.
        if (isCurrentRequest(generation, source) && networkRecoveryInProgress && !sourceFailed) {
          networkRecoveryInProgress = false
          features.forEach { it.onNetworkRecoveryEnded() }
        }
      },
    )
    // Feature-owned sources such as SSAI are added asynchronously after their
    // VMAP has been processed. Start pending autoplay only after that add, and
    // let startPendingPlayback enforce attachment/resume state. Ordinary
    // sources also emit this event, but their immediate start call has already
    // consumed pendingAutoPlay, so this is idempotent.
    sourceListenerTokens.add(
      EventType.DID_SET_VIDEO to eventEmitter.on(EventType.DID_SET_VIDEO) { event ->
        if (isCurrentRequest(generation, source) && isCurrentVideo(generation, event)) {
          startPendingPlayback()
        }
      },
    )
    sourceListenerTokens.add(
      EventType.DID_SEEK_TO to eventEmitter.on(EventType.DID_SEEK_TO) {
        if (pendingSeekGeneration == generation) {
          pendingSeekGeneration = null
        }
      },
    )
    sourceListenerTokens.add(
      EventType.SEEK_TO_INCORRECT_TARGET_VALUE to eventEmitter.on(EventType.SEEK_TO_INCORRECT_TARGET_VALUE) {
        if (pendingSeekGeneration == generation) {
          pendingSeekGeneration = null
          emitCommandError(
            command = "seekTo",
            code = "invalid_argument",
            nativeCode = "seek_target_rejected",
            message = "The player rejected the requested seek position",
          )
        }
      },
    )
    sourceListenerTokens.add(
      EventType.DID_PLAY to eventEmitter.on(EventType.DID_PLAY) {
        if (isCurrentRequest(generation, source)) {
          playbackRequested = true
        }
      },
    )
    listOf(EventType.DID_PAUSE, EventType.DID_STOP).forEach { eventType ->
      sourceListenerTokens.add(
        eventType to eventEmitter.on(eventType) {
          if (isCurrentRequest(generation, source) && !inFullscreenReparentWindow) {
            playbackRequested = false
          }
        },
      )
    }
    sourceListenerTokens.add(
      EventType.COMPLETED to eventEmitter.on(EventType.COMPLETED) {
        if (!isCurrentRequest(generation, source)) return@on

        if (!loop || sourceFailed) {
          playbackRequested = false
          return@on
        }

        // ExoMediaPlayback resets and pauses the player after publishing the
        // completion event. Post the replay so it runs after that cleanup.
        videoView.post {
          if (!loop || sourceFailed || !isCurrentRequest(generation, source)) return@post
          videoView.seekTo(0L)
          videoView.start()
          playbackRequested = true
        }
      },
    )
    features.forEach { it.onRegisterPlaybackListeners() }
  }

  private fun unregisterPlaybackListeners(eventEmitter: EventEmitter) {
    sourceListenerTokens.forEach { (eventType, token) -> eventEmitter.off(eventType, token) }
    sourceListenerTokens.clear()
  }

  private fun unregisterPersistentListeners(eventEmitter: EventEmitter) {
    persistentListenerTokens.forEach { (eventType, token) -> eventEmitter.off(eventType, token) }
    persistentListenerTokens.clear()
  }

  private fun emitPlaybackError(event: Event) {
    // If the source is already marked failed, this ERROR is a duplicate of a
    // failure classified authoritatively elsewhere — the catalog echo (EdgeTask
    // re-emits catalog errors on EventType.ERROR after VideoListener.onError),
    // or the untyped ERROR the SDK emits right after SOURCE_NOT_FOUND. Those
    // authoritative paths already latched sourceFailed with the correct code,
    // and emitSourceError would no-op anyway; return so a generic error
    // never even competes with them.
    if (sourceFailed) return

    val throwable = event.properties[Event.ERROR] as? Throwable

    // Media3 surfaces a typed PlaybackException on the ERROR event (via
    // onPlayerError) whose errorCode is a documented, stable enum — the
    // authoritative classification of a playback failure, DRM included
    // (ERROR_CODE_DRM_*). A DRM session failure additionally arrives as a
    // DrmSessionException (an IOException, not a PlaybackException) that carries
    // the same @PlaybackException.ErrorCode; classify by that code too so a DRM
    // failure is reported as `drm` even on the DrmSession path.
    val errorCode = when (throwable) {
      is PlaybackException -> throwable.errorCode
      is DrmSession.DrmSessionException -> throwable.errorCode
      else -> null
    }
    if (errorCode != null) {
      if (recoverFromTransientNetworkError(errorCode)) return
      emitSourceError(
        code = PlayerErrorClassifier.playbackErrorCategory(errorCode),
        nativeCode = PlaybackException.getErrorCodeName(errorCode),
        message = throwable?.localizedMessage
          ?: event.properties[Event.ERROR_MESSAGE]?.toString()
          ?: event.properties["message"]?.toString()
          ?: "Brightcove playback failed",
      )
      return
    }

    // A source that resolves but has a delivery type ExoMediaPlayback cannot
    // build a MediaSource for (e.g. an unsupported/malformed source selected by
    // the source selector) throws untyped, with no SOURCE_NOT_FOUND and no
    // guaranteed PlaybackException to follow — see isTerminalUntypedThrowable's
    // doc for why this specific, narrow case must not be silently ignored like
    // the other untyped-error cases below (or the player hangs on Loading
    // forever: videoLoaded already true, neither onReady nor onError fires).
    if (PlayerErrorClassifier.isTerminalUntypedThrowable(throwable)) {
      emitSourceError(
        code = "not_playable",
        nativeCode = throwable?.javaClass?.simpleName ?: "unknown_terminal_error",
        message = throwable?.localizedMessage
          ?: event.properties[Event.ERROR_MESSAGE]?.toString()
          ?: "The Brightcove video has no playable source",
      )
      return
    }

    // Give a typed follow-up emitted in the same SDK turn a chance to win, but
    // do not leave a standalone untyped failure stuck in Loading forever.
    // Capture the generation at deferral time: the callback must compare
    // against a snapshot, not the live field, or a source swap inside the
    // window self-compares true and latches a stale error onto the new source.
    val token = ++pendingUntypedErrorToken
    val generation = requestGeneration
    val message = throwable?.localizedMessage
      ?: event.properties[Event.ERROR_MESSAGE]?.toString()
      ?: event.properties["message"]?.toString()
      ?: "Brightcove playback failed"
    videoView.postDelayed({
      if (token == pendingUntypedErrorToken && !sourceFailed && !disposed &&
        activeSource?.let { isCurrentRequest(generation, it) } == true
      ) {
        emitSourceError(
          code = "unknown",
          nativeCode = throwable?.javaClass?.simpleName ?: "unknown_playback_error",
          message = message,
        )
      }
    }, 100L)
  }

  // Silently re-prepares the existing ExoPlayer instance instead of reporting
  // a terminal error, for a transient network failure — see
  // NetworkRecoveryPolicy for exactly which errorCodes qualify and why.
  // Returns true if a recovery attempt was started (the caller must not also
  // emit a terminal error for this same failure); false lets the normal
  // terminal-error path run.
  private fun recoverFromTransientNetworkError(errorCode: Int): Boolean {
    if (!NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = errorCode,
        alreadyRecovering = networkRecoveryInProgress,
        videoLoaded = videoLoaded,
      )
    ) {
      return false
    }
    val player = (videoView.videoDisplay as? ExoPlayerVideoDisplayComponent)?.getExoPlayer() ?: return false

    val shouldResume = NetworkRecoveryPolicy.shouldResumeAfterRecovery(
      playbackRequested = playbackRequested,
      isPlaying = player.isPlaying,
    )
    networkRecoveryInProgress = true
    features.forEach { it.onNetworkRecoveryStarted() }
    player.prepare()
    player.playWhenReady = shouldResume
    if (shouldResume) playbackRequested = true
    return true
  }

  // A source failure (catalog fetch or playback) is terminal for the current
  // video: mark it so the ready/error paths stop emitting and a follow-up
  // error on the same request is not delivered twice.
  private fun emitSourceError(code: String, nativeCode: String, message: String) {
    if (sourceFailed) return

    pendingUntypedErrorToken += 1

    if (networkRecoveryInProgress) {
      // A recovery attempt was in flight and this is a different, terminal
      // failure overtaking it (not the recovery's own retry, which never
      // reaches here — see recoverFromTransientNetworkError's early return
      // while alreadyRecovering). The stall it started must still resolve.
      networkRecoveryInProgress = false
      features.forEach { it.onNetworkRecoveryEnded() }
    }
    features.forEach { it.onPlaybackError() }
    sourceFailed = true
    pendingAutoPlay = false
    playbackRequested = false
    emitError(code, nativeCode, message)
  }

  private fun emitConfigurationError(message: String) {
    if (message != lastConfigurationError) {
      lastConfigurationError = message
      emitError("invalid_configuration", "invalid_configuration", message)
    }
  }

  private fun markSourceDirty() {
    if (sourceDirty) {
      // There is no active source to reset, but any queued configuration error
      // belongs to the previous prop generation and must not survive a fix.
      requestGeneration += 1
      pendingSeekGeneration = null
      return
    }

    // Let source-owning features clean up native state while the old
    // generation's listeners are still attached. Fullscreen uses this to send
    // a real SDK exit request before we invalidate that source.
    features.forEach { it.onSourceWillReset() }
    pendingFullscreenResumeSequence = null
    sourceDirty = true
    sourceReset.markPending()
    requestGeneration += 1
    // Invalidate a pending deferred untyped error: it belongs to the source
    // being torn down and must not fire into the next one.
    pendingUntypedErrorToken += 1
    activeSource = null
    unregisterPlaybackListeners(videoView.eventEmitter)
    videoLoaded = false
    readyEmitted = false
    featureReadyVideoId = null
    sourceFailed = false
    // A source change can end an in-flight network recovery just as surely as
    // success or a terminal error. Keep Started/Ended balanced so a feature
    // (BufferingFeature today) can release the state it armed in Started rather
    // than carrying it into the next source generation.
    if (networkRecoveryInProgress) {
      networkRecoveryInProgress = false
      features.forEach { it.onNetworkRecoveryEnded() }
    }
    pendingAutoPlay = false
    playbackRequested = false
    pendingSeekGeneration = null
    resumeWhenAttached = false
    lastConfigurationError = null
    videoView.stopPlayback()
    videoView.clear()
  }

  private fun resetFeaturesForPendingSource() {
    if (!sourceReset.takePending()) return

    features.forEach { it.onSourceReset() }
  }

  private fun applyPendingFeatureProps() {
    if (pendingFeatureProps.isEmpty()) return

    val updates = pendingFeatureProps.toList()
    pendingFeatureProps.clear()
    updates.forEach { (feature, props) ->
      props.forEach { (name, value) -> feature.setProp(name, value) }
    }
  }

  private fun emitReady(videoId: String) {
    emitEvent(
      EVENT_READY,
      Arguments.createMap().apply { putString("videoId", videoId) },
    )
  }

  private fun emitError(code: String, nativeCode: String, message: String) {
    emitEvent(
      EVENT_ERROR,
      Arguments.createMap().apply {
        putString("code", code)
        putString("nativeCode", nativeCode)
        putString("message", message)
      },
    )
  }

  private fun flushPendingEvents() {
    if (disposed || id == NO_ID || pendingEvents.isEmpty()) return

    val queued = pendingEvents.toList()
    pendingEvents.clear()
    queued.forEach { event ->
      if (event.generation == requestGeneration) {
        emitEvent(event.name, event.payload)
      } else {
        Log.w(TAG, "Discarding stale '${event.name}' event from generation ${event.generation}")
      }
    }
  }

  private data class PendingEvent(
    val generation: Int,
    val name: String,
    val payload: WritableMap,
  )

  private data class VideoSource(
    val accountId: String,
    val policyKey: String,
    val videoId: String?,
    val loader: PlayerFeature?,
  )

  companion object {
    private const val REQUEST_GENERATION_KEY =
      "com.brightcove.reactnativeplayer.requestGeneration"
    private const val TAG = "BrightcovePlayerView"
    const val EVENT_READY = "topReady"
    const val EVENT_ERROR = "topError"
    const val EVENT_COMMAND_ERROR = "topPlayerCommandError"
  }
}
