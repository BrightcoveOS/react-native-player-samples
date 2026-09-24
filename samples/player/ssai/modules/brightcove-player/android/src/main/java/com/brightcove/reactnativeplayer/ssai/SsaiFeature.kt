package com.brightcove.reactnativeplayer.ssai

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.player.network.HttpRequestConfig
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.brightcove.ssai.SSAIComponent
import com.facebook.react.bridge.Arguments

/**
 * Server-side ad insertion (SSAI) via the Brightcove SSAI plugin.
 *
 * The customer supplies a VideoCloud ad-config id through the adConfigId prop.
 * The core adds it to the Playback API request (additionalSourceQueryParameters)
 * so VideoCloud returns a video whose source carries a VMAP URL, then hands the
 * resolved video to this feature (willAddVideo) which routes it through
 * SSAIComponent.processVideo — the plugin fetches the VMAP, rewrites the source
 * to the server-stitched stream (content + ads in one), and adds it to the view.
 *
 * Ads are stitched server-side, so unlike CSAI there is no separate ad video
 * element. Ad lifecycle is forwarded to JS as the same dedicated onAd* events
 * the ads feature uses; runtime ad errors go to onAdError, while failures before
 * the stitched stream exists go to the content onError event.
 */
class SsaiFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var ssaiComponent: SSAIComponent? = null

  // The current ad-config id. Read lazily by additionalSourceQueryParameters so
  // a value set after attach still applies to the next source load. Blank means
  // "no ads" (plain content playback).
  private var adConfigId: String? = null
  private var activeVideoId: String? = null

  override val ownedProps = setOf("adConfigId")

  // onAllAdsCompleted is intentionally absent: the SSAI plugin does not surface
  // an all-ads-completed signal (it reuses AD_BREAK_COMPLETED per pod). The
  // prop exists in the cross-platform spec for CSAI; the ssai sample omits it.
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
    // The SSAI plugin reuses the core EventType.AD_* events. Scope these
    // forwarders to the source transaction so an event queued by an outgoing
    // component cannot update the next source.
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
      "adConfigId" -> adConfigId = requireNotNull(value as? String) {
        "SsaiFeature requires a String for '$name'"
      }.ifBlank { null }
      else -> error("SsaiFeature owns no prop '$name'")
    }
  }

  // Add the ad-config id to the Playback API request so VideoCloud returns a
  // VMAP-bearing video. With no id, no parameter is added and content plays
  // without ads.
  override fun additionalSourceQueryParameters(): Map<String, String> {
    val id = adConfigId ?: return emptyMap()
    return mapOf(HttpRequestConfig.KEY_AD_CONFIG_ID to id)
  }

  // Claim the resolved video only when SSAI is actually configured. When an
  // ad-config id is set, route the video through the SSAI plugin, which
  // asynchronously fetches the VMAP, rewrites the source to the stitched
  // stream, and adds it to the view itself. The plugin's processAndStartVideo
  // calls start immediately after starting the asynchronous processing, so it
  // cannot own autoplay safely: a detached view could begin playback when its
  // VMAP request finishes. The core retains the autoplay intent and starts from
  // the eventual DID_SET_VIDEO event only when the host is attached and resumed.
  // When autoplay is off, just process (the video is added but not started).
  // With no id, return false so the core adds and starts the plain video normally.
  override fun willAddVideo(video: Video): Boolean {
    if (adConfigId == null) return false
    // SSAIComponent needs an Activity. Do not silently replace the requested
    // stitched stream with plain content when the host is not ready: that would
    // report an ad failure while still violating the adConfigId contract.
    val component = ensureComponent() ?: run {
      host.failSource(
        code = "unknown",
        nativeCode = "ssai_no_activity",
        message = "SSAI unavailable: no bound Activity when the video loaded",
      )
      return true
    }
    activeVideoId = video.id
    // Tag the video with the current request generation before handing it to
    // the plugin. The VMAP fetch + stitch is an HTTP-layer callback the core's
    // source-reset cannot cancel, and onSourceReset's removeListeners() cannot
    // stop it — but the plugin stitches IN PLACE (the added video is this same
    // object with the same properties map), so the generation tag survives and
    // the core's isCurrentVideo guard rejects and clears a stale late add.
    component.processVideo(host.tagVideoForCurrentRequest(video))
    return true
  }

  private fun isCurrentEvent(event: Event): Boolean {
    val eventVideo = event.properties[Event.VIDEO] as? Video ?: return true
    return activeVideoId == null || eventVideo.id == activeVideoId
  }

  // Tear down the SSAI component on every source change. The plugin's VMAP
  // fetch + stitch is asynchronous and, once willAddVideo has claimed a video,
  // runs outside the core's per-request generation guard. Without this, a rapid
  // source swap (A -> B) lets A's late-resolving stitch add its stream and start
  // it over B. removeListeners() detaches the component from the shared emitter
  // and stops its background tickers, so an in-flight A can no longer touch the
  // view; ensureComponent builds a fresh one for B.
  override fun onSourceReset() {
    activeVideoId = null
    ssaiComponent?.removeListeners()
    ssaiComponent = null
  }

  private fun ensureComponent(): SSAIComponent? {
    ssaiComponent?.let { return it }

    val activity = host.boundActivity ?: return null
    val component = SSAIComponent(activity, host.videoView)
    ssaiComponent = component
    return component
  }

  // Deliberately no suppressesPlaybackError override. SSAI failures split in two
  // and each is reported truthfully:
  //  - An in-ad failure while content is already stitched-and-playing arrives as
  //    AD_ERROR and is forwarded to onAdError above.
  //  - A VMAP fetch/parse failure happens before the stitched stream is ever
  //    added to the view (SSAIComponent's error path never calls videoView.add),
  //    so nothing plays — that genuinely IS a fatal content failure and must
  //    reach the content onError, which it does by not being suppressed. (This
  //    differs from CSAI, where an ad failure never blocks content, so the ads
  //    feature does suppress its shared-ERROR duplicates.)

  override fun onDispose() {
    // SSAIComponent extends AbstractComponent (listeners on the shared emitter)
    // and spins background tickers/threads; removeListeners() is the SDK's
    // teardown for all of that. Nulling the reference alone would leak them.
    ssaiComponent?.removeListeners()
    ssaiComponent = null
  }

  private fun adPayload(event: Event) = Arguments.createMap().apply {
    putString("adTitle", event.properties[Event.AD_TITLE]?.toString() ?: "")
    // The SSAI plugin's ad event carries only the raw VAST ad (no typed per-ad
    // duration), so unlike iOS's BCOVAd.duration there is no reliable seconds
    // value to report here; emit 0. This platform difference is documented on
    // AdEventData.duration in the TS contract.
    putDouble("duration", 0.0)
  }

  private fun adErrorPayload(event: Event) = Arguments.createMap().apply {
    val throwable = event.properties[Event.ERROR] as? Throwable
    val message = throwable?.localizedMessage
      ?: event.properties[Event.ERROR_MESSAGE]?.toString()
      ?: "Server-side ad insertion failed"
    // SSAI failures are VMAP/stitching failures with no typed cross-platform
    // code; report the conservative "playback" category and preserve the
    // throwable class (or a marker) in nativeCode.
    putString("code", "playback")
    putString("message", message)
    putString("nativeCode", throwable?.javaClass?.simpleName ?: "ssai_error")
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
