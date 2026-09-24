package com.brightcove.reactnativeplayer

import com.brightcove.reactnativeplayer.core.BrightcovePlayerView
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.BrightcovePlayerViewManagerDelegate
import com.facebook.react.viewmanagers.BrightcovePlayerViewManagerInterface

/**
 * Implements the Codegen-generated manager interface. The TS spec (and so this
 * interface) always declares every feature's props — Codegen cannot split one
 * component's props across modules — but the implementations of feature props
 * are routed to the feature modules this bridge copy contains. Setting a
 * feature prop to a non-default value without its feature installed raises a
 * descriptive error instead of silently doing nothing.
 */
@ReactModule(name = BrightcovePlayerViewManager.NAME)
class BrightcovePlayerViewManager : SimpleViewManager<BrightcovePlayerView>(),
  BrightcovePlayerViewManagerInterface<BrightcovePlayerView> {
  private val delegate: ViewManagerDelegate<BrightcovePlayerView> =
    BrightcovePlayerViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<BrightcovePlayerView> = delegate

  override fun getName(): String = NAME

  public override fun createViewInstance(context: ThemedReactContext): BrightcovePlayerView =
    BrightcovePlayerView(context)

  @ReactProp(name = "accountId")
  override fun setAccountId(view: BrightcovePlayerView, value: String?) {
    view.setAccountId(value)
  }

  @ReactProp(name = "policyKey")
  override fun setPolicyKey(view: BrightcovePlayerView, value: String?) {
    view.setPolicyKey(value)
  }

  @ReactProp(name = "videoId")
  override fun setVideoId(view: BrightcovePlayerView, value: String?) {
    view.setVideoId(value)
  }

  @ReactProp(name = "offlineSourceId")
  override fun setOfflineSourceId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("offlineSourceId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "videoIds")
  override fun setVideoIds(view: BrightcovePlayerView, value: ReadableArray?) {
    // Forward the raw parsed list; the playlists feature validates and types it
    // (same pattern as setSidecarTracks below). Filtering non-String entries
    // here silently turned a malformed queue (`videoIds={[123]}`) into an empty
    // one, which is indistinguishable from "no queue loaded" and surfaces no
    // onError. The feature rejects a bad element loudly instead.
    val ids: List<Any?> = value?.toArrayList() ?: emptyList()
    view.setFeatureProp("videoIds", ids, isDefault = ids.isEmpty())
  }

  @ReactProp(name = "repeatMode")
  override fun setRepeatMode(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("repeatMode", value, isDefault = value.isNullOrEmpty() || value == "off")
  }

  @ReactProp(name = "shuffle", defaultBoolean = false)
  override fun setShuffle(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("shuffle", value, isDefault = !value)
  }

  @ReactProp(name = "videoReferenceId")
  override fun setVideoReferenceId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("videoReferenceId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "playlistId")
  override fun setPlaylistId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("playlistId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "playlistReferenceId")
  override fun setPlaylistReferenceId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("playlistReferenceId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "sourceUrl")
  override fun setSourceUrl(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("sourceUrl", value, isDefault = value.isNullOrEmpty())
  }
  @ReactProp(name = "autoPlay", defaultBoolean = true)
  override fun setAutoPlay(view: BrightcovePlayerView, value: Boolean) {
    view.setAutoPlay(value)
  }

  @ReactProp(name = "videoScalingMode")
  override fun setVideoScalingMode(view: BrightcovePlayerView, value: String?) {
    view.setVideoScalingMode(value)
  }

  @ReactProp(name = "controlsEnabled", defaultBoolean = true)
  override fun setControlsEnabled(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("controlsEnabled", value, isDefault = value)
  }

  @ReactProp(name = "sidecarTracks")
  override fun setSidecarTracks(view: BrightcovePlayerView, value: ReadableArray?) {
    // Pass the raw parsed list through; the sidecarcaptions feature (when the
    // copy includes it) validates and types it. This keeps the manager free of
    // feature imports so subset bridge copies still compile.
    val tracks: List<Any?> =
      value?.toArrayList() ?: emptyList()
    view.setFeatureProp("sidecarTracks", tracks, isDefault = tracks.isEmpty())
  }

  @ReactProp(name = "customCaptionRenderingEnabled", defaultBoolean = false)
  override fun setCustomCaptionRenderingEnabled(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("customCaptionRenderingEnabled", value, isDefault = !value)
  }
  @ReactProp(name = "audioDescriptionEnabled", defaultBoolean = false)
  override fun setAudioDescriptionEnabled(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("audioDescriptionEnabled", value, isDefault = !value)
  }

  @ReactProp(name = "preferredPeakBitrate", defaultDouble = 0.0)
  override fun setPreferredPeakBitrate(view: BrightcovePlayerView, value: Double) {
    view.setFeatureProp("preferredPeakBitrate", value, isDefault = value == 0.0)
  }

  @ReactProp(name = "chapterSeekTime", defaultDouble = -1.0)
  override fun setChapterSeekTime(view: BrightcovePlayerView, value: Double) {
    view.setFeatureProp("chapterSeekTime", value, isDefault = value == -1.0)
  }

  @ReactProp(name = "chapterSeekRequestId", defaultInt = 0)
  override fun setChapterSeekRequestId(view: BrightcovePlayerView, value: Int) {
    view.setFeatureProp("chapterSeekRequestId", value, isDefault = value == 0)
  }

  @ReactProp(name = "playbackRate", defaultDouble = 1.0)
  override fun setPlaybackRate(view: BrightcovePlayerView, value: Double) {
    view.setPlaybackRate(value)
  }

  @ReactProp(name = "volume", defaultDouble = 1.0)
  override fun setVolume(view: BrightcovePlayerView, value: Double) {
    view.setVolume(value)
  }

  @ReactProp(name = "muted", defaultBoolean = false)
  override fun setMuted(view: BrightcovePlayerView, value: Boolean) {
    view.setMuted(value)
  }

  @ReactProp(name = "loop", defaultBoolean = false)
  override fun setLoop(view: BrightcovePlayerView, value: Boolean) {
    view.setLoop(value)
  }

  @ReactProp(name = "captionsEnabled", defaultBoolean = false)
  override fun setCaptionsEnabled(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("captionsEnabled", value, isDefault = !value)
  }

  @ReactProp(name = "captionTrackId")
  override fun setCaptionTrackId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("captionTrackId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "audioTrackId")
  override fun setAudioTrackId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("audioTrackId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "pictureInPictureEnabled", defaultBoolean = false)
  override fun setPictureInPictureEnabled(view: BrightcovePlayerView, value: Boolean) {
    // Value-based default like every other feature prop: a copy without the
    // PiP feature must reject an explicit true loudly (matching iOS) rather
    // than silently ignoring the request.
    view.setFeatureProp(
      "pictureInPictureEnabled",
      value,
      isDefault = !value,
    )
  }

  @ReactProp(name = "castEnabled", defaultBoolean = false)
  override fun setCastEnabled(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("castEnabled", value, isDefault = !value)
  }

  @ReactProp(name = "backgroundPlaybackEnabled", defaultBoolean = false)
  override fun setBackgroundPlaybackEnabled(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("backgroundPlaybackEnabled", value, isDefault = !value)
  }

  @ReactProp(name = "adTagUrl")
  override fun setAdTagUrl(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("adTagUrl", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "adConfigId")
  override fun setAdConfigId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("adConfigId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "airPlayEnabled", defaultBoolean = false)
  override fun setAirPlayEnabled(view: BrightcovePlayerView, value: Boolean) {
    // AirPlay is iOS-only. Keep the generated Android contract complete while
    // making a non-default value fail loudly instead of silently pretending to
    // enable an Android feature.
    view.setFeatureProp("airPlayEnabled", value, isDefault = !value)
  }

  @ReactProp(name = "thumbnailSeekingEnabled", defaultBoolean = false)
  override fun setThumbnailSeekingEnabled(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("thumbnailSeekingEnabled", value, isDefault = !value)
  }

  @ReactProp(name = "vrMode", defaultBoolean = false)
  override fun setVrMode(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("vrMode", value, isDefault = !value)
  }

  @ReactProp(name = "preloadVideoId")
  override fun setPreloadVideoId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("preloadVideoId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "freeWheelAdUrl")
  override fun setFreeWheelAdUrl(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("freeWheelAdUrl", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "freeWheelNetworkId", defaultInt = 0)
  override fun setFreeWheelNetworkId(view: BrightcovePlayerView, value: Int) {
    view.setFeatureProp("freeWheelNetworkId", value, isDefault = value == 0)
  }

  @ReactProp(name = "freeWheelProfile")
  override fun setFreeWheelProfile(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("freeWheelProfile", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "freeWheelSiteSectionId")
  override fun setFreeWheelSiteSectionId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("freeWheelSiteSectionId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "freeWheelVideoAssetId")
  override fun setFreeWheelVideoAssetId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("freeWheelVideoAssetId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "pulseHost")
  override fun setPulseHost(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("pulseHost", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "pulseCategory")
  override fun setPulseCategory(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("pulseCategory", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "pulseTags")
  override fun setPulseTags(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("pulseTags", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "pulseContentMetadataTitle")
  override fun setPulseContentMetadataTitle(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("pulseContentMetadataTitle", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "pulseMidrollPositions")
  override fun setPulseMidrollPositions(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("pulseMidrollPositions", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "heartbeatTrackingServer")
  override fun setHeartbeatTrackingServer(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("heartbeatTrackingServer", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "heartbeatChannel")
  override fun setHeartbeatChannel(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("heartbeatChannel", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "heartbeatAppVersion")
  override fun setHeartbeatAppVersion(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("heartbeatAppVersion", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "heartbeatOvp")
  override fun setHeartbeatOvp(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("heartbeatOvp", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "heartbeatPlayerName")
  override fun setHeartbeatPlayerName(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("heartbeatPlayerName", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "heartbeatSsl", defaultBoolean = true)
  override fun setHeartbeatSsl(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("heartbeatSsl", value, isDefault = value)
  }

  @ReactProp(name = "heartbeatDebugLogging", defaultBoolean = false)
  override fun setHeartbeatDebugLogging(view: BrightcovePlayerView, value: Boolean) {
    view.setFeatureProp("heartbeatDebugLogging", value, isDefault = !value)
  }

  @ReactProp(name = "daiSourceId")
  override fun setDaiSourceId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("daiSourceId", value, isDefault = value.isNullOrEmpty())
  }

  @ReactProp(name = "daiVideoId")
  override fun setDaiVideoId(view: BrightcovePlayerView, value: String?) {
    view.setFeatureProp("daiVideoId", value, isDefault = value.isNullOrEmpty())
  }
  override fun onAfterUpdateTransaction(view: BrightcovePlayerView) {
    super.onAfterUpdateTransaction(view)
    view.commitConfiguration()
  }

  // Imperative commands (see the TS contract's NativeCommands doc comment).
  override fun play(view: BrightcovePlayerView) {
    view.play()
  }

  override fun pause(view: BrightcovePlayerView) {
    view.pause()
  }

  override fun seekTo(view: BrightcovePlayerView, positionSeconds: Double) {
    view.seekTo(positionSeconds)
  }

  override fun reload(view: BrightcovePlayerView) {
    view.reload()
  }

  override fun enterFullscreen(view: BrightcovePlayerView) {
    view.handleCommand("enterFullscreen")
  }

  override fun exitFullscreen(view: BrightcovePlayerView) {
    view.handleCommand("exitFullscreen")
  }

  override fun enterPictureInPicture(view: BrightcovePlayerView) {
    view.handleCommand("enterPictureInPicture")
  }

  override fun seekToLiveEdge(view: BrightcovePlayerView) {
    view.seekToLiveEdge()
  }

  // Imperative commands (see the TS contract's NativeCommands doc comment): a
  // manual queue skip. The native SDK's own queue already auto-advances at
  // the end of an item, so these proxy to the playlists feature only — the
  // bridge adds no separate queue state machine.
  override fun next(view: BrightcovePlayerView) {
    view.nextQueueItem()
  }

  override fun previous(view: BrightcovePlayerView) {
    view.previousQueueItem()
  }
  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> {
    val events = mutableMapOf<String, Any>(
      BrightcovePlayerView.EVENT_READY to mutableMapOf("registrationName" to "onReady"),
      BrightcovePlayerView.EVENT_ERROR to mutableMapOf("registrationName" to "onError"),
      BrightcovePlayerView.EVENT_COMMAND_ERROR to mutableMapOf("registrationName" to "onPlayerCommandError"),
    )
    FeatureRegistry.createFeatures().forEach { feature ->
      feature.exportedEvents.forEach { (native, registration) ->
        events[native] = mutableMapOf("registrationName" to registration)
      }
    }
    return events
  }

  override fun onDropViewInstance(view: BrightcovePlayerView) {
    super.onDropViewInstance(view)
    view.dispose()
  }

  // Never hand a dropped view to React Native's recycling pool: this manager
  // disposes the view's native resources in onDropViewInstance, so a recycled
  // instance would be permanently dead (generation guards reject every
  // request it receives). Until a complete reset-to-fresh lifecycle exists,
  // recycling stays off — matching iOS's shouldBeRecycled=false and paying
  // the allocation instead of resurrecting a disposed player.
  override fun prepareToRecycleView(
    reactContext: ThemedReactContext,
    view: BrightcovePlayerView,
  ): BrightcovePlayerView? = null

  companion object {
    const val NAME = "BrightcovePlayerView"
  }
}
