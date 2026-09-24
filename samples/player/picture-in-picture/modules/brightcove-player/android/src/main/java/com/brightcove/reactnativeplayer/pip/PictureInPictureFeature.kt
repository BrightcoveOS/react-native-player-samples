package com.brightcove.reactnativeplayer.pip

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import com.brightcove.player.event.EventType
import com.brightcove.player.pictureinpicture.PictureInPictureManager
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import java.lang.ref.WeakReference

/**
 * Picture-in-Picture: registers the hosting Activity with the SDK's
 * PictureInPictureManager, auto-enters PiP when the app is backgrounded WHILE
 * PLAYING, keeps the PiP window video-shaped, hides the app's chrome while PiP
 * is active, and reports enter/exit to JS.
 */
class PictureInPictureFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var pictureInPictureEnabled = false
  private var sourceLoaded = false
  private var sourceReady = false
  private var pipRegistered = false
  // PipOwnership is process-wide while this feature is per view. Track the
  // acquisition separately from pipRegistered so each owner is released once,
  // including registration paths that stop before reaching the SDK.
  private var ownsPipOwnership = false
  private var pipActive = false
  // Whether the current source is genuinely playing. PiP entry (auto-enter on
  // S+, onUserLeave pre-31) is gated on this: entering while paused/stopped/
  // errored would background into a blank or frozen PiP window, which Android
  // explicitly warns against.
  private var isPlaying = false
  private val deferredDispose = DeferredDisposeCoordinator()
  // Cached result of the manifest-flag check (see
  // supportsPictureInPictureManifestFlag): null until first checked, then fixed
  // for the lifetime of this feature instance — the manifest cannot change at
  // runtime, so there is no need to re-query PackageManager on every playback
  // state change, and this also lets the missing-flag warning log only once.
  private var manifestSupportsPip: Boolean? = null
  private data class HiddenView(
    val view: View,
    val originalVisibility: Int,
  )

  private val pipHiddenViews = mutableListOf<HiddenView>()

  override val keepsPlaybackAliveInBackground: Boolean
    get() = pictureInPictureEnabled

  override val ownedProps = setOf("pictureInPictureEnabled")

  override val exportedEvents = mapOf(
    EVENT_PIP_MODE_CHANGED to "onPictureInPictureModeChanged",
  )

  override val supportedCommands = setOf("enterPictureInPicture")

  override fun attach(host: FeatureHost) {
    this.host = host
    host.registerPersistentListener(EventType.DID_ENTER_PICTURE_IN_PICTURE_MODE) {
      setPictureInPictureActive(true)
    }
    host.registerPersistentListener(EventType.DID_EXIT_PICTURE_IN_PICTURE_MODE) {
      setPictureInPictureActive(false)
      // A real system exit finally lets a deferred teardown complete. But this
      // listener and the SDK's own DID_EXIT_PICTURE_IN_PICTURE_MODE listener
      // (added inside PictureInPictureManager.registerActivity, which always
      // runs after this attach()) share the same EventEmitter, which invokes
      // listeners for one event in registration order — so this listener always
      // fires BEFORE the SDK's own. The SDK's own handler is what unregisters
      // its media-action broadcast receiver, reading the activity reference that
      // unregisterActivity() would otherwise already have cleared. Calling
      // finalizeUnregister() synchronously here would run ahead of that handler
      // and leak the receiver. Posting to the main-thread queue defers it until
      // after the SDK's own handler — next in the same dispatch pass — has run.
      deferredDispose.completeAfterSystemExit(
        postToMain = { callback -> Handler(Looper.getMainLooper()).post(callback) },
        finalizeSdkRegistration = ::finalizeUnregister,
        completeCoreDispose = host::completeDeferredDispose,
      )
    }
    // The PiP aspect ratio depends on the decoded video size, which is not
    // known until playback prepares. Refresh the params once it is.
    host.registerPersistentListener(EventType.VIDEO_SIZE_KNOWN) {
      if (pipRegistered) applyPictureInPictureParams()
    }
  }

  override fun setProp(name: String, value: Any?) {
    check(name == "pictureInPictureEnabled") {
      "PictureInPictureFeature does not own prop '$name'"
    }
    // pictureInPictureEnabled is initialization-only, to match iOS (where the
    // PiP button is baked into the control layout at player-view creation) and
    // the TS contract. The value is always recorded so state stays truthful,
    // but only the value settled before the first source loads takes effect.
    pictureInPictureEnabled = value == true
    if (!sourceLoaded) {
      if (pictureInPictureEnabled) {
        registerPictureInPictureIfNeeded()
      } else {
        // The initialization window is still open, so a true -> false update
        // must undo a pre-source registration or waiter entry rather than leave
        // a disabled view owning the process-wide SDK singleton.
        requestTeardown()
      }
    } else if (!pictureInPictureEnabled && pipRegistered && ownsPipOwnership) {
      // Initialization-only refers to registration, not to the entry paths:
      // leaving auto-enter/setOnUserLeaveHint armed after a disable would let
      // the app background into a PiP window the app asked to turn off (and
      // emit changed(true) for it). Disarm entry; the registration stays for
      // the deterministic teardown on dispose.
      //
      // Only the registered owner may touch the entry paths: PiP registration
      // and the pre-31 manager flag are process-wide, so a non-owning view
      // (a waiter, or a view that never registered) disarming here would
      // also disarm the owning view's player.
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        host.boundActivity?.let { activity ->
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            setPictureInPictureParamsSafely(
              activity,
              PictureInPictureParams.Builder().build(),
            )
          }
        }
      } else {
        PictureInPictureManager.getInstance().setOnUserLeaveEnabled(false)
      }
    }
  }

  override fun handleCommand(name: String): Boolean {
    if (name == "enterPictureInPicture") {
      enterPictureInPicture()
      return true
    }
    return false
  }

  private fun enterPictureInPicture() {
    if (host.isDisposed) return

    if (!pictureInPictureEnabled) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "disabled",
        message = "Picture-in-Picture is disabled on this player",
        nativeCode = "pip_disabled",
      )
      return
    }

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "unavailable",
        message = "Picture-in-Picture requires Android 8.0 (API 26) or later",
        nativeCode = "unsupported_api_level",
      )
      return
    }

    val activity = host.boundActivity
    if (activity == null) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "unavailable",
        message = "Cannot enter Picture-in-Picture: host activity is not available",
        nativeCode = "no_activity",
      )
      return
    }

    if (!supportsPictureInPictureManifestFlag(activity)) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "unavailable",
        message = "Activity manifest is missing android:supportsPictureInPicture",
        nativeCode = "manifest_missing_pip",
      )
      return
    }

    if (!pipRegistered) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "unavailable",
        message = "Picture-in-Picture is not registered or ownership is unavailable",
        nativeCode = "pip_not_registered",
      )
      return
    }

    if (!sourceReady) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "not_ready",
        message = "Cannot enter Picture-in-Picture: player source is not ready",
        nativeCode = "source_not_ready",
      )
      return
    }

    if (pipActive || activity.isInPictureInPictureMode) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "invalid_state",
        message = "Player is already in Picture-in-Picture mode",
        nativeCode = "already_in_pip",
      )
      return
    }

    try {
      applyPictureInPictureParams()
      PictureInPictureManager.getInstance().enterPictureInPictureMode()
    } catch (e: Exception) {
      host.emitCommandError(
        command = "enterPictureInPicture",
        code = "failed",
        message = e.localizedMessage ?: "Failed to enter Picture-in-Picture mode",
        nativeCode = e.javaClass.simpleName,
      )
    }
  }

  override fun onActivityBound(activity: Activity) {
    registerPictureInPictureIfNeeded()
  }

  override fun onRegisterPlaybackListeners() {
    // Media has resolved and playback listeners are being registered: close the
    // initialization window so pictureInPictureEnabled changes are not applied
    // live after this point, matching iOS's initialization-only semantics.
    sourceLoaded = true
    // Entry must track playback state: only auto-enter/onUserLeave-enter while
    // the source is actually playing. These are per-source listeners, so they
    // are re-registered for each new source and torn down on source change.
    isPlaying = false
    refreshEntryEnabled()
    // Readiness must track the same boundary the core uses for
    // ensureCommandReady (BUFFERING_COMPLETED / onReady), not DID_SET_VIDEO:
    // the imperative PiP command must not succeed while play/pause/seek are
    // still rejected as not_ready for the same source.
    host.registerListener(EventType.BUFFERING_COMPLETED) {
      sourceReady = true
    }
    host.registerListener(EventType.DID_PLAY) {
      isPlaying = true
      refreshEntryEnabled()
    }
    listOf(
      EventType.DID_PAUSE,
      EventType.DID_STOP,
      EventType.COMPLETED,
      EventType.ERROR,
    ).forEach { eventType ->
      host.registerListener(eventType) {
        isPlaying = false
        refreshEntryEnabled()
      }
    }
  }

  override fun onSourceReset() {
    sourceReady = false
    // A new source is (re)loading; it is not playing yet, so stop entering PiP
    // until DID_PLAY fires again.
    isPlaying = false
    refreshEntryEnabled()
  }

  override fun onSourceWillReset() {
    sourceReady = false
    isPlaying = false
    refreshEntryEnabled()
  }

  override fun onLayoutChanged() {
    if (pipRegistered) applyPictureInPictureParams()
  }

  override fun onDisposeRequested(): Boolean {
    if (pipRegistered && host.boundActivity?.isInPictureInPictureMode == true) {
      // Do not tear the view down while the system still owns its PiP window.
      // Brightcove's DID_EXIT listener unregisters the SDK media-action receiver;
      // removing that listener early leaks the receiver and its Play/Pause path
      // dereferences the null video view after unregisterActivity().
      sourceReady = false
      isPlaying = false
      refreshEntryEnabled()
      return deferredDispose.defer()
    }
    return false
  }

  override fun onDispose() {
    sourceReady = false
    requestTeardown()
  }

  private fun setPictureInPictureActive(active: Boolean) {
    if (pipActive == active) return
    pipActive = active
    applyPictureInPictureChrome(active)
    host.emitEvent(
      EVENT_PIP_MODE_CHANGED,
      Arguments.createMap().apply { putBoolean("active", active) },
    )
  }

  // Android scales the whole Activity window into the PiP window, so any UI laid
  // out beside the player would be captured too. React Native will not repaint
  // its paused view tree during PiP, so hiding that chrome from JS does not take
  // effect. Instead, hide the player's immediate sibling views natively while
  // PiP is active and restore them on exit. Only immediate siblings are touched
  // (the walk stops at the player's direct parent) so unrelated app UI further
  // up a real navigation hierarchy is left alone.
  private fun applyPictureInPictureChrome(active: Boolean) {
    if (active) {
      pipHiddenViews.clear()
      val parent = host.hostView.parent as? ViewGroup ?: return
      for (i in 0 until parent.childCount) {
        val sibling = parent.getChildAt(i)
        if (sibling !== host.hostView && sibling.visibility == View.VISIBLE) {
          pipHiddenViews.add(HiddenView(sibling, sibling.visibility))
          sibling.visibility = View.INVISIBLE
        }
      }
    } else {
      for (hiddenView in pipHiddenViews) {
        // Do not overwrite a visibility change made by another owner while PiP
        // was active; restore only the state this feature changed.
        if (hiddenView.view.visibility == View.INVISIBLE) {
          hiddenView.view.visibility = hiddenView.originalVisibility
        }
      }
      pipHiddenViews.clear()
    }
  }

  // The SDK's PictureInPictureManager is a process-wide singleton bound to a
  // single Activity + video view: registering a second view rebinds it and
  // tears the first one's listeners down, and either view's unregister removes
  // the shared registration. A per-view boolean cannot represent that, so
  // ownership is coordinated across instances (see PipOwnership): the first
  // enabled view acquires PiP; a second enabled view is queued as a waiter and,
  // when the owner releases, ownership is handed off to it so PiP is not
  // permanently unavailable to it.
  private fun registerPictureInPictureIfNeeded() {
    if (host.isDisposed || pipRegistered || !pictureInPictureEnabled) return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val activity = host.boundActivity ?: return
    // Do this before acquiring ownership or registering the SDK. Catching a
    // params-update exception later still leaves an apparently registered view
    // whose teardown can call the same framework API again; a missing manifest
    // flag means PiP is unavailable, not "registered but degraded".
    if (!supportsPictureInPictureManifestFlag(activity)) return

    if (!PipOwnership.tryAcquire(this)) {
      Log.w(
        TAG,
        "Deferring pictureInPictureEnabled: another BrightcovePlayerView owns " +
          "Picture-in-Picture for this app (the Brightcove SDK supports one " +
          "PiP-registered player at a time). This view is queued and will " +
          "acquire PiP when the current owner releases it.",
      )
      return
    }
    ownsPipOwnership = true
    completeRegistration(activity)
  }

  private fun completeRegistration(activity: Activity) {
    PictureInPictureManager.getInstance().registerActivity(activity, host.videoView)
    pipRegistered = true
    // Entry starts disabled and is enabled only once playback begins.
    refreshEntryEnabled()
    applyPictureInPictureParams()
  }

  // Enable PiP entry only while playing. On S+ the auto-enter flag lives in the
  // PiP params (refreshed here); pre-31 uses the SDK's forwarded onUserLeaveHint,
  // toggled through the manager. Called on registration and on every playback
  // state change.
  //
  // Pre-31, setOnUserLeaveEnabled(true) is the ONLY thing standing between a
  // background transition and a crash: MainActivity.onUserLeaveHint forwards to
  // PictureInPictureManager.onUserLeaveHint(), which — if this flag is set —
  // calls Activity.enterPictureInPictureMode() directly, with no try/catch
  // anywhere in the SDK. That framework call throws IllegalStateException if
  // the Activity is missing android:supportsPictureInPicture in the manifest.
  // applyPictureInPictureParams()'s try/catch (below) only covers the S+
  // setPictureInPictureParams call — it never runs on this branch — so without
  // this check the same misconfiguration that safely degrades on S+ crashes
  // the app on API 26-30 the moment the user backgrounds it.
  private fun refreshEntryEnabled() {
    if (!pipRegistered) return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      applyPictureInPictureParams()
    } else {
      val activity = host.boundActivity
      val canEnter = isPlaying && activity != null && supportsPictureInPictureManifestFlag(activity)
      PictureInPictureManager.getInstance().setOnUserLeaveEnabled(canEnter)
    }
  }

  // Reads the same manifest flag Activity.enterPictureInPictureMode() itself
  // requires, so we can refuse to arm onUserLeaveHint entry rather than let the
  // framework throw when the user backgrounds the app. Cached after the first
  // check (see manifestSupportsPip) so a missing flag logs once, not on every
  // play/pause.
  //
  // ActivityInfo.FLAG_SUPPORTS_PICTURE_IN_PICTURE (0x400000) is not on the
  // public SDK — it is annotated @hide in AOSP — but it is the stable bit the
  // framework sets in ActivityInfo.flags when the manifest declares
  // android:supportsPictureInPicture="true", the same flag
  // ActivityInfo.supportsPictureInPicture() reads internally. There is no
  // public API to query this, so the literal is duplicated here.
  private fun supportsPictureInPictureManifestFlag(activity: Activity): Boolean {
    manifestSupportsPip?.let { return it }
    val flags = try {
      activity.packageManager.getActivityInfo(activity.componentName, 0).flags
    } catch (e: PackageManager.NameNotFoundException) {
      0
    }
    val supported = flags and FLAG_SUPPORTS_PICTURE_IN_PICTURE != 0
    manifestSupportsPip = supported
    if (!supported) {
      Log.e(
        TAG,
        "pictureInPictureEnabled requires android:supportsPictureInPicture=\"true\" " +
          "on the hosting Activity in AndroidManifest.xml; Picture-in-Picture " +
          "is disabled until that is added.",
      )
    }
    return supported
  }

  // Applies the PiP params. Aspect ratio + source-rect hint are supported since
  // API 26 (Oreo), so they are always applied when known — that is what makes
  // the PiP window show the video (not the whole letterboxed Activity) and
  // animate from the video's on-screen rect. Auto-enter and seamless-resize are
  // API 31+ only; auto-enter is gated on playback so a backgrounded, paused
  // player does not slide into a frozen PiP window.
  private fun applyPictureInPictureParams() {
    val activity = host.boundActivity ?: return
    if (!pictureInPictureEnabled) return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    setPictureInPictureParamsSafely(activity, buildPictureInPictureParams())
  }

  // Every framework params update — including teardown's auto-enter disable —
  // goes through this one path. Android throws IllegalStateException when the
  // Activity does not support PiP and IllegalArgumentException for invalid
  // parameters; neither developer configuration nor an unusual rendition may
  // crash the host app on the main thread.
  private fun setPictureInPictureParamsSafely(
    activity: Activity,
    params: PictureInPictureParams,
  ) {
    try {
      activity.setPictureInPictureParams(params)
    } catch (e: IllegalStateException) {
      // Thrown when the Activity is missing android:supportsPictureInPicture in
      // the manifest. This is a developer misconfiguration, but a reference
      // bridge that customers copy must not crash the host app over it: log a
      // clear, actionable error and degrade (PiP simply will not enter) rather
      // than take the whole app down on the main thread.
      Log.e(
        TAG,
        "pictureInPictureEnabled requires android:supportsPictureInPicture=\"true\" " +
          "on the hosting Activity in AndroidManifest.xml; Picture-in-Picture is " +
          "disabled until that is added.",
        e,
      )
    } catch (e: IllegalArgumentException) {
      // The system also rejects params it considers invalid (historically an
      // out-of-range aspect ratio — "Aspect ratio is too extreme"). We already
      // clamp the ratio to the documented range, so this should not happen, but
      // never let a bad rendition crash the main thread: log and skip this
      // params update rather than take the app down.
      Log.w(TAG, "Skipping Picture-in-Picture params update: ${e.message}")
    }
  }

  @RequiresApi(Build.VERSION_CODES.O)
  private fun buildPictureInPictureParams(): PictureInPictureParams {
    val builder = PictureInPictureParams.Builder()

    // Auto-enter + seamless resize are API 31+ only. Auto-enter follows the
    // playback state so a paused/stopped player does not background into PiP.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      builder.setAutoEnterEnabled(isPlaying)
      builder.setSeamlessResizeEnabled(true)
    }

    // The PiP window must match the video's aspect ratio, not the (full-screen,
    // portrait) player view's. Use the decoded video size and a source-rect hint
    // of the actual video area within the view.
    val videoWidth = host.videoView.videoWidth
    val videoHeight = host.videoView.videoHeight
    if (videoWidth > 0 && videoHeight > 0) {
      builder.setAspectRatio(clampedAspectRatio(videoWidth, videoHeight))
      videoAreaWithinView(videoWidth, videoHeight)?.let { builder.setSourceRectHint(it) }
    }
    return builder.build()
  }

  // Android accepts a PiP aspect ratio only within roughly [1:2.39, 2.39:1];
  // outside that it throws IllegalArgumentException("Aspect ratio is too
  // extreme"). A legitimately wide rendition (e.g. 1920x800 = 2.4:1) exceeds it,
  // so clamp to the supported range while preserving orientation (a too-wide
  // video clamps to the widest allowed, a too-tall one to the tallest).
  private fun clampedAspectRatio(width: Int, height: Int): Rational {
    val ratio = width.toDouble() / height.toDouble()
    return when {
      ratio > MAX_ASPECT -> Rational(MAX_ASPECT_NUM, MAX_ASPECT_DEN)
      ratio < MIN_ASPECT -> Rational(MAX_ASPECT_DEN, MAX_ASPECT_NUM)
      else -> Rational(width, height)
    }
  }

  // The rectangle (in Activity-window coordinates) covered by the video inside
  // this full-screen, letterboxed player, used as the PiP source-rect hint so
  // the enter animation starts from the video, not the black bars. Null until
  // laid out.
  private fun videoAreaWithinView(videoWidth: Int, videoHeight: Int): Rect? {
    val view = host.hostView
    if (view.width == 0 || view.height == 0 || !view.isAttachedToWindow) return null
    val location = IntArray(2)
    view.getLocationInWindow(location)

    val viewRatio = view.width.toFloat() / view.height.toFloat()
    val videoRatio = videoWidth.toFloat() / videoHeight.toFloat()
    val fittedWidth: Int
    val fittedHeight: Int
    if (videoRatio > viewRatio) {
      fittedWidth = view.width
      fittedHeight = (view.width / videoRatio).toInt()
    } else {
      fittedHeight = view.height
      fittedWidth = (view.height * videoRatio).toInt()
    }
    val offsetX = location[0] + (view.width - fittedWidth) / 2
    val offsetY = location[1] + (view.height - fittedHeight) / 2
    return Rect(offsetX, offsetY, offsetX + fittedWidth, offsetY + fittedHeight)
  }

  // Tear PiP down before the first source loads or during the core's final
  // disposal after a non-PiP drop.
  //
  // Android exposes no API to programmatically leave PiP, so if the Activity is
  // physically in the PiP window we must NOT fabricate an exit: emitting
  // active:false and unregistering here would (a) tell JS PiP ended while the
  // system window is still open, and (b) remove the SDK's DID_EXIT handler,
  // whose only job is to unregister the media-action receiver the SDK added on
  // DID_ENTER — leaking it. Instead we stop further entry immediately and defer
  // the real unregister to the DID_EXIT the system delivers when the user
  // returns to the app. The core now defers the whole native disposal while PiP
  // is active, so this method never removes the SDK exit handler underneath a
  // still-open system PiP window.
  private fun requestTeardown() {
    if (!pipRegistered) {
      if (pipActive) setPictureInPictureActive(false)
      releasePipOwnership()
      return
    }

    // Stop any further entry right away, on both routes.
    isPlaying = false
    refreshEntryEnabled()

    val inSystemPip = host.boundActivity?.isInPictureInPictureMode == true
    if (inSystemPip) {
      return
    }
    finalizeUnregister()
  }

  private fun finalizeUnregister() {
    if (!pipRegistered) {
      releasePipOwnership()
      return
    }

    if (pipActive) setPictureInPictureActive(false)
    val activity = host.boundActivity
    if (activity != null) {
      PictureInPictureManager.getInstance().unregisterActivity(activity)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        setPictureInPictureParamsSafely(
          activity,
          PictureInPictureParams.Builder().setAutoEnterEnabled(false).build(),
        )
      }
    }
    pipRegistered = false
    // Hand PiP off to a view that asked for it while we owned it, so a queued
    // second player becomes active instead of staying enabled-but-inactive.
    releasePipOwnership()
  }

  private fun releasePipOwnership() {
    if (!ownsPipOwnership) {
      PipOwnership.cancelWaiter(this)
      return
    }
    ownsPipOwnership = false
    PipOwnership.releaseOwner(this)?.let { it.registerPictureInPictureIfNeeded() }
  }

  // Process-wide single-owner coordination for the PiP singleton, with a waiter
  // queue so ownership is handed off rather than lost. Holds only weak
  // references so a leaked/destroyed view cannot pin ownership or block the
  // queue forever.
  private object PipOwnership {
    private var owner: WeakReference<PictureInPictureFeature>? = null
    private val waiters = ArrayDeque<WeakReference<PictureInPictureFeature>>()

    @Synchronized
    fun tryAcquire(feature: PictureInPictureFeature): Boolean {
      // Drop any waiters whose feature has been GC'd so the queue cannot grow
      // unbounded with dead references (this object is process-global).
      waiters.removeAll { it.get() == null }
      val current = owner?.get()
      if (current != null && current !== feature) {
        if (waiters.none { it.get() === feature }) {
          waiters.addLast(WeakReference(feature))
        }
        return false
      }
      owner = WeakReference(feature)
      return true
    }

    // Release ownership held by `feature` and return the next live waiter, if
    // any, so the caller can hand PiP to it. A non-owner must not advance the
    // queue: disposing a queued view must only remove itself.
    @Synchronized
    fun releaseOwner(feature: PictureInPictureFeature): PictureInPictureFeature? {
      if (owner?.get() !== feature && owner?.get() != null) return null

      owner = null
      waiters.removeAll { it.get() == null || it.get() === feature }
      while (waiters.isNotEmpty()) {
        val next = waiters.removeFirst().get()
        if (next != null) return next
      }
      return null
    }

    @Synchronized
    fun cancelWaiter(feature: PictureInPictureFeature) {
      waiters.removeAll { it.get() == null || it.get() === feature }
    }
  }

  companion object {
    private const val TAG = "PictureInPictureFeature"
    const val EVENT_PIP_MODE_CHANGED = "topPictureInPictureModeChanged"

    // Android's supported PiP aspect-ratio bounds: max ~2.39:1 (and its inverse
    // for the min). Expressed as a rational to clamp without float drift.
    private const val MAX_ASPECT_NUM = 239
    private const val MAX_ASPECT_DEN = 100
    private const val MAX_ASPECT = MAX_ASPECT_NUM.toDouble() / MAX_ASPECT_DEN
    private const val MIN_ASPECT = MAX_ASPECT_DEN.toDouble() / MAX_ASPECT_NUM

    // See supportsPictureInPictureManifestFlag: ActivityInfo.flags bit set from
    // the manifest's android:supportsPictureInPicture attribute. Not on the
    // public SDK (hidden in AOSP as ActivityInfo.FLAG_SUPPORTS_PICTURE_IN_PICTURE).
    private const val FLAG_SUPPORTS_PICTURE_IN_PICTURE = 0x400000
  }
}
