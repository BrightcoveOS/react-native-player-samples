import type * as React from 'react';
import {
  codegenNativeCommands,
  codegenNativeComponent,
  type HostComponent,
  type ViewProps,
} from 'react-native';
import type {
  Double,
  DirectEventHandler,
  Int32,
  WithDefault,
} from 'react-native/Libraries/Types/CodegenTypes';

/**
 * Repeat modes for queue playback (see `videoIds`): 'off' (default, plays
 * sequentially to the end of the queue), 'one' (repeats the current item
 * indefinitely), 'all' (loops the entire queue continuously).
 */
export type RepeatMode = 'off' | 'one' | 'all';

/**
 * Data sent from the native player to React Native after the requested video
 * has been prepared. Codegen uses this type to generate the corresponding
 * Android and iOS event payload definitions.
 */
export type ReadyEventData = Readonly<{
  videoId: string;
}>;

/** Reports the Brightcove SDK's completed screen-mode state. */
export type FullscreenChangedEventData = Readonly<{
  active: boolean;
}>;

/**
 * Controls how the native player fits the video pixels inside the React Native
 * view. Both modes preserve the source aspect ratio.
 */
export type VideoScalingMode = 'fit' | 'fill';

/**
 * A normalized time-aligned signal from the current stream. `time` is seconds
 * on the player timeline. Only textual ID3 frames and finite catalog cue
 * points cross the native boundary.
 */
export type TimedMetadataEventData = Readonly<{
  time: Double;
  type: string;
  data: {
    key: string;
    value: string;
  };
}>;

/**
 * A normalized, cross-platform error category. Both native implementations map
 * their SDK-specific errors onto exactly one of these values, so `code` is a
 * value a customer can branch on identically on Android and iOS:
 *
 * - `invalid_configuration` — a required prop is missing or malformed (bridge
 *   caught it before reaching the SDK).
 * - `not_found` — the requested video does not exist (a genuine 404 / missing
 *   resource). This is NOT reported for an expired or invalid policy key, a
 *   geo/domain restriction, or a server (5xx) error — those are access or
 *   server failures, not a missing video, and surface as `unknown` so `code`
 *   never claims a video is absent when it is not.
 * - `not_playable` — the video resolved but has no playable source (e.g. no
 *   compatible rendition, or FairPlay content on the simulator).
 * - `network` — a transport-level failure reaching Brightcove or the CDN
 *   (e.g. the device is offline, DNS/TLS failure, or a request timeout).
 * - `drm` — license acquisition or DRM playback failed.
 * - `playback` — the source loaded but playback failed mid-stream.
 * - `unknown` — an SDK error that does not map to any category above,
 *   including access/authorization and server-side failures whose precise
 *   cause the bridge cannot positively determine.
 *
 * The raw, platform-specific SDK code is preserved separately in `nativeCode`
 * for logging and support, and must not be used for control flow.
 */
export type PlayerErrorCode =
  | 'invalid_configuration'
  | 'not_found'
  | 'not_playable'
  | 'network'
  | 'drm'
  | 'playback'
  | 'unknown';

/**
 * Platform-independent error data sent by a native implementation. Native SDK
 * errors are normalized into this shape before they cross the RN boundary.
 * `code` is the normalized, branchable category; `nativeCode` is the raw
 * platform SDK code (e.g. "AVFoundationErrorDomain:-11800" on iOS, a catalog /
 * ExoPlayer code on Android) kept for diagnostics only.
 */
export type PlayerErrorEventData = Readonly<{
  // One of PlayerErrorCode. Typed as string because React Native Codegen does
  // not support string-literal union types in event payloads; treat it as
  // PlayerErrorCode in consuming code (see BrightcovePlayerView.tsx re-export).
  code: string;
  message: string;
  nativeCode: string;
}>;

/**
 * Stable error categories for imperative command rejections or failures.
 * `invalid_configuration` reports a configuration change the player cannot
 * apply once running — on web, a change to the initialization-only ad props
 * (see the web note beside them below), reported with nativeCode
 * `ad_config_init_only`.
 */
export type PlayerCommandErrorCode =
  | 'feature_not_installed'
  | 'invalid_argument'
  | 'invalid_configuration'
  | 'not_ready'
  | 'disabled'
  | 'invalid_state'
  | 'unavailable'
  | 'failed';

/**
 * Emitted when an imperative command cannot be executed by the native player.
 */
export type PlayerCommandErrorEventData = Readonly<{
  command: string;
  code: string;
  message: string;
  nativeCode: string;
}>;

/**
 * Emitted when the native SDK enumerates the current source's playable audio
 * tracks. `id` is opaque and valid only for this source; `label` is the
 * Brightcove display/selection label and must not be used as the id.
 * After Android clear/default or invalid-id requests, `onAudioTrackChanged`
 * reports an empty id until a later native selected-track event confirms a
 * replacement; Media3 re-selection is asynchronous and the bridge does not
 * guess the default synchronously.
 */
export type AudioTracksAvailableEventData = Readonly<{
  tracks: {
    id: string;
    language: string;
    label: string;
  }[];
}>;

/**
 * Sent whenever the active audio track changes — either programmatically via
 * audioTrackId or through the player's native controls. Emitted with empty id
 * and language on source reset; every id emitted for the previous source is
 * invalid after that reset.
 */
export type AudioTrackChangedEventData = Readonly<{
  id: string;
  language: string;
}>;

