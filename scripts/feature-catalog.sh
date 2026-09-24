# Shared feature catalog for the bridge tooling. Sourced by
# assemble-bridge.sh (which generates each sample's composition-root files) and
# check-bridge-copies.sh (which verifies a sample's public prop surface matches
# the features it installs). Keeping the mapping in one place means adding a
# feature is a single edit here, not the same edit duplicated across scripts
# that must agree.
#
# Each function maps a feature directory name to a facet of that feature. The
# props here must match the feature's ownedProps in its native class and the
# props declared in the Codegen spec — those live in different languages and
# cannot share this list, but this is the single source of truth for the shell
# tooling.

# All feature directory names that exist in the reference.
ALL_FEATURES="ads airplay audiodescription audiotracks background buffering captionrendering captions cast chapternavigation controls dai drm freewheel fullscreen lifecycle live offline omniture pip playbackevents playlists preloading pulse quality sidecarcaptions sourceloadingmodes ssai thumbnail timedmetadata video360"
ALL_WEB_FEATURES="captions pip drm fullscreen ads ssai lifecycle playbackevents live playlists buffering audiodescription quality chapternavigation controls sidecarcaptions captionrendering dai audiotracks timedmetadata thumbnail preloading"

# Samples whose native integrations require licensed artifacts unavailable in CI.
# Both CI discovery and the bridge hygiene check consume this list.
ALLOWED_NATIVE_BUILD_OPTOUTS=""

# Returns 0 if two features are mutually exclusive (cannot both be installed in
# the same bridge copy), 1 otherwise.
feature_conflicts() {
  case "$1:$2" in
    ads:ssai|ssai:ads) return 0 ;;
    ads:dai|dai:ads) return 0 ;;
    ssai:dai|dai:ssai) return 0 ;;
    freewheel:ads|ads:freewheel) return 0 ;;
    freewheel:ssai|ssai:freewheel) return 0 ;;
    freewheel:dai|dai:freewheel) return 0 ;;
    pulse:ads|ads:pulse) return 0 ;;
    pulse:ssai|ssai:pulse) return 0 ;;
    pulse:dai|dai:pulse) return 0 ;;
    pulse:freewheel|freewheel:pulse) return 0 ;;
    # Both offline and sourceloadingmodes call claimsSourceLoading(); the core
    # crashes (IllegalStateException / NSInternalInconsistencyException) if
    # two installed features claim the source simultaneously. They are
    # mutually exclusive bridge copies, not just mutually exclusive props.
    offline:sourceloadingmodes|sourceloadingmodes:offline) return 0 ;;
    *) return 1 ;;
  esac
}

