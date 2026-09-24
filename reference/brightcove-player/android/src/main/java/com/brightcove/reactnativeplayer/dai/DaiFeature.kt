package com.brightcove.reactnativeplayer.dai

import com.brightcove.dai.GoogleDAIComponent
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import com.google.ads.interactivemedia.v3.api.AdError
import com.google.ads.interactivemedia.v3.api.AdEvent

/**
 * Google Dynamic Ad Insertion (DAI) feature using the Brightcove Android DAI plugin
 * (GoogleDAIComponent).
 */
class DaiFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var daiComponent: GoogleDAIComponent? = null

  private var daiSourceId: String? = null
  private var daiVideoId: String? = null
  private var sourceGeneration = 0
  private var activeVideoIds = emptySet<String>()
  private var daiStreamReady = false

  override val ownedProps = setOf("daiSourceId", "daiVideoId")

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

  override fun onRegisterPlaybackListeners() {
    host.registerListener(EventType.AD_BREAK_STARTED) { event ->
      if (isCurrentEvent(event)) {
        host.emitEvent(
          EVENT_AD_BREAK_STARTED,
          Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
        )
      }
    }
    host.registerListener(EventType.AD_BREAK_COMPLETED) { event ->
      if (isCurrentEvent(event)) {
        host.emitEvent(
          EVENT_AD_BREAK_ENDED,
          Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
        )
      }
    }
    host.registerListener(EventType.AD_STARTED) { event ->
      if (isCurrentEvent(event)) host.emitEvent(EVENT_AD_STARTED, adPayload(event))
    }
    host.registerListener(EventType.AD_COMPLETED) { event ->
      if (isCurrentEvent(event)) host.emitEvent(EVENT_AD_COMPLETED, adPayload(event))
    }
    host.registerListener(EventType.AD_ERROR) { event ->
      if (isCurrentEvent(event)) host.emitEvent(EVENT_AD_ERROR, adErrorPayload(event))
    }
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "daiSourceId" -> daiSourceId = requireNotNull(value as? String) {
        "DaiFeature requires a String for '$name'"
      }.ifBlank { null }
      "daiVideoId" -> daiVideoId = requireNotNull(value as? String) {
        "DaiFeature requires a String for '$name'"
      }.ifBlank { null }
      else -> error("DaiFeature does not own prop '$name'")
    }
  }

  override fun willAddVideo(video: Video): Boolean {
    val sourceId = daiSourceId ?: return false
    val videoId = daiVideoId ?: return false

    if (host.isDisposed) return false

    val component = GoogleDAIComponent.Builder(host.videoView, host.eventEmitter).build()
    daiComponent = component
    activeVideoIds = setOf(video.id)
    val requestGeneration = sourceGeneration

    component.setFallbackVideo(video)
    component.addCallback(object : GoogleDAIComponent.Listener {
      override fun onStreamReady(daiVideo: Video) {
        if (!host.isDisposed && requestGeneration == sourceGeneration && daiComponent === component) {
          daiStreamReady = true
          activeVideoIds += daiVideo.id
          host.videoView.add(host.tagVideoForCurrentRequest(host.onVideoLoaded(daiVideo)))
        }
      }
      override fun onContentComplete() {}
    })

    component.requestVOD(sourceId, videoId, null)

    return true
  }

  // Claim every DAI ad failure: the plugin always attaches a fallback video
  // (setFallbackVideo below), so a failed stream request — invalid ids, stream
  // unavailable — falls back to plain-content playback rather than failing the
  // source, and the fallback reaching BUFFERING_COMPLETED emits onReady
  // normally. The failure is reported once, through onAdError, while the
  // fallback keeps the session alive; letting the shared AdError ERROR reach
  // the content onError instead would latch sourceFailed and suppress the
  // fallback's onReady — a playing video the UI reports as failed.
  override fun suppressesPlaybackError(event: Event): Boolean =
    event.properties[Event.ERROR] is AdError

  override fun onSourceReset() {
    sourceGeneration += 1
    activeVideoIds = emptySet()
    releaseDaiComponent()
  }

  override fun onDispose() {
    sourceGeneration += 1
    activeVideoIds = emptySet()
    releaseDaiComponent()
  }

  private fun releaseDaiComponent() {
    val component = daiComponent ?: return
    daiComponent = null
    val streamReady = daiStreamReady
    daiStreamReady = false
    component.removeListeners()
    if (streamReady) {
      component.onRelease()
    } else {
      // GoogleDAIComponent.onRelease() dereferences stream-only managers that
      // are null until the asynchronous stream callback completes. clean() is
      // its null-safe inherited resource cleanup for an in-flight request.
      component.clean()
    }
  }

  private fun isCurrentEvent(event: Event): Boolean {
    val eventVideo = event.properties[Event.VIDEO] as? Video ?: return true
    return eventVideo.id in activeVideoIds
  }

  private fun adPayload(event: Event) = Arguments.createMap().apply {
    val ad = (event.properties["adEvent"] as? AdEvent)?.ad
    putString("adTitle", ad?.title ?: event.properties[Event.AD_TITLE]?.toString() ?: "")
    putDouble("duration", ad?.duration ?: 0.0)
  }

  private fun adErrorPayload(event: Event) = Arguments.createMap().apply {
    val adError = event.properties[Event.ERROR] as? AdError
    val message = adError?.message
      ?: event.properties[Event.ERROR_MESSAGE]?.toString()
      ?: "DAI ad playback failed"
    val code = when (adError?.errorType) {
      AdError.AdErrorType.LOAD -> "load"
      AdError.AdErrorType.PLAY -> "playback"
      else -> "unknown"
    }
    val nativeCode = adError?.errorCodeNumber?.toString() ?: "dai_ad_error"
    putString("code", code)
    putString("message", message)
    putString("nativeCode", nativeCode)
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