/**
 * Sent once per video after the native SDK has enumerated the available
 * caption tracks (Android's CAPTIONS_LANGUAGES / iOS's legibleMediaSelectionGroup).
 * An empty list means the video carries no captions. The track object is
 * inlined here because Codegen does not support a named object type as an
 * array element inside an event payload.
 *
 * - id: an opaque, per-source stable token identifying this specific track.
 *   This is the value to select with (captionTrackId) and to branch on — it
 *   distinguishes tracks that share a language (e.g. "English" and
 *   "English SDH" both tagged "en"), which `language` cannot. Do not persist it
 *   across videos or parse it; it is only stable within the current source.
 * - language: a BCP-47 code (e.g. "en", "es", "ja"), metadata only.
 * - label: a human-readable display name (e.g. "English"), localized per
 *   platform for display only.
 *
 * Platform note: on iOS each distinct media option gets its own id, so
 * same-language variants are individually selectable. On Android the SDK's
 * caption selection is language-keyed (it exposes and selects one track per
 * language), so the id is the language code and same-language variants collapse
 * to a single selectable track — selecting one yields the SDK's first track for
 * that language.
 */
export type CaptionsAvailableEventData = Readonly<{
  tracks: {
    id: string;
    language: string;
    label: string;
  }[];
}>;

/**
 * Sent whenever the active caption track changes — either because the customer
 * set captionTrackId, or the user toggled captions via the native controls.
 * id is the stable token of the now-active track (see CaptionsAvailableEventData),
 * empty when captions are off; language mirrors it as metadata.
 */
export type CaptionTrackChangedEventData = Readonly<{
  id: string;
  language: string;
}>;

/**
 * Event data sent when a sidecar subtitle/caption track status updates
 * (configured, selected, reset, or failed). Configured means the track was
 * attached to the current source; it does not claim that the remote WebVTT
 * file has already been downloaded. A same-language in-manifest track is
 * rejected because Android selects captions by language and cannot identify
 * the sidecar track independently. Sidecar failures do not reuse the terminal
 * content onError event.
 */
export type SidecarTrackStatusEventData = Readonly<{
  status: string;
  language: string;
  label: string;
  error: string;
  nativeCode: string;
}>;

/**
 * Event data sent when caption cue text changes during playback under custom
 * caption rendering. When no cue is active, text is empty and times are 0.
 * Native cue callbacks expose the presentation time but not a reliable end
 * time on both platforms, so endTime is 0 when unknown.
 */
export type CaptionCueEventData = Readonly<{
  text: string;
  startTime: Double;
  endTime: Double;
}>;

/**
 * Sent whenever the player enters or leaves Picture-in-Picture. `active` is
 * true while the video plays in the PiP window and false once it returns to the
 * app or PiP is dismissed.
 */
export type PictureInPictureModeChangedEventData = Readonly<{
  active: boolean;
}>;

/**
 * Sent by the iOS Brightcove playback controller when external playback
 * becomes active or inactive. The SDK reports external playback, not a route
 * name or device identity, so this event intentionally contains only `active`.
 */
export type ExternalPlaybackChangedEventData = Readonly<{
  active: boolean;
}>;

/**
 * Sent when the native player reports a new positive presentation size. The
 * dimensions are pixels and describe the decoded video, not the React Native
 * view's layout.
 */
export type VideoSizeChangedEventData = Readonly<{
  width: Double;
  height: Double;
}>;

/**
 * Sent when a single ad starts or finishes playing. `adTitle` and `duration`
 * (seconds) are best-effort — an ad tag may not supply them, in which case they
 * are empty/zero. Maps to Android's AD_STARTED / AD_COMPLETED and iOS's IMA
 * STARTED / COMPLETE ad events.
 *
 * Note for SSAI: server-side ad insertion reports `duration` as 0 on Android —
 * the SSAI plugin's ad event does not carry a per-ad duration (only iOS's
 * BCOVAd exposes one). Treat `duration` as informational for SSAI ads; do not
 * rely on it for timing on Android.
 */
export type AdEventData = Readonly<{
  adTitle: string;
  duration: Double;
}>;

/**
 * Sent when an ad break (pod) begins or ends — the transition into and out of
 * ad playback around the content. Maps to Android's
 * AD_BREAK_STARTED / AD_BREAK_COMPLETED and iOS's IMA AD_BREAK_STARTED /
 * AD_BREAK_ENDED ad events.
 */
export type AdBreakEventData = Readonly<{
  // Index of this ad break within the video (0-based), or -1 when unknown.
  // Neither platform's ad SDK surfaces a stable break index on these events, so
  // this is currently always -1; it is kept in the payload so a future SDK that
  // does report it needs no contract change. Do not branch on it today.
  index: Int32;
}>;

/**
 * Sent once, after the entire ad schedule for the video has finished. Maps to
 * Google IMA's ALL_ADS_COMPLETED on both platforms: iOS reads it from the IMA
 * lifecycle event, Android attaches to the IMA AdsManager to observe it.
 */
export type AllAdsCompletedEventData = Readonly<{
  // Codegen requires a non-empty event payload shape, so a constant true marker
  // is carried rather than an empty object; the event firing is the signal.
  completed: boolean;
}>;

/**
 * Sent when an active ad pauses.
 */
export type AdPausedEventData = Readonly<{
  adId: string;
}>;

/**
 * Sent when a paused ad resumes playback.
 */
export type AdResumedEventData = Readonly<{
  adId: string;
}>;

/**
 * Sent periodically during ad playback with current playhead position and duration.
 */
export type AdProgressEventData = Readonly<{
  adId: string;
  positionSeconds: Double;
  durationSeconds: Double;
}>;

/**
 * Sent when an ad passes a quartile milestone (25, 50, or 75 percent).
 */