# TS prop names the feature owns (props + event handlers). An event-only feature
# (playbackevents, live) owns no input props — only its event handlers.
feature_props() {
  case "$1" in
    ads) echo "adTagUrl onAdStarted onAdCompleted onAdBreakStarted onAdBreakEnded onAllAdsCompleted onAdError onAdPaused onAdResumed onAdProgress onAdQuartile onAdSkipped onAdInteraction onAdMetadata onAdOverlayStateChanged" ;;
    airplay) echo "airPlayEnabled onExternalPlaybackChanged" ;;
    audiodescription) echo "audioDescriptionEnabled onAudioDescriptionAvailable onAudioDescriptionChanged" ;;
    audiotracks) echo "audioTrackId onAudioTracksAvailable onAudioTrackChanged" ;;
    background) echo "backgroundPlaybackEnabled" ;;
    buffering) echo "onRebufferStart onRebufferEnd" ;;
    captionrendering) echo "customCaptionRenderingEnabled onCaptionCueChanged" ;;
    captions) echo "captionsEnabled captionTrackId onCaptionsAvailable onCaptionTrackChanged" ;;
    cast) echo "castEnabled onCastStateChanged" ;;
    chapternavigation) echo "chapterSeekTime chapterSeekRequestId onChapterSeekCompleted" ;;
    controls) echo "controlsEnabled" ;;
    dai) echo "daiSourceId daiVideoId onAdStarted onAdCompleted onAdBreakStarted onAdBreakEnded onAdError" ;;
    drm) echo "" ;;
    freewheel) echo "freeWheelAdUrl freeWheelNetworkId freeWheelProfile freeWheelSiteSectionId freeWheelVideoAssetId onAdStarted onAdCompleted onAdBreakStarted onAdBreakEnded onAdError" ;;
    fullscreen) echo "onFullscreenChanged" ;;
    lifecycle) echo "onVideoSizeChanged" ;;
    live) echo "onLiveStatus onSeekableRangesChanged" ;;
    offline) echo "offlineSourceId" ;;
    omniture) echo "heartbeatTrackingServer heartbeatChannel heartbeatAppVersion heartbeatOvp heartbeatPlayerName heartbeatSsl heartbeatDebugLogging" ;;
    pip) echo "pictureInPictureEnabled onPictureInPictureModeChanged" ;;
    playbackevents) echo "onPlay onPause onEnded onProgress" ;;
    playlists) echo "videoIds repeatMode shuffle onQueueItemChanged onQueueItemFailed onQueueCompleted" ;;
    preloading) echo "preloadVideoId onPreloadQueued onPreloadHandoff onPreloadError" ;;
    pulse) echo "pulseHost pulseCategory pulseTags pulseContentMetadataTitle pulseMidrollPositions onAdBreakStarted onAdBreakEnded" ;;
    quality) echo "preferredPeakBitrate onRenditionChanged" ;;
    sidecarcaptions) echo "sidecarTracks onSidecarTrackStatus" ;;
    sourceloadingmodes) echo "videoReferenceId playlistId playlistReferenceId sourceUrl" ;;
    ssai) echo "adConfigId onAdStarted onAdCompleted onAdBreakStarted onAdBreakEnded onAdError" ;;
    thumbnail) echo "thumbnailSeekingEnabled" ;;
    timedmetadata) echo "onTimedMetadata" ;;
    video360) echo "vrMode onProjectionFormatChanged onVideo360ModeChanged" ;;
    *) echo "" ;;
  esac
}

# All web props across current and future features for web wrapper generation.
web_feature_props() {
  case "$1" in
    captions) echo "captionsEnabled captionTrackId onCaptionsAvailable onCaptionTrackChanged" ;;
    pip) echo "pictureInPictureEnabled onPictureInPictureModeChanged" ;;
    fullscreen) echo "onFullscreenChanged" ;;
    ads) echo "adTagUrl onAdStarted onAdCompleted onAdBreakStarted onAdBreakEnded onAllAdsCompleted onAdError onAdPaused onAdResumed onAdProgress onAdQuartile onAdSkipped onAdInteraction onAdMetadata onAdOverlayStateChanged" ;;
    ssai) echo "adConfigId onAdStarted onAdCompleted onAdBreakStarted onAdBreakEnded onAdError" ;;
    lifecycle) echo "onSourceLoading onFirstFrame onSeekStarted onSeekCompleted onDurationChanged onVideoSizeChanged" ;;
    playbackevents) echo "onPlay onPause onEnded onProgress" ;;
    live) echo "onLiveStatus onSeekableRangesChanged" ;;
    playlists) echo "videoIds repeatMode onQueueItemChanged onQueueItemFailed onQueueCompleted" ;;
    buffering) echo "onRebufferStart onRebufferEnd" ;;
    audiodescription) echo "audioDescriptionEnabled onAudioDescriptionAvailable onAudioDescriptionChanged" ;;
    quality) echo "preferredPeakBitrate onRenditionChanged" ;;
    chapternavigation) echo "chapterSeekTime chapterSeekRequestId onChapterSeekCompleted" ;;
    controls) echo "controlsEnabled" ;;
    sidecarcaptions) echo "sidecarTracks onSidecarTrackStatus" ;;
    captionrendering) echo "customCaptionRenderingEnabled onCaptionCueChanged" ;;
    dai) echo "daiSourceId daiVideoId" ;;
    audiotracks) echo "audioTrackId onAudioTracksAvailable onAudioTrackChanged" ;;
    timedmetadata) echo "onTimedMetadata" ;;
    thumbnail) echo "thumbnailSeekingEnabled" ;;
    preloading) echo "preloadVideoId onPreloadQueued onPreloadHandoff onPreloadError" ;;
    *) echo "" ;;
  esac
}

