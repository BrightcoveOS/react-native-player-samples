package com.brightcove.reactnativeplayer.cast

import android.app.Activity
import android.util.Log
import android.view.Gravity
import android.widget.FrameLayout
import androidx.mediarouter.app.MediaRouteButton
import com.brightcove.cast.GoogleCastComponent
import com.brightcove.cast.GoogleCastEventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.cast.framework.CastStateListener
import com.google.android.gms.common.GooglePlayServicesNotAvailableException
import com.google.android.gms.common.GooglePlayServicesRepairableException

/**
 * Google Cast (Chromecast) via the Brightcove Google Cast plugin.
 *
 * When castEnabled is set, this wires a GoogleCastComponent to the player's
 * event emitter — the plugin listens for the SDK's playback events and, once a
 * receiver is selected through the cast button, hands the current video off to
 * the Cast device (and back to local playback when the session ends). A
 * MediaRouteButton is overlaid on the player so a receiver can be chosen
 * without an ActionBar (the RN host Activity has none), and Cast connection
 * state is reported to JS through onCastStateChanged.
 *
 * Initialization-only: the component and button are wired the first time the
 * prop turns on with an Activity bound; toggling it off later is a no-op beyond
 * what teardown does on dispose. Cast discovery needs a real Chromecast on the
 * same network — an emulator finds no devices (state stays no_devices).
 */
class CastFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var castEnabled = false
  private var castComponent: GoogleCastComponent? = null
  private var castButton: MediaRouteButton? = null
  private var castContext: CastContext? = null
  private var castStateListener: CastStateListener? = null

  override val ownedProps = setOf("castEnabled")

  override val exportedEvents = mapOf(
    EVENT_CAST_STATE_CHANGED to "onCastStateChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    check(name == "castEnabled") { "CastFeature does not own prop '$name'" }
    val enabled = requireNotNull(value as? Boolean) {
      "CastFeature requires a Boolean for '$name'"
    }
    if (castEnabled == enabled) return
    castEnabled = enabled
    if (enabled) {
      setUpCastIfNeeded()
    } else {
      tearDownCast()
    }
  }

  override fun onActivityBound(activity: Activity) {
    setUpCastIfNeeded()
  }

  private fun setUpCastIfNeeded() {
    if (host.isDisposed || castComponent != null || !castEnabled) return
    val activity = host.boundActivity ?: return

    // CastContext initialization talks to Google Play services and throws when
    // it is missing or needs an update (common on bare emulators). Cast is an
    // optional enhancement, not core playback, so a missing Play services must
    // not crash the player: report no_devices and stop, rather than failing.
    val context = try {
      CastContext.getSharedInstance(activity)
    } catch (e: GooglePlayServicesNotAvailableException) {
      Log.w(TAG, "Google Cast unavailable: Google Play services not available", e)
      emitCastState(CAST_STATE_UNKNOWN)
      return
    } catch (e: GooglePlayServicesRepairableException) {
      Log.w(TAG, "Google Cast unavailable: Google Play services needs an update", e)
      emitCastState(CAST_STATE_UNKNOWN)
      return
    } catch (e: RuntimeException) {
      Log.w(TAG, "Google Cast unavailable: CastContext initialization failed", e)
      emitCastState(CAST_STATE_UNKNOWN)
      return
    }
    castContext = context

    // The plugin observes the video view's emitter and drives the local<->cast
    // hand-off itself; autoPlay resumes playback on the receiver on connect.
    castComponent = GoogleCastComponent.Builder(host.videoView.eventEmitter, activity)
      .setAutoPlay(true)
      .build()

    addCastButton()

    val listener = CastStateListener { state -> emitCastState(mapCastState(state)) }
    context.addCastStateListener(listener)
    castStateListener = listener
    // Emit the current state immediately so JS starts from the truth rather than
    // waiting for the first change.
    emitCastState(mapCastState(context.castState))
  }

  // The RN host Activity has no ActionBar/menu to hang the standard cast button
  // on, so add a MediaRouteButton directly over the player (top-right). This is
  // the same button CastButtonFactory wires elsewhere; here it is attached to a
  // view instead of a menu item.
  private fun addCastButton() {
    val activity = host.boundActivity ?: return
    val button = MediaRouteButton(activity)
    CastButtonFactory.setUpMediaRouteButton(activity.applicationContext, button)
    val params = FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.WRAP_CONTENT,
      FrameLayout.LayoutParams.WRAP_CONTENT,
    ).apply { gravity = Gravity.TOP or Gravity.END }
    host.hostView.addView(button, params)
    castButton = button
  }

  private fun mapCastState(state: Int): String = normalizedCastState(state)

  private fun emitCastState(state: String) {
    host.emitEvent(
      EVENT_CAST_STATE_CHANGED,
      Arguments.createMap().apply { putString("state", state) },
    )
  }

  private fun tearDownCast() {
    castStateListener?.let { castContext?.removeCastStateListener(it) }
    castStateListener = null
    castContext = null
    // GoogleCastComponent's constructor registers its own CastPlayer as a
    // SessionManagerListener on the app-wide CastContext.getSessionManager()
    // singleton. removeListeners() only detaches the Brightcove EventEmitter
    // listeners this component added via addListener() — it does NOT release
    // the CastPlayer, so that SessionManagerListener would otherwise stay
    // registered on the singleton for the rest of the process lifetime, every
    // time a castEnabled view is disposed (a real, unbounded leak across
    // repeated mounts). The only way to release it is emitting DESTROY_CAST on
    // the same emitter: the component's own OnDestroyCastListener is what calls
    // castPlayer.release() — there is no public release()/destroy() method to
    // call directly. Emit before removeListeners() so this handler is still
    // registered to receive it.
    castComponent?.let { host.videoView.eventEmitter.emit(GoogleCastEventType.DESTROY_CAST) }
    castComponent?.removeListeners()
    castComponent = null
    castButton?.let { host.hostView.removeView(it) }
    castButton = null
  }

  override fun onDispose() {
    tearDownCast()
  }

  companion object {
    internal fun normalizedCastState(state: Int): String = when (state) {
      CastState.NO_DEVICES_AVAILABLE -> CAST_STATE_NO_DEVICES
      CastState.NOT_CONNECTED -> CAST_STATE_NOT_CONNECTED
      CastState.CONNECTING -> CAST_STATE_CONNECTING
      CastState.CONNECTED -> CAST_STATE_CONNECTED
      else -> CAST_STATE_UNKNOWN
    }

    private const val TAG = "CastFeature"
    private const val EVENT_CAST_STATE_CHANGED = "topCastStateChanged"

    private const val CAST_STATE_NO_DEVICES = "no_devices"
    private const val CAST_STATE_NOT_CONNECTED = "not_connected"
    private const val CAST_STATE_CONNECTING = "connecting"
    private const val CAST_STATE_CONNECTED = "connected"
    private const val CAST_STATE_UNKNOWN = "unknown"
  }
}