export type AdQuartileEventData = Readonly<{
  adId: string;
  quartile: Int32;
}>;

/**
 * Sent when the user skips a skippable ad.
 */
export type AdSkippedEventData = Readonly<{
  adId: string;
}>;

/**
 * Sent on user interaction with an ad (e.g. clicked, tapped).
 * Only interactions supported across both Android and iOS IMA SDKs are surfaced.
 */
export type AdInteractionEventData = Readonly<{
  adId: string;
  interaction: string;
}>;

/**
 * Detailed metadata about an ad received from the VAST/VMAP response.
 */
export type AdMetadataEventData = Readonly<{
  adId: string;
  adTitle: string;
  advertiserName: string;
  durationSeconds: Double;
  isLinear: boolean;
  width: Int32;
  height: Int32;
  isSkippable: boolean;
  skipTimeOffsetSeconds: Double;
}>;

/**
 * Sent when the overlay visibility of a non-linear ad changes.
 */
export type AdOverlayStateChangedEventData = Readonly<{
  adId: string;
  visible: boolean;
}>;

/**
 * Ad-specific error data. Ads failing must not be reported through the content
 * `onError` contract — an ad failure does not mean the video failed to play —
 * so ad errors have their own event. `code` is a normalized, cross-platform
 * category; `nativeCode` is the raw platform ad-SDK code for diagnostics.
 *
 * - `load` — the ad tag / VMAP could not be fetched or parsed.
 * - `playback` — an ad loaded but failed to play.
 * - `unknown` — an ad-SDK error that does not map to the above.
 */
export type AdErrorEventData = Readonly<{
  // One of 'load' | 'playback' | 'unknown'. Typed as string because Codegen
  // does not support string-literal unions in event payloads.
  code: string;
  message: string;
  nativeCode: string;
}>;

/**
 * Describes the latest rendition observation from the native adaptive
 * streaming engine. The native rendition object never crosses the bridge:
 * `renditionId` is an opaque, source-scoped identifier and the remaining
 * fields are serializable playback facts.
 *
 * `bitrate` is the advertised/manifest bitrate for the rendition (HLS
 * BANDWIDTH/AVERAGE-BANDWIDTH on iOS, the container's declared bitrate on
 * Android) — not a live measured throughput.
 *
 * There is deliberately no field distinguishing "adaptive" vs "user-selected"
 * quality: neither Brightcove SDK exposes a reliable public signal for it.
 * Android's automatic HEVC-compatibility override and a genuine manual
 * selection both populate the same track-selector override state, so they
 * cannot be told apart; a field claiming to do so would lie some of the time.
 */
export type RenditionChangedEventData = Readonly<{
  sourceId: string;
  videoId: string;
  renditionId: string;
  bitrate: Double;
  width: Double;
  height: Double;
}>;

/**
 * Playback position update, emitted periodically while the video plays and once
 * on seek. `currentTime` and `duration` are in seconds. For a live stream
 * `duration` is not a fixed length: it reports the current seekable-window
 * duration (0 when the SDK has not yet reported one), so treat a live duration
 * as informational, not as a fixed total. Maps to Android's PROGRESS event
 * (PLAYHEAD_POSITION_LONG / VIDEO_DURATION_LONG, milliseconds) and iOS's
 * didProgressTo: / didChangeDuration: delegate callbacks.
 */
export type PlaybackProgressEventData = Readonly<{
  currentTime: Double;
  duration: Double;
}>;

/**
 * Reports whether the current source exposes a playable audio-description mix.
 * `videoId` is empty for the source-reset event.
 */
export type AudioDescriptionAvailableEventData = Readonly<{
  videoId: string;
  available: boolean;
}>;

/**
 * Reports the actual audible selection after native controls or a prop request
 * changes it. `enabled` is the selected track state, not merely the requested
 * prop value.
 */
export type AudioDescriptionChangedEventData = Readonly<{
  videoId: string;
  enabled: boolean;
  available: boolean;
}>;

/**
 * Sent once the SDK has determined whether the loaded video is on-demand, live,
 * or live with DVR. `isLive` is true for both live and live-DVR; `hasDvr` is
 * true only when the live stream supports DVR scrubbing (a seekable window
 * behind the live edge). Maps to iOS's determinedVideoType:forVideo:
 * (BCOVVideoTypeLive / BCOVVideoTypeLiveDVR) and Android's
 * videoDisplay.isLive() / hasDvr() read once the source is ready.
 */
export type LiveStatusEventData = Readonly<{
  isLive: boolean;
  hasDvr: boolean;
}>;

/**
 * Moving seekable window updates for live-DVR content. `ranges` contains the
 * valid seekable intervals in seconds on the player timeline (start and end).
 * `liveEdge` is the current usable live edge in seconds. On Android, this
 * reflects the SDK's calculated target live edge (clamped to the seekable window
 * end if clock drift causes a slight excess); on iOS, this reflects the
 * seekable window end.
 */
export type SeekableRangesChangedEventData = Readonly<{
  ranges: {
    startTime: Double;
    endTime: Double;
  }[];
  liveEdge: Double;
}>;

/**
 * Reports completion of a caller-owned chapter navigation request. The native
 * bridge does not discover or title chapters; it only seeks to the supplied
 * media-timeline time through the Brightcove playback API.
 */
export type ChapterSeekCompletedEventData = Readonly<{
  requestId: Int32;
  positionSeconds: Double;
  completed: boolean;
}>;

/**
 * Sent when the current queue item changes: once for the first item after
 * `videoIds` loads, and again on every transition — whether the native SDK
 * auto-advanced at the end of an item or the app called the `next`/`previous`
 * command. `index` is the item's position in `videoIds`.
 */