# Imperative command names the feature contributes to NativeCommands. The
# core bridge (always present) owns play/pause/seekTo/reload; each feature
# entry lists only the commands its feature's supportedCommands declares.
feature_commands() {
  case "$1" in
    fullscreen) echo "enterFullscreen exitFullscreen" ;;
    live) echo "seekToLiveEdge" ;;
    pip) echo "enterPictureInPicture" ;;
    playlists) echo "next previous" ;;
    *) echo "" ;;
  esac
}

# Event payload type names the feature contributes to the public exports.
feature_event_types() {
  case "$1" in
    ads) echo "AdEventData AdBreakEventData AllAdsCompletedEventData AdErrorEventData AdPausedEventData AdResumedEventData AdProgressEventData AdQuartileEventData AdSkippedEventData AdInteractionEventData AdMetadataEventData AdOverlayStateChangedEventData" ;;
    airplay) echo "ExternalPlaybackChangedEventData" ;;
    audiodescription) echo "AudioDescriptionAvailableEventData AudioDescriptionChangedEventData" ;;
    audiotracks) echo "AudioTracksAvailableEventData AudioTrackChangedEventData" ;;
    background) echo "" ;;
    buffering) echo "" ;;
    captionrendering) echo "CaptionCueEventData" ;;
    captions) echo "CaptionsAvailableEventData CaptionTrackChangedEventData" ;;
    cast) echo "CastStateChangedEventData" ;;
    chapternavigation) echo "ChapterSeekCompletedEventData" ;;
    controls) echo "" ;;
    dai) echo "AdEventData AdBreakEventData AdErrorEventData" ;;
    drm) echo "" ;;
    freewheel) echo "AdEventData AdBreakEventData AdErrorEventData" ;;
    fullscreen) echo "FullscreenChangedEventData" ;;
    lifecycle) echo "VideoSizeChangedEventData" ;;
    live) echo "LiveStatusEventData SeekableRangesChangedEventData" ;;
    offline) echo "" ;;
    omniture) echo "" ;;
    pip) echo "PictureInPictureModeChangedEventData" ;;
    playbackevents) echo "PlaybackProgressEventData" ;;
    playlists) echo "RepeatMode QueueItemChangedEventData QueueItemFailedEventData" ;;
    preloading) echo "PreloadQueuedEventData PreloadHandoffEventData PreloadErrorEventData" ;;
    pulse) echo "AdBreakEventData" ;;
    quality) echo "RenditionChangedEventData" ;;
    sidecarcaptions) echo "SidecarTrackStatusEventData" ;;
    sourceloadingmodes) echo "" ;;
    ssai) echo "AdEventData AdBreakEventData AdErrorEventData" ;;
    thumbnail) echo "" ;;
    timedmetadata) echo "TimedMetadataEventData" ;;
    video360) echo "ProjectionFormatChangedEventData Video360ModeChangedEventData" ;;
    *) echo "" ;;
  esac
}

