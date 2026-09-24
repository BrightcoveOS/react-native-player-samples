package com.brightcove.reactnativeplayer.background

import android.Manifest
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Player
import com.brightcove.playback.notification.BackgroundPlaybackNotification
import com.brightcove.player.event.EventType
import com.brightcove.player.playback.ExoMediaPlayback
import com.brightcove.player.playback.PlaybackNotification
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature

/**
 * Connects the Brightcove ExoPlayer to the SDK's foreground-service/media
 * notification integration. The notification implementation is process-wide,
 * so active players are handed ownership one at a time.
 */
internal object BackgroundPlaybackConfiguration {
  const val MEDIA_PLAYBACK_SERVICE = "com.brightcove.playback.notification.MediaPlaybackService"

  fun requiredManifestPermissions(sdkInt: Int): Set<String> = buildSet {
    add(Manifest.permission.FOREGROUND_SERVICE)
    if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      add(Manifest.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK)
    }
  }
}

class BackgroundPlaybackFeature : PlayerFeature {
  private var host: FeatureHost? = null
  private var notification: PlaybackNotification? = null
  private var enabled = false

  override val keepsPlaybackAliveInBackground: Boolean
    get() = enabled

  override val ownedProps: Set<String> = setOf("backgroundPlaybackEnabled")

  override val exportedEvents: Map<String, String> = emptyMap()

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun onActivityBound(activity: android.app.Activity) {
    if (enabled) {
      validateHostConfiguration()
      configureNotification()
      if (host?.videoView?.isPlaying == true) {
        BackgroundPlaybackNotificationOwner.acquire(this)
      }
    }
  }

  override fun setProp(name: String, value: Any?) {
    check(name == "backgroundPlaybackEnabled") { "Unsupported background playback prop: $name" }
    enabled = value as? Boolean ?: error("backgroundPlaybackEnabled must be a Boolean")
    if (enabled) {
      validateHostConfiguration()
      configureNotification()
      if (host?.videoView?.isPlaying == true) {
        BackgroundPlaybackNotificationOwner.acquire(this)
      }
    } else {
      BackgroundPlaybackNotificationOwner.release(this)
      // The core's onPause/onStop lifecycle callbacks are no-ops while this
      // feature reports keepsPlaybackAliveInBackground=true, and they already
      // ran once for the current backgrounding — they will not run again just
      // because this prop flipped. If the host is not resumed at the moment
      // this feature is disabled, playback would otherwise keep running with
      // no notification and no foreground-service justification for it: pause
      // it directly, the same outcome the core's own onPause would have
      // produced had the feature not been suppressing it.
      host?.let { it.reevaluateBackgroundPolicy() }
    }
  }

  override fun onSourceReset() {
    BackgroundPlaybackNotificationOwner.release(this)
  }

  override fun onRegisterPlaybackListeners() {
    host?.registerListener(EventType.DID_PLAY) {
      if (enabled) BackgroundPlaybackNotificationOwner.acquire(this)
    }
    host?.registerListener(EventType.DID_PAUSE) {
      BackgroundPlaybackNotificationOwner.promoteIfOwnerPaused(this)
    }
    listOf(EventType.DID_STOP, EventType.COMPLETED, EventType.ERROR).forEach { eventType ->
      host?.registerListener(eventType) {
        BackgroundPlaybackNotificationOwner.release(this)
      }
    }
  }

  override fun onDispose() {
    BackgroundPlaybackNotificationOwner.release(this)
    host = null
    notification = null
  }

  internal val isEligibleForNotification: Boolean
    get() = enabled && host?.isDisposed == false && host?.videoView?.isPlaying == true

  internal fun attachNotificationOwnership() {
    check(Looper.myLooper() == Looper.getMainLooper()) {
      "Background playback ownership must be attached on the main thread"
    }
    val featureHost = host ?: return
    val featureNotification = notification ?: return
    val playback = featureHost.videoView.playback as? ExoMediaPlayback
      ?: error("Background playback requires Brightcove's ExoMediaPlayback")
    playback.setPlaybackNotification(featureNotification)
    featureNotification.setPlayback(playback)
    featureNotification.show()
  }

  internal fun detachNotificationOwnership() {
    check(Looper.myLooper() == Looper.getMainLooper()) {
      "Background playback ownership must be detached on the main thread"
    }
    notification?.cancel()
  }

  private fun validateHostConfiguration() {
    val activity = host?.boundActivity ?: return
    val packageManager = activity.packageManager
    val packageName = activity.packageName
    val requiredPermissions = BackgroundPlaybackConfiguration.requiredManifestPermissions(Build.VERSION.SDK_INT)
    val missingPermissions = requiredPermissions.filter {
      packageManager.checkPermission(it, packageName) != PackageManager.PERMISSION_GRANTED
    }
    check(missingPermissions.isEmpty()) {
      "backgroundPlaybackEnabled requires manifest permissions: ${missingPermissions.joinToString()}"
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      check(activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
        "backgroundPlaybackEnabled requires a runtime POST_NOTIFICATIONS grant on Android 13+"
      }
    }
    val serviceInfo = packageManager.getServiceInfo(
      ComponentName(packageName, BackgroundPlaybackConfiguration.MEDIA_PLAYBACK_SERVICE),
      PackageManager.GET_META_DATA,
    )
    check(serviceInfo.enabled) {
      "backgroundPlaybackEnabled requires the Brightcove MediaPlaybackService in the app manifest"
    }
  }

  private fun configureNotification() {
    val featureHost = host ?: return
    val configuredNotification = BackgroundPlaybackNotification.getInstance(featureHost.videoView.context)
      ?: error("Brightcove background playback notification is unavailable")
    configuredNotification.setStreamTypes(
      PlaybackNotification.StreamType.Audio,
      PlaybackNotification.StreamType.Video,
      PlaybackNotification.StreamType.AudioLive,
      PlaybackNotification.StreamType.VideoLive,
      PlaybackNotification.StreamType.AudioLiveDvr,
      PlaybackNotification.StreamType.VideoLiveDvr,
    )
    notification = configuredNotification
  }
}

private object BackgroundPlaybackNotificationOwner {
  private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
  private val ownership = NotificationOwnershipState<BackgroundPlaybackFeature>()

  fun acquire(feature: BackgroundPlaybackFeature) {
    runOnMain { acquireOnMain(feature) }
  }

  fun release(feature: BackgroundPlaybackFeature) {
    runOnMain { releaseOnMain(feature) }
  }

  fun promoteIfOwnerPaused(feature: BackgroundPlaybackFeature) {
    runOnMain { promoteIfOwnerPausedOnMain(feature) }
  }

  private fun runOnMain(action: () -> Unit) {
    if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
      action()
    } else {
      mainHandler.post(action)
    }
  }

  private fun acquireOnMain(feature: BackgroundPlaybackFeature) {
    check(android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
    val transition = ownership.acquire(feature) { it.isEligibleForNotification } ?: return
    transition.previous?.detachNotificationOwnership()
    transition.next?.attachNotificationOwnership()
  }

  private fun releaseOnMain(feature: BackgroundPlaybackFeature) {
    check(android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
    val transition = ownership.release(feature) { it.isEligibleForNotification } ?: return
    transition.previous?.detachNotificationOwnership()
    transition.next?.attachNotificationOwnership()
  }

  private fun promoteIfOwnerPausedOnMain(feature: BackgroundPlaybackFeature) {
    check(android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
    val transition = ownership.promoteIfOwnerPaused(feature) { it.isEligibleForNotification } ?: return
    transition.previous?.detachNotificationOwnership()
    transition.next?.attachNotificationOwnership()
  }
}