export type QueueItemChangedEventData = Readonly<{
  videoId: string;
  index: Int32;
}>;

/**
 * Sent when an item in `videoIds` fails to resolve from the Brightcove
 * catalog (e.g. a bad or deleted video ID). The item is skipped — it never
 * reaches the native playback queue — and playback continues with the next
 * resolvable item. `code`/`message`/`nativeCode` use the same normalized
 * error contract as `onError`.
 *
 * This event covers catalog-resolution failures only. A failure once an item
 * has already started playing is reported through the existing `onError` and
 * is terminal for the queue, matching single-video behavior; auto-skipping a
 * mid-playback failure is not yet supported.
 */
export type QueueItemFailedEventData = Readonly<{
  videoId: string;
  index: Int32;
  code: string;
  message: string;
  nativeCode: string;
}>;

/**
 * Normalized Google Cast connection state sent to JS whenever the Cast SDK
 * discovers, connects to, or disconnects from a receiver.
 *
 * `state` is one of:
 * - `no_devices` — no Cast receivers found on the local network (normal on emulators/simulators).
 * - `not_connected` — at least one receiver found; tap the Cast button to connect.
 * - `connecting` — connection to the chosen receiver is in progress.
 * - `connected` — actively connected and casting to a receiver.
 * - `unknown` — CastContext is not initialized or the SDK reported an unrecognized state.
 */
export type CastState =
  | 'no_devices'
  | 'not_connected'
  | 'connecting'
  | 'connected'
  | 'unknown';

export type CastStateChangedEventData = Readonly<{
  state: string;
}>;

/**
 * Reports whether the current source is a 360 (equirectangular) video, and
 * the caller-facing projection format string. Fired once per source
 * (including once on source reset, reporting "normal"/false) and again
 * whenever the SDK's own projection detection changes.
 */
export type ProjectionFormatChangedEventData = Readonly<{
  projectionFormat: string;
  is360: boolean;
}>;

/**
 * Reports 360 VR (goggles) mode transitions: whether vrMode is currently
 * active, the SDK's projection style ("normal" | "vrGoggles"), and which
 * input drove the transition ("deviceMotion" | "fingerTracking" | "none" |
 * "unknown" — "unknown" only when the SDK has not reported a navigation
 * method yet). Fired for both a caller-requested vrMode prop change and a
 * change the SDK's own player-view UI made directly (e.g. a native
 * VR-goggles button).
 */
export type Video360ModeChangedEventData = Readonly<{
  vrMode: boolean;
  projectionStyle: string;
  navigationMethod: string;
}>;

/**
 * The video named by preloadVideoId finished resolving and was added to the
 * native queue behind the currently playing video. Fired once per successful
 * preload request; a new preloadVideoId value or an explicit cancellation
 * (empty string) supersedes it without a corresponding event.
 */
export type PreloadQueuedEventData = Readonly<{
  videoId: string;
}>;

/**
 * The current video ended and playback handed off to the preloaded video
 * queued by onPreloadQueued. previousVideoId is the video that just finished;
 * currentVideoId is the preloaded video now playing.
 */
export type PreloadHandoffEventData = Readonly<{
  previousVideoId: string;
  currentVideoId: string;
}>;

/**
 * The video named by preloadVideoId failed to resolve or queue. This does not
 * fail the currently playing video — it only means the requested preload
 * never became available, so a handoff at end-of-video will not occur for it.
 */
export type PreloadErrorEventData = Readonly<{
  videoId: string;
  code: string;
  nativeCode: string;
  message: string;
}>;

/**
 * The public contract between React Native and the native player view.
 * Extending ViewProps also gives the component standard RN properties such as
 * style, accessibility settings, and testID.
 */
export interface NativeProps extends ViewProps {
  // These identifiers tell the native SDK which account and published video to
  // retrieve. accountId and policyKey are always required. videoId is
  // required UNLESS videoIds is set (non-empty), offlineSourceId names a
  // completed persisted download in a bridge copy that includes offline, or
  // videoReferenceId/playlistId/playlistReferenceId/sourceUrl names a
  // sourceloadingmodes alternate source below — set exactly one video source,
  // never more than one.
  accountId: string;
  policyKey: string;
  videoId?: WithDefault<string, ''>;

  // Loads a Video Cloud queue instead of a single video: each ID is resolved
  // from the catalog in order and handed to the native SDK's own queue, which
  // owns normal end-of-item advancement. Mutually exclusive with videoId and
  // offlineSourceId — set exactly one. Omitted or empty means "not a queue"; a
  // single-element array is a 1-item queue. Feature-owned: setting it to a
  // non-empty value without the playlists feature installed raises the
  // bridge's descriptive missing-feature error. Not WithDefault: Codegen's
  // WithDefault only accepts a string/number/boolean/null default literal,
  // not [] — the generated prop is empty when omitted regardless.
  videoIds?: string[];

  // Repeat mode for queue playback (videoIds). Feature-owned by playlists:
  // setting it to a non-default value without the playlists feature installed
  // raises the bridge's descriptive missing-feature error.
  repeatMode?: WithDefault<'off' | 'one' | 'all', 'off'>;

  // Shuffle mode for queue playback (videoIds): when true, plays queue items
  // in a randomized order without duplicates. Feature-owned by playlists.
  shuffle?: WithDefault<boolean, false>;