# Web event payload type names each feature contributes to index.web.tsx exports.
web_feature_event_types() {
  case "$1" in
    ads) echo "AdEventData AdBreakEventData AllAdsCompletedEventData AdErrorEventData AdPausedEventData AdResumedEventData AdProgressEventData AdQuartileEventData AdSkippedEventData AdInteractionEventData AdMetadataEventData AdOverlayStateChangedEventData" ;;
    audiodescription) echo "AudioDescriptionAvailableEventData AudioDescriptionChangedEventData" ;;
    audiotracks) echo "AudioTracksAvailableEventData AudioTrackChangedEventData" ;;
    buffering) echo "" ;;
    captions) echo "CaptionsAvailableEventData CaptionTrackChangedEventData" ;;
    chapternavigation) echo "ChapterSeekCompletedEventData" ;;
    drm) echo "" ;;
    fullscreen) echo "FullscreenChangedEventData" ;;
    lifecycle) echo "SourceLoadingEventData FirstFrameEventData SeekStartedEventData SeekCompletedEventData DurationChangedEventData VideoSizeChangedEventData" ;;
    live) echo "LiveStatusEventData SeekableRangesChangedEventData" ;;
    pip) echo "PictureInPictureModeChangedEventData" ;;
    playbackevents) echo "PlaybackProgressEventData" ;;
    playlists) echo "RepeatMode QueueItemChangedEventData QueueItemFailedEventData" ;;
    quality) echo "RenditionChangedEventData" ;;
    ssai) echo "AdEventData AdBreakEventData AdErrorEventData" ;;
    sidecarcaptions) echo "SidecarTrackStatusEventData" ;;
    captionrendering) echo "CaptionCueEventData" ;;
    timedmetadata) echo "TimedMetadataEventData" ;;
    preloading) echo "PreloadQueuedEventData PreloadHandoffEventData PreloadErrorEventData" ;;
    *) echo "" ;;
  esac
}

# Fully-qualified Kotlin feature class.
feature_kotlin_class() {
  case "$1" in
    ads) echo "com.brightcove.reactnativeplayer.ads.AdsFeature" ;;
    airplay) echo "" ;;
    audiodescription) echo "com.brightcove.reactnativeplayer.audiodescription.AudioDescriptionFeature" ;;
    audiotracks) echo "com.brightcove.reactnativeplayer.audiotracks.AudioTracksFeature" ;;
    background) echo "com.brightcove.reactnativeplayer.background.BackgroundPlaybackFeature" ;;
    buffering) echo "com.brightcove.reactnativeplayer.buffering.BufferingFeature" ;;
    captionrendering) echo "com.brightcove.reactnativeplayer.captionrendering.CaptionRenderingFeature" ;;
    captions) echo "com.brightcove.reactnativeplayer.captions.CaptionsFeature" ;;
    cast) echo "com.brightcove.reactnativeplayer.cast.CastFeature" ;;
    chapternavigation) echo "com.brightcove.reactnativeplayer.chapternavigation.ChapterNavigationFeature" ;;
    controls) echo "com.brightcove.reactnativeplayer.controls.ControlsFeature" ;;
    dai) echo "com.brightcove.reactnativeplayer.dai.DaiFeature" ;;
    drm) echo "com.brightcove.reactnativeplayer.drm.DrmFeature" ;;
    freewheel) echo "com.brightcove.reactnativeplayer.freewheel.FreeWheelFeature" ;;
    fullscreen) echo "com.brightcove.reactnativeplayer.fullscreen.FullscreenFeature" ;;
    lifecycle) echo "com.brightcove.reactnativeplayer.lifecycle.PlaybackLifecycleFeature" ;;
    live) echo "com.brightcove.reactnativeplayer.live.LiveFeature" ;;
    offline) echo "com.brightcove.reactnativeplayer.offline.BrightcoveOfflinePlaybackFeature" ;;
    omniture) echo "com.brightcove.reactnativeplayer.omniture.OmnitureFeature" ;;
    pip) echo "com.brightcove.reactnativeplayer.pip.PictureInPictureFeature" ;;
    playbackevents) echo "com.brightcove.reactnativeplayer.playbackevents.PlaybackEventsFeature" ;;
    playlists) echo "com.brightcove.reactnativeplayer.playlists.PlaylistsFeature" ;;
    preloading) echo "com.brightcove.reactnativeplayer.preloading.PreloadingFeature" ;;
    pulse) echo "com.brightcove.reactnativeplayer.pulse.PulseFeature" ;;
    quality) echo "com.brightcove.reactnativeplayer.quality.QualityFeature" ;;
    sidecarcaptions) echo "com.brightcove.reactnativeplayer.sidecarcaptions.SidecarCaptionsFeature" ;;
    sourceloadingmodes) echo "com.brightcove.reactnativeplayer.sourceloadingmodes.SourceLoadingModesFeature" ;;
    ssai) echo "com.brightcove.reactnativeplayer.ssai.SsaiFeature" ;;
    thumbnail) echo "com.brightcove.reactnativeplayer.thumbnail.ThumbnailSeekingFeature" ;;
    timedmetadata) echo "com.brightcove.reactnativeplayer.timedmetadata.TimedMetadataFeature" ;;
    video360) echo "com.brightcove.reactnativeplayer.video360.Video360Feature" ;;
  esac
}

