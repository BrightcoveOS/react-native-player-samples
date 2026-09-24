package com.brightcove.reactnativeplayer.ads

import com.brightcove.ima.BaseIMAComponent
import com.brightcove.ima.GoogleIMAComponent
import com.brightcove.ima.GoogleIMAEventType
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import com.google.ads.interactivemedia.v3.api.Ad
import com.google.ads.interactivemedia.v3.api.AdError
import com.google.ads.interactivemedia.v3.api.AdEvent
import com.google.ads.interactivemedia.v3.api.AdsManager
import com.google.ads.interactivemedia.v3.api.AdsRequest
import com.google.ads.interactivemedia.v3.api.ImaSdkFactory

/**
 * Client-side ad insertion via Google IMA (CSAI), VMAP ("ad rules") only.
 *
 * The customer supplies a single VMAP ad-tag URL through the adTagUrl prop; the
 * VMAP response defines the whole pre/mid/post schedule, so the app never has
 * to place cue points (that is the VAST model, which this feature intentionally
 * does not support). The GoogleIMAComponent is built once, when the video view
 * is available, and inserts itself into the playback pipeline; it asks for the
 * ad tag each time it is about to load ads, via ADS_REQUEST_FOR_VIDEO.
 *
 * Ad lifecycle events are forwarded to JS as dedicated onAd* events. Ad errors
 * go to onAdError, never the content onError: the core asks features to claim
 * their own errors (suppressesPlaybackError) and this feature claims the IMA
 * ones — an ad failing does not mean the video failed.
 */
class AdsFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var imaComponent: GoogleIMAComponent? = null

  // The AdsManager we attached an ALL_ADS_COMPLETED listener to, and that
  // listener, retained so both can be detached on teardown. The manager is
  // owned by the IMA plugin (created per source load); our listener holds a
  // strong reference to this view, so it must be removed on dispose or a
  // repeatedly created/destroyed Fabric view leaks through it.
  private var adsManager: AdsManager? = null
  private var allAdsCompletedListener: AdEvent.AdEventListener? = null
  // True from onSourceLoading until the source is reset or disposed. A source a
  // feature owns (a videoIds queue, a source-loading mode, an offline download)
  // reaches onSourceLoading with no videoId, so an empty sourceVideoId cannot
  // stand for "no active source".
  private var sourceActive = false
  private var sourceVideoId = ""
  private var sourceVideo: Video? = null
  private var adBreakActive = false

  // The current VMAP tag. Read lazily inside the ADS_REQUEST_FOR_VIDEO handler
  // (not captured once) so a tag set after the component is built still applies
  // to the next ad request. Blank means "no ads".
  private var adTagUrl: String? = null

  override val ownedProps = setOf("adTagUrl")

  override fun play(): Boolean {
    if (!adBreakActive) return false
    adsManager?.resume()
    return adsManager != null
  }

  override fun pause(): Boolean {
    if (!adBreakActive) return false
    adsManager?.pause()
    return adsManager != null
  }

  override val exportedEvents = mapOf(
    EVENT_AD_STARTED to "onAdStarted",
    EVENT_AD_COMPLETED to "onAdCompleted",
    EVENT_AD_BREAK_STARTED to "onAdBreakStarted",
    EVENT_AD_BREAK_ENDED to "onAdBreakEnded",
    EVENT_ALL_ADS_COMPLETED to "onAllAdsCompleted",
    EVENT_AD_ERROR to "onAdError",
    EVENT_AD_PAUSED to "onAdPaused",
    EVENT_AD_RESUMED to "onAdResumed",
    EVENT_AD_PROGRESS to "onAdProgress",
    EVENT_AD_QUARTILE to "onAdQuartile",
    EVENT_AD_SKIPPED to "onAdSkipped",
    EVENT_AD_INTERACTION to "onAdInteraction",
    EVENT_AD_METADATA to "onAdMetadata",
    EVENT_AD_OVERLAY_STATE_CHANGED to "onAdOverlayStateChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun onSourceLoading(videoId: String?) {
    sourceActive = true
    sourceVideoId = videoId.orEmpty()
    sourceVideo = null
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "adTagUrl" -> {
        adTagUrl = (value as? String)?.ifBlank { null }
        // The component only needs to exist once there is a tag to serve. It is
        // safe to build eagerly here: with no tag the ADS_REQUEST_FOR_VIDEO
        // handler declines to request ads, so a blank tag plays content only.
        ensureImaComponent()
      }
      else -> error("AdsFeature owns no prop '$name'")
    }
  }

  // Claim the IMA plugin's ad failures so the core does not also report them as
  // content errors. The plugin re-emits every ad failure on the shared ERROR
  // event carrying an IMA AdError as Event.ERROR; a content/ExoPlayer error
  // never does. Keying off the error type (not a property key like AD_ID, which
  // the plugin omits when the failure happens before an ad player exists — i.e.
  // exactly the ad-load case) reliably covers load and playback failures alike.
  override fun suppressesPlaybackError(event: Event): Boolean =
    event.properties[Event.ERROR] is AdError

  private fun ensureImaComponent() {
    if (imaComponent != null || host.isDisposed) return

    val eventEmitter = host.eventEmitter

    // Forward the ad lifecycle to JS. These are persistent (view-lifetime)
    // listeners: ad events are not scoped to a single catalog request, and the
    // IMA component itself outlives source swaps.
    host.registerPersistentListener(EventType.AD_BREAK_STARTED) { event ->
      if (!isCurrentEvent(event) || adBreakActive) return@registerPersistentListener
      adBreakActive = true
      // The IMA plugin plays ads on its own ExoPlayer (an ExoAdPlayer built
      // with a fresh player), which never receives the SDK's SET_VOLUME
      // event — without this, a muted or low-volume app plays ads at full
      // volume. iOS is unaffected: its ads share the session's AVPlayer.
      applyVolumeToAdPlayer()
      host.emitEvent(
        EVENT_AD_BREAK_STARTED,
        Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
      )
    }
    host.registerPersistentListener(EventType.SET_VOLUME) {
      // A volume/mute change made while an ad is playing must reach the ad
      // player too (persistent: the core emits this on every apply, including
      // outside ad breaks, where applying to a detached ad PlayerView is a
      // harmless no-op through the null player guard).
      if (adBreakActive) applyVolumeToAdPlayer()
    }
    host.registerPersistentListener(EventType.DID_SET_VIDEO) { event ->
      val video = event.properties[Event.VIDEO] as? Video ?: return@registerPersistentListener
      if (video.id == sourceVideoId) {
        sourceVideo = video
      }
    }
    host.registerPersistentListener(EventType.AD_BREAK_COMPLETED) { event ->
      // The IMA plugin emits adBreakCompleted for a normally-finished pod with
      // {adInsights, sendVideoResumed?} — no Event.VIDEO property — so
      // isCurrentEvent() (which requires it) always drops the event and
      // adBreakActive stays latched, suppressing every later pod and rerouting
      // play()/pause() to a finished AdsManager. Guard on adBreakActive alone:
      // it is set only by an AD_BREAK_STARTED the same source produced and is
      // cleared on source reset, so it names the current source's break.
      if (!adBreakActive) return@registerPersistentListener
      adBreakActive = false
      host.emitEvent(
        EVENT_AD_BREAK_ENDED,
        Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
      )
    }
    host.registerPersistentListener(EventType.AD_STARTED) { event ->
      if (!isCurrentEvent(event)) return@registerPersistentListener
      host.emitEvent(EVENT_AD_STARTED, adPayload(event))
    }
    host.registerPersistentListener(EventType.AD_COMPLETED) { event ->
      if (!isCurrentEvent(event)) return@registerPersistentListener
      val adEvent = event.properties[BaseIMAComponent.AD_EVENT] as? AdEvent
      if (adEvent?.type == AdEvent.AdEventType.SKIPPED) {
        val adId = adIdForEvent(event)
        if (adId.isNotEmpty()) {
          host.emitEvent(
            EVENT_AD_SKIPPED,
            Arguments.createMap().apply { putString("adId", adId) },
          )
        }
      }
      host.emitEvent(EVENT_AD_COMPLETED, adPayload(event))
    }
    host.registerPersistentListener(EventType.AD_PAUSED) { event ->
      if (!isCurrentEvent(event)) return@registerPersistentListener
      val adId = adIdForEvent(event)
      if (adId.isEmpty()) return@registerPersistentListener
      host.emitEvent(
        EVENT_AD_PAUSED,
        Arguments.createMap().apply { putString("adId", adId) },
      )
    }
    host.registerPersistentListener(EventType.AD_RESUMED) { event ->
      if (!isCurrentEvent(event)) return@registerPersistentListener
      val adId = adIdForEvent(event)
      if (adId.isEmpty()) return@registerPersistentListener
      host.emitEvent(
        EVENT_AD_RESUMED,
        Arguments.createMap().apply { putString("adId", adId) },
      )
    }
    host.registerPersistentListener(EventType.AD_PROGRESS) { event ->
      if (!isCurrentEvent(event)) return@registerPersistentListener
      val posMs = (event.properties[Event.PLAYHEAD_POSITION_LONG] as? Number)?.toLong() ?: 0L
      val durMs = (event.properties[Event.VIDEO_DURATION_LONG] as? Number)?.toLong() ?: 0L
      val adId = adIdForEvent(event)
      if (adId.isEmpty()) return@registerPersistentListener
      host.emitEvent(
        EVENT_AD_PROGRESS,
        Arguments.createMap().apply {
          putString("adId", adId)
          putDouble("positionSeconds", posMs / 1000.0)
          putDouble("durationSeconds", durMs / 1000.0)
        },
      )
    }
    // The plugin emits both AD_ERROR and DID_FAIL_TO_PLAY_AD for a single
    // failure; listen to only AD_ERROR so JS gets exactly one onAdError.
    host.registerPersistentListener(EventType.AD_ERROR) { event ->
      if (!isCurrentEvent(event)) return@registerPersistentListener
      host.emitEvent(EVENT_AD_ERROR, adErrorPayload(event))
    }

    // onAllAdsCompleted has no dedicated Brightcove event: the plugin consumes
    // Google IMA's ALL_ADS_COMPLETED internally. Attach directly to the
    // AdsManager (delivered on ADS_MANAGER_LOADED) to observe it honestly,
    // rather than guessing from a postroll heuristic. ADS_MANAGER_LOADED fires
    // once per source load, each time with a fresh AdsManager that the plugin
    // destroys on source change. Detach from any previous manager first, and
    // retain the new manager + listener so both can be removed on dispose —
    // otherwise the listener (which references this view) outlives it.
    host.registerPersistentListener(GoogleIMAEventType.ADS_MANAGER_LOADED) { event ->
      if (!isCurrentEvent(event)) return@registerPersistentListener
      detachAllAdsCompletedListener()
      val manager = event.properties[BaseIMAComponent.ADS_MANAGER] as? AdsManager ?: return@registerPersistentListener
      val observedManager = manager
      val listener = AdEvent.AdEventListener { adEvent ->
        if (adsManager !== observedManager || !sourceActive) return@AdEventListener
        when (adEvent.type) {
          AdEvent.AdEventType.ALL_ADS_COMPLETED -> {
            host.emitEvent(
              EVENT_ALL_ADS_COMPLETED,
              Arguments.createMap().apply { putBoolean("completed", true) },
            )
          }
          AdEvent.AdEventType.SKIPPED -> {
            adEvent.ad?.let { ad ->
              if (!ad.isLinear) emitAdOverlayState(adIdForEvent(event), false)
            }
          }
          AdEvent.AdEventType.FIRST_QUARTILE -> {
            emitAdQuartile(adEvent, 25)
          }
          AdEvent.AdEventType.MIDPOINT -> {
            emitAdQuartile(adEvent, 50)
          }
          AdEvent.AdEventType.THIRD_QUARTILE -> {
            emitAdQuartile(adEvent, 75)
          }
          AdEvent.AdEventType.CLICKED -> {
            emitAdInteraction(adEvent, "clicked")
          }
          AdEvent.AdEventType.TAPPED -> {
            emitAdInteraction(adEvent, "tapped")
          }
          AdEvent.AdEventType.STARTED -> {
            emitAdMetadata(adEvent.ad)
            adEvent.ad?.let { ad ->
              if (!ad.isLinear) emitAdOverlayState(adIdForEvent(event), true)
            }
          }
          AdEvent.AdEventType.COMPLETED -> {
            adEvent.ad?.let { ad ->
              if (!ad.isLinear) emitAdOverlayState(adIdForEvent(event), false)
            }
          }
          else -> Unit
        }
      }
      manager.addAdEventListener(listener)
      adsManager = manager
      allAdsCompletedListener = listener
    }

    // Supply the ad tag when IMA asks. Reading adTagUrl here (not at build
    // time) means the latest prop value is always used.
    host.registerPersistentListener(GoogleIMAEventType.ADS_REQUEST_FOR_VIDEO) { event ->
      val tag = adTagUrl
      if (tag != null) {
        val adsRequest = ImaSdkFactory.getInstance().createAdsRequest().apply {
          // Inside this apply block the receiver is the AdsRequest, so
          // `adTagUrl` resolves to AdsRequest.setAdTagUrl (the SDK property),
          // NOT this feature's own adTagUrl field of the same name. `tag` is
          // that field's value, captured above.
          adTagUrl = tag
        }
        event.properties[BaseIMAComponent.ADS_REQUESTS] = arrayListOf<AdsRequest>(adsRequest)
      }
      // Always respond, even with no ADS_REQUESTS: that tells the IMA plugin
      // "no ads for this video, play the content" and unblocks the pipeline.
      // Failing to respond would stall playback waiting for an ad request.
      eventEmitter.respond(event)
    }

    imaComponent = GoogleIMAComponent.Builder(host.videoView, eventEmitter)
      .setUseAdRules(true)
      .build()
  }

  override fun onSourceReset() {
    // The IMA plugin destroys the AdsManager on a source change. Drop our
    // listener + manager reference now rather than waiting for the next
    // ADS_MANAGER_LOADED (which never arrives if the new source has no ads), so
    // we never hold a listener attached to a destroyed manager.
    sourceActive = false
    sourceVideoId = ""
    sourceVideo = null
    adBreakActive = false
    detachAllAdsCompletedListener()
  }

  override fun onDispose() {
    // GoogleIMAComponent extends AbstractComponent and registers listeners on
    // the shared videoView.eventEmitter (plus IMA ad listeners); nulling the
    // reference alone leaks them past this view's disposal, which matters
    // because Fabric creates and destroys views repeatedly. removeListeners()
    // is the SDK's teardown for those registrations. Our own AdsManager
    // listener is not covered by it, so detach that too.
    sourceActive = false
    sourceVideoId = ""
    sourceVideo = null
    adBreakActive = false
    detachAllAdsCompletedListener()
    imaComponent?.clean()
    imaComponent?.removeListeners()
    imaComponent = null
  }

  private fun isCurrentEvent(event: Event): Boolean =
    isCurrentAdEvent(
      event = event,
      sourceActive = sourceActive,
      sourceVideoId = sourceVideoId,
      sourceVideo = sourceVideo,
      currentRequestGeneration = host.currentRequestGeneration,
    )

  // The plugin inflates brightcove_ad_player (an androidx.media3.ui.PlayerView)
  // into the video view's container; its player is the ad's ExoPlayer. Walking
  // the hierarchy is the only supported route — ExoAdPlayer exposes no volume
  // API and its player field is package-private. No-ops when the ad view is not
  // (yet/any longer) attached or its player is unset.
  private fun applyVolumeToAdPlayer() {
    if (host.isDisposed) return
    val adPlayer = findAdPlayerView(host.videoView)?.player ?: return
    adPlayer.volume = host.effectiveVolume
  }

  private fun findAdPlayerView(group: android.view.ViewGroup): androidx.media3.ui.PlayerView? {
    for (i in 0 until group.childCount) {
      val child = group.getChildAt(i) ?: continue
      if (child is androidx.media3.ui.PlayerView) return child
      if (child is android.view.ViewGroup) {
        findAdPlayerView(child)?.let { return it }
      }
    }
    return null
  }

  private fun emitAdMetadata(ad: Ad?) {
    if (ad == null || ad.adId.isNullOrEmpty() || host.isDisposed) return
    host.emitEvent(
      EVENT_AD_METADATA,
      Arguments.createMap().apply {
        putString("adId", ad.adId ?: "")
        putString("adTitle", ad.title ?: "")
        putString("advertiserName", ad.advertiserName ?: "")
        putDouble("durationSeconds", ad.duration)
        putBoolean("isLinear", ad.isLinear)
        putInt("width", ad.width)
        putInt("height", ad.height)
        putBoolean("isSkippable", ad.isSkippable)
        putDouble("skipTimeOffsetSeconds", ad.skipTimeOffset)
      },
    )
  }

  private fun emitAdOverlayState(adId: String, visible: Boolean) {
    if (adId.isEmpty() || host.isDisposed) return
    host.emitEvent(
      EVENT_AD_OVERLAY_STATE_CHANGED,
      Arguments.createMap().apply {
        putString("adId", adId)
        putBoolean("visible", visible)
      },
    )
  }

  private fun emitAdQuartile(adEvent: AdEvent, quartile: Int) {
    val adId = adEvent.ad?.adId.orEmpty()
    if (adId.isEmpty() || host.isDisposed) return
    host.emitEvent(
      EVENT_AD_QUARTILE,
      Arguments.createMap().apply {
        putString("adId", adId)
        putInt("quartile", quartile)
      },
    )
  }

  private fun emitAdInteraction(adEvent: AdEvent, interaction: String) {
    val adId = adEvent.ad?.adId.orEmpty()
    if (adId.isEmpty() || host.isDisposed) return
    host.emitEvent(
      EVENT_AD_INTERACTION,
      Arguments.createMap().apply {
        putString("adId", adId)
        putString("interaction", interaction)
      },
    )
  }

  // Remove the ALL_ADS_COMPLETED listener from the manager it was attached to.
  // Safe to call when nothing is attached. The plugin destroys the manager on
  // source change, so this also runs when a new manager arrives to avoid
  // holding a reference to a stale one.
  private fun detachAllAdsCompletedListener() {
    val manager = adsManager
    val listener = allAdsCompletedListener
    if (manager != null && listener != null) {
      manager.removeAdEventListener(listener)
    }
    adsManager = null
    allAdsCompletedListener = null
  }

  private fun adPayload(event: Event) = Arguments.createMap().apply {
    val ad = (event.properties[BaseIMAComponent.AD_EVENT] as? AdEvent)?.ad
    putString("adTitle", ad?.title ?: adTitleForEvent(event))
    // IMA reports ad duration in seconds; 0 when unknown.
    putDouble("duration", ad?.duration ?: 0.0)
  }

  private fun adIdForEvent(event: Event): String {
    val ad = (event.properties[BaseIMAComponent.AD_EVENT] as? AdEvent)?.ad
    val value = ad?.adId ?: event.properties[Event.AD_ID]?.toString().orEmpty()
    return value.takeUnless { it == UNKNOWN_AD_ID }.orEmpty()
  }

  private fun adTitleForEvent(event: Event): String {
    val value = event.properties[Event.AD_TITLE]?.toString().orEmpty()
    return value.takeUnless { it == UNKNOWN_AD_TITLE }.orEmpty()
  }

  private fun adErrorPayload(event: Event) = Arguments.createMap().apply {
    val adError = event.properties[Event.ERROR] as? AdError
    val message = adError?.message
      ?: event.properties[Event.ERROR_MESSAGE]?.toString()
      ?: "Ad playback failed"
    // Map the IMA AdError type onto the cross-platform contract: a LOAD failure
    // (tag could not be fetched/parsed) is "load"; a PLAY failure is "playback";
    // anything without a typed AdError stays "unknown" rather than a guess.
    val code = when (adError?.errorType) {
      AdError.AdErrorType.LOAD -> "load"
      AdError.AdErrorType.PLAY -> "playback"
      else -> "unknown"
    }
    val nativeCode = adError?.errorCodeNumber?.toString() ?: "ad_error"
    putString("code", code)
    putString("message", message)
    putString("nativeCode", nativeCode)
  }

  companion object {
    private const val UNKNOWN_AD_BREAK_INDEX = -1
    private const val UNKNOWN_AD_ID = "Unknown Ad ID"
    private const val UNKNOWN_AD_TITLE = "Unknown Ad Title"
    private const val EVENT_AD_STARTED = "topAdStarted"
    private const val EVENT_AD_COMPLETED = "topAdCompleted"
    private const val EVENT_AD_BREAK_STARTED = "topAdBreakStarted"
    private const val EVENT_AD_BREAK_ENDED = "topAdBreakEnded"
    private const val EVENT_ALL_ADS_COMPLETED = "topAllAdsCompleted"
    private const val EVENT_AD_ERROR = "topAdError"
    private const val EVENT_AD_PAUSED = "topAdPaused"
    private const val EVENT_AD_RESUMED = "topAdResumed"
    private const val EVENT_AD_PROGRESS = "topAdProgress"
    private const val EVENT_AD_QUARTILE = "topAdQuartile"
    private const val EVENT_AD_SKIPPED = "topAdSkipped"
    private const val EVENT_AD_INTERACTION = "topAdInteraction"
    private const val EVENT_AD_METADATA = "topAdMetadata"
    private const val EVENT_AD_OVERLAY_STATE_CHANGED = "topAdOverlayStateChanged"
  }
}