  // Opaque localId returned by OfflinePlayback.requestDownload. It is mutually
  // exclusive with videoId: an offline source is resolved from native durable
  // storage and never re-fetches the Video Cloud catalog, so it keeps playing
  // while the device has no network connection. Changing this prop rebuilds the
  // native playback controller so its FairPlay provider chain matches the new
  // online/offline mode before the source is loaded.
  offlineSourceId?: WithDefault<string, ''>;

  // A Video Cloud video's customer-assigned reference ID, resolved through the
  // same online catalog as videoId. Feature-owned by sourceloadingmodes and
  // mutually exclusive with videoId, playlistId, playlistReferenceId, and
  // sourceUrl: exactly one of the five may be set.
  videoReferenceId?: WithDefault<string, ''>;

  // A Video Cloud playlist's numeric ID. Every video in the resolved playlist
  // is added to the native queue at once (SDK-owned end-of-item advancement);
  // the ready event reports the playlist's first video. Feature-owned by
  // sourceloadingmodes and mutually exclusive with videoId, videoReferenceId,
  // playlistReferenceId, and sourceUrl.
  playlistId?: WithDefault<string, ''>;

  // A Video Cloud playlist's customer-assigned reference ID. Same queue
  // semantics as playlistId. Feature-owned by sourceloadingmodes and mutually
  // exclusive with videoId, videoReferenceId, playlistId, and sourceUrl.
  playlistReferenceId?: WithDefault<string, ''>;

  // A direct HTTPS HLS (.m3u8) or MP4 (.mp4) stream URL, played without any
  // Video Cloud catalog authentication (accountId/policyKey are ignored for
  // this mode). Feature-owned by sourceloadingmodes and mutually exclusive
  // with videoId, videoReferenceId, playlistId, and playlistReferenceId.
  sourceUrl?: WithDefault<string, ''>;

  // Initialization-only hint: whether playback starts automatically once the
  // video is ready. It is applied when the source becomes ready, not as a live
  // play/pause control — toggling it after load does not start or stop an
  // already-loaded video (drive playback with your own controls for that).
  // Defaults to true because this is a playback demo; a real app that must
  // respect data usage or platform autoplay policies should pass false.
  autoPlay?: WithDefault<boolean, true>;

  // `fit` shows the complete video with preserved aspect ratio. `fill` preserves
  // the aspect ratio while cropping overflow so the view is completely filled.
  videoScalingMode?: WithDefault<VideoScalingMode, 'fit'>;

  // Enables or disables native playback controls. When false, native controls
  // are hidden, allowing custom React Native controls to drive playback.
  controlsEnabled?: WithDefault<boolean, true>;

  // Externally-hosted caption tracks to attach to the current source, in
  // addition to any the manifest already carries. Each url must be HTTPS and
  // each language a BCP-47 tag; label defaults to language when omitted.
  // Languages must be unique within the array and not collide with an
  // in-manifest track of the same language. Feature-owned by sidecarcaptions:
  // setting it to a non-empty value without the sidecarcaptions feature
  // installed raises the bridge's descriptive missing-feature error.
  // Not WithDefault: Codegen's WithDefault only accepts a
  // string/number/boolean/null default literal, not [] — the generated prop is
  // empty when omitted regardless.
  sidecarTracks?: { url: string; language: string; label?: WithDefault<string, ''> }[];

  // Enables custom caption rendering mode, extracting cue text to JS instead of
  // using the native closed caption rendering surface.
  customCaptionRenderingEnabled?: WithDefault<boolean, false>;
  // Requests selection of a playable audio-description mix positively marked by
  // the native media metadata. Setting false restores the audible selection that
  // was active before this feature's request; it does not mute the player. The
  // changed event reports the actual selected state after native confirmation.
  audioDescriptionEnabled?: WithDefault<boolean, false>;

  // Requests an adaptive peak-bitrate preference in bits per second. Zero
  // restores automatic selection; fractional values are rounded to a whole bit
  // per second. The actual rendition remains native-engine controlled and is
  // reported through onRenditionChanged.
  preferredPeakBitrate?: WithDefault<Double, 0>;

  // Caller-owned chapter navigation request. -1 means no request. Request IDs
  // must be positive and unique for the current source; change the ID for
  // repeated seeks to the same time. A source reset abandons pending requests.
  // Chapter titles and ranges stay in JavaScript rather than being inferred from
  // native metadata.
  chapterSeekTime?: WithDefault<Double, -1>;
  chapterSeekRequestId?: WithDefault<Int32, 0>;

  // The playback speed: 1.0 is normal speed, 2.0 is twice as fast, 0.5 is half
  // speed. Like volume/muted (not autoPlay), this is a live control: it can be
  // changed at any time, including during playback, and is not tied to any one
  // source. Values <= 0, NaN, non-finite values (+/-Infinity), or values that
  // cannot be safely represented as positive finite 32-bit floats are rejected:
  // the previously-applied rate remains in effect (identically on both
  // platforms), logged as a warning without changing the current rate. Audio
  // pitch is preserved (time-stretched, not resampled) by both native SDKs.
  playbackRate?: WithDefault<Double, 1.0>;

  // The player's volume, 0.0 (silent) to 1.0 (full). Unlike autoPlay, this is a
  // live control: it can be changed at any time, including during playback.
  // Out-of-range finite values are clamped. NaN is rejected and logged without
  // changing the current volume. Independent of `muted` — setting volume while
  // muted is recorded but has no audible effect until unmuted.
  volume?: WithDefault<Double, 1.0>;

  // Mutes the player without discarding the volume level: unmuting restores
  // whatever volume was last set (default 1.0 if none was). Also a live
  // control.
  muted?: WithDefault<boolean, false>;