# "Header.h:ClassName" for the iOS feature.
feature_objc() {
  case "$1" in
    ads) echo "ads/BrightcoveAdsFeature.h:BrightcoveAdsFeature" ;;
    airplay) echo "airplay/BrightcoveAirPlayFeature.h:BrightcoveAirPlayFeature" ;;
    audiodescription) echo "audiodescription/BrightcoveAudioDescriptionFeature.h:BrightcoveAudioDescriptionFeature" ;;
    audiotracks) echo "audiotracks/BrightcoveAudioTracksFeature.h:BrightcoveAudioTracksFeature" ;;
    background) echo "background/BrightcoveBackgroundPlaybackFeature.h:BrightcoveBackgroundPlaybackFeature" ;;
    buffering) echo "buffering/BrightcoveBufferingFeature.h:BrightcoveBufferingFeature" ;;
    captionrendering) echo "captionrendering/BrightcoveCaptionRenderingFeature.h:BrightcoveCaptionRenderingFeature" ;;
    captions) echo "captions/BrightcoveCaptionsFeature.h:BrightcoveCaptionsFeature" ;;
    cast) echo "cast/BrightcoveCastFeature.h:BrightcoveCastFeature" ;;
    chapternavigation) echo "chapternavigation/BrightcoveChapterNavigationFeature.h:BrightcoveChapterNavigationFeature" ;;
    controls) echo "controls/BrightcoveControlsFeature.h:BrightcoveControlsFeature" ;;
    dai) echo "dai/BrightcoveDaiFeature.h:BrightcoveDaiFeature" ;;
    drm) echo "drm/BrightcoveDrmFeature.h:BrightcoveDrmFeature" ;;
    freewheel) echo "freewheel/BrightcoveFreeWheelFeature.h:BrightcoveFreeWheelFeature" ;;
    fullscreen) echo "fullscreen/BrightcoveFullscreenFeature.h:BrightcoveFullscreenFeature" ;;
    lifecycle) echo "lifecycle/BrightcovePlaybackLifecycleFeature.h:BrightcovePlaybackLifecycleFeature" ;;
    live) echo "live/BrightcoveLiveFeature.h:BrightcoveLiveFeature" ;;
    offline) echo "offline/BrightcoveOfflinePlaybackFeature.h:BrightcoveOfflinePlaybackFeature" ;;
    omniture) echo "omniture/BrightcoveOmnitureFeature.h:BrightcoveOmnitureFeature" ;;
    pip) echo "pip/BrightcovePictureInPictureFeature.h:BrightcovePictureInPictureFeature" ;;
    playbackevents) echo "playbackevents/BrightcovePlaybackEventsFeature.h:BrightcovePlaybackEventsFeature" ;;
    playlists) echo "playlists/BrightcovePlaylistsFeature.h:BrightcovePlaylistsFeature" ;;
    preloading) echo "preloading/BrightcovePreloadingFeature.h:BrightcovePreloadingFeature" ;;
    pulse) echo "pulse/BrightcovePulseFeature.h:BrightcovePulseFeature" ;;
    quality) echo "quality/BrightcoveQualityFeature.h:BrightcoveQualityFeature" ;;
    sidecarcaptions) echo "sidecarcaptions/BrightcoveSidecarCaptionsFeature.h:BrightcoveSidecarCaptionsFeature" ;;
    sourceloadingmodes) echo "sourceloadingmodes/BrightcoveSourceLoadingModesFeature.h:BrightcoveSourceLoadingModesFeature" ;;
    ssai) echo "ssai/BrightcoveSsaiFeature.h:BrightcoveSsaiFeature" ;;
    thumbnail) echo "thumbnail/BrightcoveThumbnailSeekingFeature.h:BrightcoveThumbnailSeekingFeature" ;;
    timedmetadata) echo "timedmetadata/BrightcoveTimedMetadataFeature.h:BrightcoveTimedMetadataFeature" ;;
    video360) echo "video360/BrightcoveVideo360Feature.h:BrightcoveVideo360Feature" ;;
  esac
}

