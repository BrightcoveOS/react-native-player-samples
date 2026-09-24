package com.brightcove.reactnativeplayer.freewheel

import android.app.Activity
import android.view.View
import android.view.ViewGroup
import com.brightcove.freewheel.controller.FreeWheelController
import com.brightcove.freewheel.event.FreeWheelEventType
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import tv.freewheel.ad.interfaces.IAdContext
import tv.freewheel.ad.interfaces.IConstants
import tv.freewheel.ad.interfaces.ISlot
import tv.freewheel.ad.request.config.AdRequestConfiguration
import tv.freewheel.ad.request.config.TemporalSlotConfiguration
import tv.freewheel.ad.request.config.VideoAssetConfiguration

class FreeWheelFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var freeWheelController: FreeWheelController? = null
  private val displayAdViews = mutableListOf<View>()
  private var sourceGeneration = 0
  private val pendingDisplayAdRunnables = mutableListOf<Runnable>()

  private var adUrl: String? = null
  private var networkId: Int = 0
  private var profile: String? = null
  private var siteSectionId: String? = null
  private var videoAssetId: String? = null

  override val ownedProps = setOf(
    "freeWheelAdUrl",
    "freeWheelNetworkId",
    "freeWheelProfile",
    "freeWheelSiteSectionId",
    "freeWheelVideoAssetId",
  )

  override val exportedEvents = mapOf(
    EVENT_AD_STARTED to "onAdStarted",
    EVENT_AD_COMPLETED to "onAdCompleted",
    EVENT_AD_BREAK_STARTED to "onAdBreakStarted",
    EVENT_AD_BREAK_ENDED to "onAdBreakEnded",
    EVENT_AD_ERROR to "onAdError",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "freeWheelAdUrl" -> adUrl = (value as? String)?.ifBlank { null }
      "freeWheelNetworkId" -> networkId = (value as? Number)?.toInt() ?: 0
      "freeWheelProfile" -> profile = (value as? String)?.ifBlank { null }
      "freeWheelSiteSectionId" -> siteSectionId = (value as? String)?.ifBlank { null }
      "freeWheelVideoAssetId" -> {
        videoAssetId = (value as? String)?.ifBlank { null }
      }
      else -> error("FreeWheelFeature owns no prop '$name'")
    }
  }

  override fun onActivityBound(activity: Activity) {
    ensureFreeWheelController()
  }

  private fun ensureFreeWheelController() {
    if (freeWheelController != null || host.isDisposed) return
    val currentAdUrl = adUrl ?: return
    if (networkId <= 0) return
    if (profile.isNullOrBlank() || siteSectionId.isNullOrBlank()) return
    val activity = host.boundActivity ?: return

    val controller = FreeWheelController(activity, host.videoView, host.eventEmitter)
    controller.setAdURL(currentAdUrl)
    controller.setAdNetworkId(networkId)
    profile?.let { controller.setProfile(it) }
    siteSectionId?.let { controller.setSiteSectionId(it) }
    controller.enable()

    freeWheelController = controller
  }

  override fun onRegisterPlaybackListeners() {
    sourceGeneration += 1
    host.registerListener(EventType.AD_BREAK_STARTED) {
      host.emitEvent(
        EVENT_AD_BREAK_STARTED,
        Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
      )
    }
    host.registerListener(EventType.AD_BREAK_COMPLETED) {
      host.emitEvent(
        EVENT_AD_BREAK_ENDED,
        Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
      )
    }
    host.registerListener(EventType.AD_STARTED) { event ->
      host.emitEvent(EVENT_AD_STARTED, adPayload(event))
    }
    host.registerListener(EventType.AD_COMPLETED) { event ->
      host.emitEvent(EVENT_AD_COMPLETED, adPayload(event))
    }
    host.registerListener(EventType.AD_ERROR) { event ->
      host.emitEvent(EVENT_AD_ERROR, adErrorPayload(event))
    }
    host.registerListener(FreeWheelEventType.SHOW_DISPLAY_ADS) { event ->
      val currentGeneration = sourceGeneration
      val slots = event.properties[FreeWheelController.AD_SLOTS_KEY] as? List<*>
        ?: return@registerListener
      var runnable: Runnable? = null
      runnable = Runnable {
        pendingDisplayAdRunnables.remove(runnable)
        if (host.isDisposed || sourceGeneration != currentGeneration) return@Runnable
        removeDisplayAds()
        slots.filterIsInstance<ISlot>().forEach { slot ->
          val view = slot.base
          (view.parent as? ViewGroup)?.removeView(view)
          host.hostView.addView(
            view,
            ViewGroup.LayoutParams(
              ViewGroup.LayoutParams.WRAP_CONTENT,
              ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
          )
          displayAdViews += view
          slot.play()
        }
      }
      pendingDisplayAdRunnables += runnable
      host.hostView.post(runnable)
    }
    host.registerListener(FreeWheelEventType.WILL_SUBMIT_AD_REQUEST) { event ->
      val adContext = event.properties[FreeWheelController.AD_CONTEXT_KEY] as? IAdContext
        ?: error("FreeWheel did not provide an ad context")
      val adRequestConfig = event.properties[FreeWheelController.AD_REQUEST_CONFIGURATION_KEY]
        as? AdRequestConfiguration
        ?: error("FreeWheel did not provide an ad request configuration")
      val adConstants = adContext.constants
      val video = event.properties[Event.VIDEO] as? Video
        ?: error("FreeWheel did not provide the current video")
      val durationSec = if (video.durationLong > 0) video.durationLong / 1000.0 else 0.0
      val assetId = videoAssetId?.takeIf { it.isNotBlank() } ?: video.id

      if (assetId != null) {
        adRequestConfig.videoAssetConfiguration = VideoAssetConfiguration(
          assetId,
          IConstants.IdType.CUSTOM,
          durationSec,
          IConstants.VideoAssetDurationType.EXACT,
          IConstants.VideoAssetAutoPlayType.ATTENDED,
        )
      }

      adRequestConfig.addSlotConfiguration(
        TemporalSlotConfiguration("preroll", adConstants.ADUNIT_PREROLL(), 0.0),
      )
      if (durationSec > 0.0) {
        adRequestConfig.addSlotConfiguration(
          TemporalSlotConfiguration("midroll", adConstants.ADUNIT_MIDROLL(), durationSec / 2.0),
        )
        adRequestConfig.addSlotConfiguration(
          TemporalSlotConfiguration("postroll", adConstants.ADUNIT_POSTROLL(), durationSec),
        )
      }
    }
    ensureFreeWheelController()
  }

  override fun onDispose() {
    sourceGeneration += 1
    cancelPendingDisplayAds()
    removeDisplayAds()
    freeWheelController?.disable()
    freeWheelController = null
  }

  override fun onSourceReset() {
    sourceGeneration += 1
    cancelPendingDisplayAds()
    removeDisplayAds()
  }

  private fun cancelPendingDisplayAds() {
    pendingDisplayAdRunnables.forEach { host.hostView.removeCallbacks(it) }
    pendingDisplayAdRunnables.clear()
  }

  private fun removeDisplayAds() {
    displayAdViews.forEach { view ->
      (view.parent as? ViewGroup)?.removeView(view)
    }
    displayAdViews.clear()
  }

  private fun adPayload(event: Event) = Arguments.createMap().apply {
    // FreeWheelAnalytics exposes an ad identifier but no stable title or
    // duration on AD_STARTED/AD_COMPLETED. Do not substitute the content
    // duration or an identifier into those fields; zero/empty means unknown.
    putString("adTitle", event.properties[Event.AD_TITLE]?.toString() ?: "")
    putDouble("duration", 0.0)
  }

  private fun adErrorPayload(event: Event) = Arguments.createMap().apply {
    val error = event.properties[Event.ERROR]
    val message = event.properties[Event.ERROR_MESSAGE]?.toString()
      ?: (error as? Throwable)?.message
      ?: "FreeWheel ad playback failed"
    putString("code", "unknown")
    putString("message", message)
    putString("nativeCode", "freewheel_ad_error")
  }

  companion object {
    private const val UNKNOWN_AD_BREAK_INDEX = -1
    private const val EVENT_AD_STARTED = "topAdStarted"
    private const val EVENT_AD_COMPLETED = "topAdCompleted"
    private const val EVENT_AD_BREAK_STARTED = "topAdBreakStarted"
    private const val EVENT_AD_BREAK_ENDED = "topAdBreakEnded"
    private const val EVENT_AD_ERROR = "topAdError"
  }
}