  // Turn captions on or off. When true and captionTrackId is unset, the native
  // SDK enables its default (first available) caption track.
  captionsEnabled?: WithDefault<boolean, false>;

  // The id of the caption track to show — an opaque token from a track reported
  // by onCaptionsAvailable (not a language code). Empty string means "no
  // specific track": with captionsEnabled the default/first track is used. If
  // an id is set that the current video does not carry, captions stay off
  // rather than silently switching to a different track; set an available id to
  // turn them on. captionsEnabled and captionTrackId are read together as one
  // selection per commit, so setting both in the same render applies atomically.
  captionTrackId?: WithDefault<string, ''>;

  // Selects an audio track by its opaque, source-scoped track identifier.
  // Empty string leaves or restores the native SDK's default/automatic audio selection.
  //
  // Platform ID semantics:
  // - Android: IDs are generation/index identifiers (e.g. "3:1"). The native
  //   Brightcove selection key is private; use the id from the current
  //   onAudioTracksAvailable event and never persist it across sources.
  // - iOS: IDs are source-generation-scoped identifiers (e.g. "0:1") valid only
  //   for the source that reported them; stale source-scoped IDs will not be
  //   reinterpreted on a new source, falling back to the new source's default.
  audioTrackId?: WithDefault<string, ''>;

  // Enables Picture-in-Picture while the player is actually playing. The
  // feature owns the platform-specific readiness and lifecycle rules.
  pictureInPictureEnabled?: WithDefault<boolean, false>;

  // iOS-only: enables Brightcove's external-playback support and route
  // detection. The Android public bridge surface omits this feature.
  airPlayEnabled?: WithDefault<boolean, false>;

  // Repeats the current single video after it reaches the end. This is a
  // playback setting, not playlist repeat-all behavior.
  loop?: WithDefault<boolean, false>;

  // Enables Google Cast (Chromecast) for this player. When true, the native
  // SDK displays a Cast button over the player and hands playback off to any
  // selected receiver on the local network. Changes are applied to the active
  // player when possible.
  castEnabled?: WithDefault<boolean, false>;

  // Enables background audio playback and native lock-screen / notification
  // controls while the hosting app is backgrounded. Android requires
  // FOREGROUND_SERVICE, FOREGROUND_SERVICE_MEDIA_PLAYBACK, and
  // POST_NOTIFICATIONS in the manifest, plus a runtime notification grant on
  // Android 13+. iOS requires UIBackgroundModes containing audio and an audio
  // session configured with the playback category.
  backgroundPlaybackEnabled?: WithDefault<boolean, false>;
  // A VMAP ("ad rules") ad-tag URL. When set, the native IMA plugin requests
  // the ad schedule from this URL — the VMAP response defines the full
  // pre/mid/post schedule, so no client-side ad positioning is needed. Empty
  // string means no ads. (VAST tags, which require the app to define ad
  // positions via cue points, are intentionally not supported by this prop.)
  //
  // Read at each source load, not as a live control: the value in effect when a
  // video is loaded determines that video's ad schedule (iOS stamps it on the
  // video; Android supplies it when IMA requests ads). Changing it after a
  // video is already playing does not re-request ads for the current video;
  // set it before/with the source. Like autoPlay, treat it as load-time.
  adTagUrl?: WithDefault<string, ''>;

  // A VideoCloud ad-config id for server-side ad insertion (SSAI). When set,
  // the source is requested with this ad-config and played as one stitched
  // stream. It is mutually exclusive with adTagUrl.
  adConfigId?: WithDefault<string, ''>;

  // Web note: adTagUrl, adConfigId, daiSourceId, and daiVideoId select which
  // ad integrations the web SDK builds at player creation; unlike native,
  // where each source rebuilds the playback pipeline, a web player cannot be
  // reconfigured after creation. Changing these on web after mount reports
  // an invalid_configuration/ad_config_init_only command error instead of
  // silently ignoring the new values — remount or reload to apply them.

  // Enables the native SDK's thumbnail-aware scrub bar for the current
  // source. Must be set before the source loads (an online-only feature);
  // toggling it after the current video is already loaded is a bridge error,
  // not a silent no-op. Feature-owned: setting it without the
  // thumbnail-seeking feature installed raises the bridge's descriptive
  // missing-feature error.
  thumbnailSeekingEnabled?: WithDefault<boolean, false>;

  // Requests VR (goggles) projection for a 360/equirectangular source.
  // Ignored (reported back as false via onVideo360ModeChanged) for a
  // non-360 source — vrMode does not itself make an ordinary video
  // spherical. Feature-owned by video360.
  vrMode?: WithDefault<boolean, false>;

  // The Video Cloud video ID to preload in the background while the current
  // video plays, so it starts instantly once the current video ends. Empty
  // string cancels any pending preload. Feature-owned by preloading; requires
  // accountId/policyKey (an online catalog lookup, independent of the current
  // source's own videoId/videoReferenceId/etc.). Setting the same value the
  // current source already reports as ready is a no-op — this is for the
  // *next* video, not the one already playing.
  preloadVideoId?: WithDefault<string, ''>;

  // FreeWheel ad server URL. Empty string means FreeWheel is not configured.
  freeWheelAdUrl?: WithDefault<string, ''>;
  // FreeWheel network ID (e.g. 90750 or 42015). 0 means unset.
  freeWheelNetworkId?: WithDefault<Int32, 0>;
  // FreeWheel player profile (e.g. "3pqa_android" or "42015:ios_allinone_profile").
  freeWheelProfile?: WithDefault<string, ''>;
  // FreeWheel site section ID (e.g. "3pqa_section_nocbp" or "ios_allinone_demo_site_section").
  freeWheelSiteSectionId?: WithDefault<string, ''>;
  // FreeWheel video asset ID. When empty, defaults to the current video ID.
  freeWheelVideoAssetId?: WithDefault<string, ''>;