# Fully-qualified Android NativeModule class a feature contributes. Most player
# features return nothing; offline is app-scoped rather than view-scoped, so its
# durable download manager is registered as a TurboModule only when selected.
feature_kotlin_module() {
  case "$1" in
    offline) echo "com.brightcove.reactnativeplayer.offline.BrightcoveOfflinePlaybackModule" ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Per-feature native dependencies.
#
# Most features need nothing beyond the core Brightcove SDK, but some pull in
# an extra native SDK — ads needs the Brightcove IMA plugin
# (which brings Google IMA transitively), and offline needs the offline-playback
# plugin on Android. Those extra dependencies must appear in a sample's
# build.gradle / podspec ONLY when that feature is installed, or a core-only
# sample would ship extra SDKs it never uses. assemble-bridge.sh generates the
# dependency sections of each sample's build.gradle and podspec from core +
# these per-feature declarations; check-bridge-copies.sh treats those two files
# as generated composition roots and validates them against the installed
# feature set rather than byte-comparing them.

# Android Gradle dependency coordinates (space-separated group:artifact entries,
# without version — the version is the shared brightcoveSdkVersion). Empty for
# features that need no extra dependency.
feature_gradle_deps() {
  case "$1" in
    ads) echo "com.brightcove.player:android-ima-plugin" ;;
    background) echo "com.brightcove.player:android-playback-notification-plugin" ;;
    cast) echo "com.brightcove.player:android-cast-plugin" ;;
    dai) echo "com.brightcove.player:android-dai-plugin" ;;
    freewheel) echo "com.brightcove.player:android-freewheel-plugin" ;;
    offline) echo "com.brightcove.player:offline-playback" ;;
    omniture) echo "com.brightcove.player:android-omniture-plugin" ;;
    pulse) echo "com.brightcove.player:android-pulse-plugin" ;;
    ssai) echo "com.brightcove.player:android-ssai-plugin com.brightcove.player:android-thumbnail-plugin" ;;
    thumbnail) echo "com.brightcove.player:android-thumbnail-plugin" ;;
    *) echo "" ;;
  esac
}

# Props a feature declares cross-platform but whose iOS SDK cannot back, so the
# iOS public entry point must omit them rather than advertise an event or input
# that can never work. ssai: the iOS BrightcoveSSAI SDK exposes no recoverable
# per-ad error signal (only the fatal kBCOVSSAILifecycleErrorEvent), so onAdError
# is Android-only. Keep this in sync with the native feature's own comments.
feature_ios_unsupported_props() {
  case "$1" in
    ssai) echo "onAdError" ;;
    *) echo "" ;;
  esac
}

# Additional Android dependency lines for vendor SDKs whose versions are not
# tied to Brightcove's native SDK version.
feature_gradle_extra() {
  case "$1" in
    freewheel) echo '  compileOnly files("${System.getProperty('\''user.home'\'')}/libs/AdManager.aar")' ;;
    pulse) echo '  implementation "com.ooyala:pulse:2.5.20.3.0"' ;;
    *) echo "" ;;
  esac
}

# iOS SwiftPM product names from brightcove-player-sdk-ios that this feature
# needs, beyond the core BrightcovePlayerSDK. Empty for features that need none.
feature_spm_products() {
  case "$1" in
    ads) echo "BrightcoveIMA" ;;
    cast) echo "BrightcoveGoogleCast" ;;
    dai) echo "BrightcoveDAI" ;;
    freewheel) echo "BrightcoveFW" ;;
    omniture) echo "BrightcoveAMC" ;;
    pulse) echo "BrightcovePulse" ;;
    ssai) echo "BrightcoveSSAI" ;;
    *) echo "" ;;
  esac
}
feature_test_dir() {
  case "$1" in
    live) echo "android/src/test/java/com/brightcove/reactnativeplayer/live" ;;
    quality) echo "android/src/test/java/com/brightcove/reactnativeplayer/quality" ;;
    pip) echo "android/src/test/java/com/brightcove/reactnativeplayer/pip" ;;
    audiodescription) echo "android/src/test/java/com/brightcove/reactnativeplayer/audiodescription" ;;
    audiotracks) echo "android/src/test/java/com/brightcove/reactnativeplayer/audiotracks" ;;
    buffering) echo "android/src/test/java/com/brightcove/reactnativeplayer/buffering" ;;
    chapternavigation) echo "android/src/test/java/com/brightcove/reactnativeplayer/chapternavigation" ;;
    lifecycle) echo "android/src/test/java/com/brightcove/reactnativeplayer/lifecycle" ;;
    playlists) echo "android/src/test/java/com/brightcove/reactnativeplayer/playlists" ;;
    *) echo "" ;;
  esac
}

# AirPlay is intentionally iOS-only. The catalog owns that platform fact so
# the assembler and guard cannot accidentally grow an Android AirPlay copy.
feature_supports_android() {
  [ "$1" != "airplay" ]
}

feature_supports_ios() {
  return 0
}

# Web support level for each feature: supported | partial | unsupported.
#
# Whether a feature reaches the browser at all is decided by ALL_WEB_FEATURES above — that list is
# what assemble-bridge.sh consumes — so this derives from it rather than repeating it; a separate
# hand-maintained table can silently disagree with the list the generator actually uses.
#
# NOTE: this and feature_web_notes below are documentation-facing reference data; nothing in the
# generator or the guards reads them, so a mistake here fails no check. Keep them derived from
# ALL_WEB_FEATURES rather than adding another source of truth.
feature_web_support() {
  case " $ALL_WEB_FEATURES " in
    *" $1 "*) ;;
    *) echo "unsupported"; return ;;
  esac
  # Of the web-capable features, only the core playback facets are complete; the rest expose a
  # usable subset of their native behaviour through the Web SDK.
  case "$1" in
    controls|playbackevents|lifecycle) echo "supported" ;;
    *) echo "partial" ;;
  esac
}