  // Pulse ad server host URL (e.g. "https://bc-test.videoplaza.tv"). Empty string means Pulse is not configured.
  pulseHost?: WithDefault<string, ''>;
  // Pulse content metadata category (e.g. "skip-always").
  pulseCategory?: WithDefault<string, ''>;
  // Comma-separated Pulse content metadata tags (e.g. "standard-linears").
  pulseTags?: WithDefault<string, ''>;
  // Pulse content metadata title / identifier (e.g. "demo"). When empty, defaults to the video ID.
  pulseContentMetadataTitle?: WithDefault<string, ''>;
  // Comma-separated content positions in seconds for Pulse mid-rolls. Empty
  // means that Pulse's request policy chooses the insertion points.
  pulseMidrollPositions?: WithDefault<string, ''>;

  // Adobe Video Heartbeat tracking server (e.g. "ovppartners.hb.omtrdc.net"). Empty string means Heartbeat is not configured.
  heartbeatTrackingServer?: WithDefault<string, ''>;
  // Adobe Video Heartbeat channel (e.g. "test-channel").
  heartbeatChannel?: WithDefault<string, ''>;
  // Adobe Video Heartbeat app version (e.g. "1.0.0").
  heartbeatAppVersion?: WithDefault<string, ''>;
  // Adobe Video Heartbeat Online Video Platform name (e.g. "Brightcove").
  heartbeatOvp?: WithDefault<string, ''>;
  // Adobe Video Heartbeat player name (e.g. "BasicOmniturePlayer").
  heartbeatPlayerName?: WithDefault<string, ''>;
  // Whether to use SSL for Adobe Video Heartbeat tracking. Defaults to true:
  // telemetry (session ids, viewer identifiers, playback positions) must not
  // cross the network in plaintext.
  heartbeatSsl?: WithDefault<boolean, true>;
  // Whether to enable debug logging for Adobe Video Heartbeat. Defaults to false.
  heartbeatDebugLogging?: WithDefault<boolean, false>;

  // Google DAI VOD source id (stream request key).
  daiSourceId?: WithDefault<string, ''>;
  // Google DAI VOD video id.
  daiVideoId?: WithDefault<string, ''>;
  // Direct events travel from this native view to its matching JSX callbacks;
  // unlike bubbling events, they do not propagate through parent components.
  onReady?: DirectEventHandler<ReadyEventData>;
  onError?: DirectEventHandler<PlayerErrorEventData>;
  onPlayerCommandError?: DirectEventHandler<PlayerCommandErrorEventData>;

  // Fired once the SDK knows which caption tracks the video carries, and again
  // whenever the active track changes.
  onCaptionsAvailable?: DirectEventHandler<CaptionsAvailableEventData>;
  onCaptionTrackChanged?: DirectEventHandler<CaptionTrackChangedEventData>;
  onSidecarTrackStatus?: DirectEventHandler<SidecarTrackStatusEventData>;
  onCaptionCueChanged?: DirectEventHandler<CaptionCueEventData>;
  onAudioTracksAvailable?: DirectEventHandler<AudioTracksAvailableEventData>;
  onAudioTrackChanged?: DirectEventHandler<AudioTrackChangedEventData>;
  onPictureInPictureModeChanged?: DirectEventHandler<PictureInPictureModeChangedEventData>;
  onFullscreenChanged?: DirectEventHandler<FullscreenChangedEventData>;
  // iOS-only: reports the SDK's externalPlaybackActive session callback.
  onExternalPlaybackChanged?: DirectEventHandler<ExternalPlaybackChangedEventData>;
  onVideoSizeChanged?: DirectEventHandler<VideoSizeChangedEventData>;
  onRenditionChanged?: DirectEventHandler<RenditionChangedEventData>;

  // Ad lifecycle. onAdBreakStarted/Ended bracket a pod; onAdStarted/onAdCompleted
  // fire per individual ad; onAdError reports an ad failure without failing
  // content playback.
  onAdStarted?: DirectEventHandler<AdEventData>;
  onAdCompleted?: DirectEventHandler<AdEventData>;
  onAdBreakStarted?: DirectEventHandler<AdBreakEventData>;
  onAdBreakEnded?: DirectEventHandler<AdBreakEventData>;
  // Fires once after the entire ad schedule has completed, on both platforms.
  // iOS reads Google IMA's ALL_ADS_COMPLETED lifecycle event; Android attaches
  // directly to the IMA AdsManager to observe the same event (the Brightcove
  // plugin does not re-broadcast it, so the feature listens for it itself).
  onAllAdsCompleted?: DirectEventHandler<AllAdsCompletedEventData>;
  onAdError?: DirectEventHandler<AdErrorEventData>;

  // Detailed ad lifecycle and control events (Google IMA CSAI only).
  // Note: Companion ads are not exposed because client-side Google IMA does not
  // provide a reliable cross-platform companion callback.
  onAdPaused?: DirectEventHandler<AdPausedEventData>;
  onAdResumed?: DirectEventHandler<AdResumedEventData>;
  onAdProgress?: DirectEventHandler<AdProgressEventData>;
  onAdQuartile?: DirectEventHandler<AdQuartileEventData>;
  onAdSkipped?: DirectEventHandler<AdSkippedEventData>;
  onAdInteraction?: DirectEventHandler<AdInteractionEventData>;
  onAdMetadata?: DirectEventHandler<AdMetadataEventData>;
  onAdOverlayStateChanged?: DirectEventHandler<AdOverlayStateChangedEventData>;

  // Playback lifecycle events surfaced to JS by the playback-events feature.
  // onPlay/onPause fire when playback starts/pauses; onEnded fires once when the
  // video plays to completion; onProgress fires periodically with the current
  // position and duration. These report playback state — they do not configure
  // Brightcove's analytics beacons, which the SDK sends automatically.
  onPlay?: DirectEventHandler<null>;
  onPause?: DirectEventHandler<null>;
  onEnded?: DirectEventHandler<null>;
  onProgress?: DirectEventHandler<PlaybackProgressEventData>;

  // Fired once after the SDK determines the video type (live or on-demand);
  // `isLive` tells you which, so JS can adapt its UI without guessing from the source.
  onLiveStatus?: DirectEventHandler<LiveStatusEventData>;
  onSeekableRangesChanged?: DirectEventHandler<SeekableRangesChangedEventData>;

  // Fired for normal playback stalls after playback has started. Initial
  // preparation and seek-induced buffering are excluded on both platforms.
  onRebufferStart?: DirectEventHandler<null>;
  onRebufferEnd?: DirectEventHandler<null>;
  onAudioDescriptionAvailable?: DirectEventHandler<AudioDescriptionAvailableEventData>;
  onAudioDescriptionChanged?: DirectEventHandler<AudioDescriptionChangedEventData>;
  onChapterSeekCompleted?: DirectEventHandler<ChapterSeekCompletedEventData>;
  onTimedMetadata?: DirectEventHandler<TimedMetadataEventData>;

  // Fired for a videoIds queue: item changes (including the first), a skipped
  // catalog-resolution failure, and once when the queue completes (repeatMode
  // "off" only — "one"/"all" loop forever and never complete). Not fired for a
  // single-video (videoId/offlineSourceId) source. Completion is a natural
  // event only — the last item's own end-of-playback — fired exactly once per
  // loaded queue; a manual `next` command at the last item emits
  // onPlayerCommandError (invalid_state/queue_at_end) instead.
  onQueueItemChanged?: DirectEventHandler<QueueItemChangedEventData>;
  onQueueItemFailed?: DirectEventHandler<QueueItemFailedEventData>;
  onQueueCompleted?: DirectEventHandler<null>;

  // Fired whenever the Google Cast connection state changes (device discovered,
  // connecting, connected, disconnected).
  onCastStateChanged?: DirectEventHandler<CastStateChangedEventData>;

  // Fired once per source (video360) reporting whether it is 360/equirectangular,
  // and again whenever VR (goggles) mode is entered or exited.
  onProjectionFormatChanged?: DirectEventHandler<ProjectionFormatChangedEventData>;
  onVideo360ModeChanged?: DirectEventHandler<Video360ModeChangedEventData>;

  // Background preload lifecycle for preloadVideoId (feature-owned by
  // preloading). onPreloadHandoff fires once the current video ends and
  // playback switches to the preloaded video; onPreloadError reports a
  // preload that never became available without affecting the currently
  // playing video.
  onPreloadQueued?: DirectEventHandler<PreloadQueuedEventData>;
  onPreloadHandoff?: DirectEventHandler<PreloadHandoffEventData>;
  onPreloadError?: DirectEventHandler<PreloadErrorEventData>;
}

/**
 * Marks this interface as a Fabric native-component specification. During a
 * native build, React Native Codegen reads NativeProps and generates the
 * Android/iOS props, event emitters, component descriptors, and manager
 * interfaces. The component name must match the native manager registration.
 */
export default codegenNativeComponent<NativeProps>(
  'BrightcovePlayerView',
) as HostComponent<NativeProps>;
/**
 * Imperative player controls, dispatched through a ref to the native view
 * rather than as props. Playback actions (play, pause, seekTo, reload),
 * presentation transitions (fullscreen, Picture-in-Picture), live stream seeking
 * (seekToLiveEdge), and queue management (next, previous) are one-shot actions
 * with no meaningful "current value" a prop could hold. The native player
 * remains the source of truth for playback state, while command rejections or
 * failures are reported through onPlayerCommandError.
 *
 * seekTo's positionSeconds is a Double. Seconds match the public playback event
 * units and avoid exposing platform-specific millisecond conversions.
 *
 * Queue commands: `next` advances when a next item exists or repeatMode is
 * "all" (wrapping); at the last item when the repeat mode does not wrap
 * ("off", or "one" looping only the current item) it emits
 * invalid_state/queue_at_end, and with no queue loaded it emits
 * invalid_state/queue_not_loaded. `previous` moves back when a previous item
 * exists, wraps under repeatMode "all", and restarts the current item at the
 * first position — "at first" is a valid position, so it never fails while a
 * queue is loaded.
 */
export interface NativeCommands {
  play: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  pause: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  seekTo: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    positionSeconds: Double,
  ) => void;
  reload: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  enterFullscreen: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
  ) => void;
  exitFullscreen: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
  ) => void;
  enterPictureInPicture: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
  ) => void;
  seekToLiveEdge: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
  ) => void;
  next: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  previous: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
}

export const Commands: NativeCommands = codegenNativeCommands<NativeCommands>({
  supportedCommands: [
    'play',
    'pause',
    'seekTo',
    'reload',
    'enterFullscreen',
    'exitFullscreen',
    'enterPictureInPicture',
    'seekToLiveEdge',
    'next',
    'previous',
  ],
});