# Web notes describing available Web SDK capabilities or explicit browser/SDK constraints
feature_web_notes() {
  case "$1" in
    basic-playback) echo "Supported via @brightcove/web-sdk Player (play/pause/seekTo, volume/mute via video element, playbackRate, poster)." ;;
    captions) echo "Partial: in-manifest text tracks, captionsEnabled and track selection via getAudioTracks/getTextTracks." ;;
    pip) echo "Partial: HTML5 video Picture-in-Picture API supported via browser enterPictureInPicture / document.exitPictureInPicture." ;;
    cast) echo "Unsupported: Google Cast sender framework is native SDK only." ;;
    fullscreen) echo "Partial: HTML5 Fullscreen API via container/video requestFullscreen." ;;
    ads) echo "Partial: client-side Google IMA supported via Web SDK imaClientSideIntegration." ;;
    drm) echo "Partial: Web SDK EME source handling supports browser-compatible encrypted media and normalizes DRM errors." ;;
    ssai) echo "Partial: Brightcove SSAI supported via Web SDK ssaiIntegration." ;;
    buffering) echo "Partial: waiting and playing events mapped to onRebufferStart/onRebufferEnd." ;;
    audiodescription) echo "Partial: descriptive audio track selection via Web SDK audio track kinds descriptions/main-desc." ;;
    quality) echo "Partial: manual and adaptive quality selection via Web SDK getQualityLevels / selectQualityLevel." ;;
    chapternavigation) echo "Partial: caller-owned chapter times use the HTML video seek API with request-scoped completion events." ;;
    captionrendering) echo "Partial: cue-level caption data is surfaced through onCaptionCueChanged so the app can render captions itself." ;;
    audiotracks) echo "Partial: audio track selection via Web SDK getAudioTracks / selectAudioTrack." ;;
    live) echo "Partial: live status and seekable ranges via duration / seekable." ;;
    offline) echo "Unsupported: offline persistent download manager is native-only." ;;
    # No feature-specific note. Web-capable features without one land here too, so derive the
    # fallback from the support level instead of asserting "unsupported" for everything.
    *)
      case "$(feature_web_support "$1")" in
        unsupported) echo "Unsupported on web platform." ;;
        *) echo "Available on web through the Web SDK." ;;
      esac
      ;;
  esac
}

feature_web_control_bar_components() {
  case "$1" in
    pip) echo "PictureInPictureToggle" ;;
    fullscreen) echo "FullscreenToggle" ;;
    captions|sidecarcaptions|captionrendering) echo "SubsCapsButton" ;;
    audiotracks) echo "AudioTrackButton" ;;
    chapternavigation) echo "ChaptersButton" ;;
    audiodescription) echo "DescriptionsButton" ;;
    live) echo "LiveDisplay SeekToLive RemainingTimeDisplay" ;;
    *) echo "" ;;
  esac
}

feature_web_integrations() {
  case "$1" in
    ads) echo "imaClientSide" ;;
    dai) echo "imaDai" ;;
    ssai) echo "ssai" ;;
    thumbnail) echo "thumbnails" ;;
    *) echo "" ;;
  esac
}

feature_web_integration_import() {
  case "$1" in
    imaClientSide) echo "@brightcove/web-sdk/integrations/imaClientSide" ;;
    imaDai) echo "@brightcove/web-sdk/integrations/imaDai" ;;
    ssai) echo "@brightcove/web-sdk/integrations/ssai" ;;
    thumbnails) echo "@brightcove/web-sdk/integrations/thumbnails" ;;
    *) echo "" ;;
  esac
}

feature_web_integration_style_import() {
  case "$1" in
    imaClientSide) echo "@brightcove/web-sdk/integrations/imaClientSide/styles" ;;
    imaDai) echo "@brightcove/web-sdk/integrations/imaDai/styles" ;;
    ssai) echo "@brightcove/web-sdk/integrations/ssai/styles" ;;
    thumbnails) echo "@brightcove/web-sdk/integrations/thumbnails/styles" ;;
    *) echo "" ;;
  esac
}

feature_web_integration_factory() {
  case "$1" in
    imaClientSide) echo "ImaClientSideIntegrationFactory" ;;
    imaDai) echo "ImaDaiIntegrationFactory" ;;
    ssai) echo "SsaiIntegrationFactory" ;;
    thumbnails) echo "ThumbnailsIntegrationFactory" ;;
    *) echo "" ;;
  esac
}
