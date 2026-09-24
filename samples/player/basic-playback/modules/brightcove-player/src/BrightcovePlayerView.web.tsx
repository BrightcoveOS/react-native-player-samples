import React, {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
} from 'react';
import { StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native';
import { IntegrationsManager, Player } from '@brightcove/web-sdk/ui';
import '@brightcove/web-sdk/ui/styles';

import {
  classifyImaClientSideAdError,
  classifyWebAdError,
  classifyWebPlayerError,
  isAdClassWebPlayerError,
  isPlaybackRateValid,
  normalizeVolume,
  validateSeekPosition,
  type AdBreakEventData,
  type AdErrorEventData,
  type AdEventData,
  type AdMetadataEventData,
  type AdOverlayStateChangedEventData,
  type AdPausedEventData,
  type AdProgressEventData,
  type AdQuartileEventData,
  type AdResumedEventData,
  type AdSkippedEventData,
  type AdInteractionEventData,
  type AllAdsCompletedEventData,
  type AudioDescriptionAvailableEventData,
  type AudioDescriptionChangedEventData,
  type AudioTrackChangedEventData,
  type AudioTracksAvailableEventData,
  type CaptionCueEventData,
  type CaptionsAvailableEventData,
  type CaptionTrackChangedEventData,
  type ChapterSeekCompletedEventData,
  type DurationChangedEventData,
  type FirstFrameEventData,
  type FullscreenChangedEventData,
  type LiveStatusEventData,
  type PictureInPictureModeChangedEventData,
  type PlaybackProgressEventData,
  type PlayerCommandErrorCode,
  type PlayerCommandErrorEventData,
  type PlayerErrorEventData,
  type PreloadErrorEventData,
  type PreloadHandoffEventData,
  type PreloadQueuedEventData,
  type QueueItemChangedEventData,
  type QueueItemFailedEventData,
  type ReadyEventData,
  type RenditionChangedEventData,
  type RepeatMode,
  type SeekableRangesChangedEventData,
  type SeekCompletedEventData,
  type SeekStartedEventData,
  type SidecarTrackStatusEventData,
  type SourceLoadingEventData,
  type TimedMetadataEventData,
  type VideoScalingMode,
  type VideoSizeChangedEventData,
} from './webErrorClassification';

const PLAYER_CAN_PLAY_EVENT = Player.Event.PlayerCanPlay;
const PLAYER_ERROR_EVENT = Player.Event.PlayerError;
const PLAYER_AUDIO_TRACKS_CHANGED_EVENT = Player.Event.PlayerAudioTracksChanged;
const PLAYER_TEXT_TRACKS_CHANGED_EVENT = Player.Event.PlayerTextTracksChanged;

type PromiseLikeValue = {
  then: (
    onFulfilled: () => void,
    onRejected?: (reason: unknown) => void,
  ) => unknown;
};

function isPromiseLike(value: unknown): value is PromiseLikeValue {
  return (
    typeof value === 'object' &&
    value !== null &&
    'then' in value &&
    typeof (value as { then?: unknown }).then === 'function'
  );
}

// Safari's prefixed fullscreen surface (still required on iPadOS and older
// Safari): the prefixed element getter and event mirror the standard ones.
interface DocumentWithWebkitFullscreen extends Document {
  webkitFullscreenElement?: Element | null;
  webkitExitFullscreen?: () => Promise<void> | void;
}

// Safari's prefixed PiP surface on the video element: the mode setter and
// the state-change events mirror the standard requestPictureInPicture API.
interface VideoElementWithWebkitPresentationMode extends HTMLVideoElement {
  webkitSupportsPresentationMode?: (mode: string) => boolean;
  webkitSetPresentationMode?: (mode: string) => Promise<void> | void;
  presentationMode?: string;
}

export interface WebSdkPlayerOptions {
  accountId: string;
  enableThumbnails?: boolean;
  enableAds?: boolean;
  enableSsai?: boolean;
  enableDai?: boolean;
  integrationFactories?: WebSdkIntegrationFactories;
}

export interface WebSdkIntegrationFactories {
  thumbnails?: unknown;
  imaClientSide?: unknown;
  ssai?: unknown;
  imaDai?: unknown;
}

let thumbnailsIntegrationRegistered = false;

function ensureThumbnailsIntegration(factory: unknown): void {
  if (thumbnailsIntegrationRegistered) return;
  if (!factory) {
    throw new Error('Thumbnails integration factory is not configured');
  }
  IntegrationsManager.registerThumbnailsIntegrationFactory(
    factory as Parameters<
      typeof IntegrationsManager.registerThumbnailsIntegrationFactory
    >[0],
  );
  thumbnailsIntegrationRegistered = true;
}

function ensureImaClientSideIntegration(factory: unknown): void {
  if (!factory) {
    throw new Error('IMA client-side integration factory is not configured');
  }
  IntegrationsManager.registerImaClientSideIntegrationFactory(
    factory as Parameters<
      typeof IntegrationsManager.registerImaClientSideIntegrationFactory
    >[0],
  );
}

function ensureSsaiIntegration(factory: unknown): void {
  if (!factory) {
    throw new Error('SSAI integration factory is not configured');
  }
  IntegrationsManager.registerSsaiIntegrationFactory(
    factory as Parameters<
      typeof IntegrationsManager.registerSsaiIntegrationFactory
    >[0],
  );
}

function ensureImaDaiIntegration(factory: unknown): void {
  if (!factory) {
    throw new Error('IMA DAI integration factory is not configured');
  }
  IntegrationsManager.registerImaDaiIntegrationFactory(
    factory as Parameters<
      typeof IntegrationsManager.registerImaDaiIntegrationFactory
    >[0],
  );
}

// Mirrors @brightcove/web-sdk's QualityLevel (videojs-contrib-quality-levels
// under the hood). enabled is a restriction flag the adaptive selector reads
// before choosing a rendition, not "this is the one currently playing" —
// currently-playing rendition is derived separately, from the video
// element's actual videoWidth/videoHeight on the tech's own 'resize' event.
export interface WebSdkQualityLevel {
  id: string;
  label: string;
  bitrate: number;
  width?: number;
  height?: number;
  frameRate?: number;
  enabled: boolean;
}

// Mirrors @brightcove/web-sdk's AudioTrack (the standard HTMLMediaElement/
// videojs AudioTrackList model). Unlike QualityLevel, enabled here IS the
// selection itself — the SDK's selectAudioTrack sets enabled=true on the
// chosen track and false on every other, so at most one track in the list
// is enabled at a time (matching a real <audio>/<video> AudioTrackList,
// where only one track plays at once).
export interface WebSdkAudioTrack {
  id: string;
  kind: string;
  language: string;
  label: string;
  enabled: boolean;
}

// Mirrors the browser's standard TextTrack (what videojs's textTracks()
// returns directly — the Web SDK adds no wrapper type of its own here,
// unlike AudioTrack/QualityLevel). mode is the real DOM selection
// mechanism: 'showing' renders the track's cues, 'hidden' loads the track
// without rendering, 'disabled' does not load it at all. Selecting a
// caption track sets its mode to 'showing' and every other text track's
// mode to 'disabled' (mirroring AudioTrack.enabled's "at most one active"
// semantics), except tracks whose kind is not captions/subtitles (e.g.
// metadata, chapters, thumbnails), which are left untouched.
export interface WebSdkTextTrack {
  id: string;
  kind: string;
  language: string;
  label: string;
  mode: string;
}

export interface WebSdkTextTrackOptions {
  id: string;
  kind: string;
  language: string;
  label: string;
  src?: string;
}

interface WebSdkCaptionCue {
  startTime: number;
  endTime: number;
  text: string;
}

interface WebSdkAd {
  getAdId(): string;
  getTitle(): string;
  getDuration(): number;
  isLinear(): boolean;
  getAdvertiserName(): string;
  getWidth(): number;
  getHeight(): number;
  getSkipTimeOffset(): number;
}

interface WebSdkImaClientSideIntegration {
  getCurrentAd(): WebSdkAd | null;
  requestAd(adTagUrl: string): void;
}

interface WebSdkSsaiAd {
  adTitle(): string;
  duration(): number;
  absoluteStartTime(): number;
  absoluteEndTime(): number;
}

interface WebSdkSsaiAdRoll {
  indexOf(ad: WebSdkSsaiAd): number;
}

interface WebSdkSsaiTimelineState {
  linearAdRoll: WebSdkSsaiAdRoll | null;
  linearAd: WebSdkSsaiAd | null;
}

interface WebSdkSsaiIntegration {
  getRelativeTimelineState(): WebSdkSsaiTimelineState | null;
}

interface WebSdkSource {
  mimeType: string;
  url: string;
  keySystems?: Record<string, unknown>;
}

interface WebSdkImaDaiIntegration {
  load(options: {
    streamRequest: Record<string, unknown>;
    fallbackSource: WebSdkSource;
  }): void;
  getIsImaDaiStream(): boolean;
}

interface WebSdkDaiRuntimeApi {
  VodStreamRequest: new () => Record<string, unknown>;
}

export interface WebSdkUiComponent {
  show?(): void;
  hide?(): void;
  getChild?(name: string): WebSdkUiComponent | null | undefined;
}

export interface WebSdkUiManager {
  getPlayerContainerUiComponent?(): WebSdkUiComponent | null | undefined;
}

export interface WebSdkPlayerInstance {
  updateConfiguration(chunk: Record<string, unknown>): unknown;
  attach(root: HTMLDivElement): void;
  detach(): void;
  dispose(): void;
  getVideoElement(): HTMLVideoElement | null;
  getVideoByIdFromPlaybackApi(payload: { videoId: string }): {
    abort: () => void;
    promise: Promise<unknown>;
  };
  loadBrightcoveVideoModel(model: unknown): void;
  play(): void | Promise<void>;
  pause(): void;
  seek(seconds: number): void;
  setVolumeLevel(level: number): void;
  mute(): void;
  unmute(): void;
  setPlaybackRate(rate: number): void;
  getQualityLevels(): WebSdkQualityLevel[];
  getAudioTracks(): WebSdkAudioTrack[];
  selectAudioTrack(track: WebSdkAudioTrack): void;
  getTextTracks(): WebSdkTextTrack[];
  addTextTrack?(options: WebSdkTextTrackOptions): WebSdkTextTrack | null;
  removeTextTrack?(track: WebSdkTextTrack): void;
  getId3MetadataTrack?(): WebSdkTextTrack | null;
  getMediaCuePointsTrack?(): WebSdkTextTrack | null;
  getCurrentSource?(): WebSdkSource | null;
  getIntegrationsManager?(): {
    imaClientSideIntegration?: WebSdkImaClientSideIntegration;
    ssaiIntegration?: WebSdkSsaiIntegration;
    imaDaiIntegration?: WebSdkImaDaiIntegration;
  };
  getUiManager?(): WebSdkUiManager | null | undefined;
  addEventListener(
    event: string,
    callback: (eventData?: unknown) => void,
  ): void;
  removeEventListener(
    event: string,
    callback: (eventData?: unknown) => void,
  ): void;
}

// Cast Player constructor because public @brightcove/web-sdk/ui Player types
// define constructor parameter as internal PlayerDependencies instead of options.
function defaultPlayerFactory(
  options: WebSdkPlayerOptions,
): WebSdkPlayerInstance {
  const { integrationFactories, ...playerOptions } = options;
  if (options.enableThumbnails) {
    ensureThumbnailsIntegration(integrationFactories?.thumbnails);
  }
  if (options.enableAds) {
    ensureImaClientSideIntegration(integrationFactories?.imaClientSide);
  }
  if (options.enableSsai) {
    ensureSsaiIntegration(integrationFactories?.ssai);
  }
  if (options.enableDai) {
    ensureImaDaiIntegration(integrationFactories?.imaDai);
  }
  return new (Player as unknown as new (
    options: WebSdkPlayerOptions,
  ) => WebSdkPlayerInstance)(playerOptions);
}

export function createWebSdkPlayer(
  options: WebSdkPlayerOptions,
  integrationFactories: WebSdkIntegrationFactories,
): WebSdkPlayerInstance {
  return defaultPlayerFactory({ ...options, integrationFactories });
}

const BCP47_REGEX = /^[a-zA-Z]{2,3}(-[a-zA-Z0-9]+)*$/;

const isDescriptiveTrack = (track: WebSdkAudioTrack): boolean =>
  track.kind === 'descriptions' || track.kind === 'main-desc';

function extractErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string' && error.length > 0) return error;
  return 'Unknown web player error';
}

function getVideoElement(player: WebSdkPlayerInstance): HTMLVideoElement {
  const videoElement = player.getVideoElement();
  if (!videoElement) {
    throw new Error('The web player video element is not attached');
  }
  return videoElement;
}

function updateVideoVolume(player: WebSdkPlayerInstance, volume: number): void {
  const videoElement = getVideoElement(player);
  videoElement.volume = volume;
}

function updateVideoMuted(player: WebSdkPlayerInstance, muted: boolean): void {
  const videoElement = getVideoElement(player);
  videoElement.muted = muted;
}

export interface SidecarTrackInput {
  url: string;
  language: string;
  label?: string;
}

export interface BrightcovePlayerViewWebProps {
  accountId: string;
  policyKey: string;
  videoId?: string;
  videoIds?: string[];
  // Web-only, not part of the native Codegen contract: the generated
  // per-sample index.web.tsx injects this fixed list (baseline components
  // plus whatever this sample's installed features add) so the control bar
  // never shows a button (e.g. Picture-in-Picture) for a feature the sample
  // never installed — the web analogue of native samples never compiling in
  // a feature's code at all. App.tsx never sets this; BrightcovePlayerViewProps
  // (the type App.tsx actually sees) omits it.
  webControlBarComponents?: string[];
  repeatMode?: RepeatMode;
  audioDescriptionEnabled?: boolean;
  preferredPeakBitrate?: number;
  chapterSeekTime?: number;
  chapterSeekRequestId?: number;
  loop?: boolean;
  controlsEnabled?: boolean;
  sidecarTracks?: SidecarTrackInput[];
  customCaptionRenderingEnabled?: boolean;
  daiSourceId?: string;
  daiVideoId?: string;
  audioTrackId?: string;
  thumbnailSeekingEnabled?: boolean;
  preloadVideoId?: string;
  autoPlay?: boolean;
  volume?: number;
  muted?: boolean;
  playbackRate?: number;
  videoScalingMode?: VideoScalingMode;
  captionsEnabled?: boolean;
  captionTrackId?: string;
  pictureInPictureEnabled?: boolean;
  adTagUrl?: string;
  adConfigId?: string;
  onReady?: (event: { nativeEvent: ReadyEventData }) => void;
  onError?: (event: { nativeEvent: PlayerErrorEventData }) => void;
  onPlayerCommandError?: (event: {
    nativeEvent: PlayerCommandErrorEventData;
  }) => void;
  onCaptionsAvailable?: (event: {
    nativeEvent: CaptionsAvailableEventData;
  }) => void;
  onCaptionTrackChanged?: (event: {
    nativeEvent: CaptionTrackChangedEventData;
  }) => void;
  onAudioTracksAvailable?: (event: {
    nativeEvent: AudioTracksAvailableEventData;
  }) => void;
  onAudioTrackChanged?: (event: {
    nativeEvent: AudioTrackChangedEventData;
  }) => void;
  onPictureInPictureModeChanged?: (event: {
    nativeEvent: PictureInPictureModeChangedEventData;
  }) => void;
  onFullscreenChanged?: (event: {
    nativeEvent: FullscreenChangedEventData;
  }) => void;
  onTimedMetadata?: (event: { nativeEvent: TimedMetadataEventData }) => void;
  onPreloadQueued?: (event: { nativeEvent: PreloadQueuedEventData }) => void;
  onPreloadHandoff?: (event: { nativeEvent: PreloadHandoffEventData }) => void;
  onPreloadError?: (event: { nativeEvent: PreloadErrorEventData }) => void;
  onSourceLoading?: (event: { nativeEvent: SourceLoadingEventData }) => void;
  onFirstFrame?: (event: { nativeEvent: FirstFrameEventData }) => void;
  onSeekStarted?: (event: { nativeEvent: SeekStartedEventData }) => void;
  onSeekCompleted?: (event: { nativeEvent: SeekCompletedEventData }) => void;
  onDurationChanged?: (event: {
    nativeEvent: DurationChangedEventData;
  }) => void;
  onVideoSizeChanged?: (event: {
    nativeEvent: VideoSizeChangedEventData;
  }) => void;
  onPlay?: (event: { nativeEvent: null }) => void;
  onPause?: (event: { nativeEvent: null }) => void;
  onEnded?: (event: { nativeEvent: null }) => void;
  onProgress?: (event: { nativeEvent: PlaybackProgressEventData }) => void;
  onLiveStatus?: (event: { nativeEvent: LiveStatusEventData }) => void;
  onSeekableRangesChanged?: (event: {
    nativeEvent: SeekableRangesChangedEventData;
  }) => void;
  onQueueItemChanged?: (event: {
    nativeEvent: QueueItemChangedEventData;
  }) => void;
  onQueueItemFailed?: (event: {
    nativeEvent: QueueItemFailedEventData;
  }) => void;
  onQueueCompleted?: (event: { nativeEvent: null }) => void;
  onRebufferStart?: (event: { nativeEvent: null }) => void;
  onRebufferEnd?: (event: { nativeEvent: null }) => void;
  onAudioDescriptionAvailable?: (event: {
    nativeEvent: AudioDescriptionAvailableEventData;
  }) => void;
  onAudioDescriptionChanged?: (event: {
    nativeEvent: AudioDescriptionChangedEventData;
  }) => void;
  onRenditionChanged?: (event: {
    nativeEvent: RenditionChangedEventData;
  }) => void;
  onChapterSeekCompleted?: (event: {
    nativeEvent: ChapterSeekCompletedEventData;
  }) => void;
  onSidecarTrackStatus?: (event: {
    nativeEvent: SidecarTrackStatusEventData;
  }) => void;
  onCaptionCueChanged?: (event: {
    nativeEvent: CaptionCueEventData;
  }) => void;
  onAdStarted?: (event: { nativeEvent: AdEventData }) => void;
  onAdCompleted?: (event: { nativeEvent: AdEventData }) => void;
  onAdBreakStarted?: (event: { nativeEvent: AdBreakEventData }) => void;
  onAdBreakEnded?: (event: { nativeEvent: AdBreakEventData }) => void;
  onAllAdsCompleted?: (event: {
    nativeEvent: AllAdsCompletedEventData;
  }) => void;
  onAdError?: (event: { nativeEvent: AdErrorEventData }) => void;
  onAdPaused?: (event: { nativeEvent: AdPausedEventData }) => void;
  onAdResumed?: (event: { nativeEvent: AdResumedEventData }) => void;
  onAdProgress?: (event: { nativeEvent: AdProgressEventData }) => void;
  onAdQuartile?: (event: { nativeEvent: AdQuartileEventData }) => void;
  onAdSkipped?: (event: { nativeEvent: AdSkippedEventData }) => void;
  onAdInteraction?: (event: { nativeEvent: AdInteractionEventData }) => void;
  onAdMetadata?: (event: { nativeEvent: AdMetadataEventData }) => void;
  onAdOverlayStateChanged?: (event: {
    nativeEvent: AdOverlayStateChangedEventData;
  }) => void;
  style?: StyleProp<ViewStyle>;
  testID?: string;
  playerFactory?: (options: WebSdkPlayerOptions) => WebSdkPlayerInstance;
}

export interface BrightcovePlayerWebHandle {
  play: () => Promise<void>;
  pause: () => void;
  seekTo: (positionSeconds: number) => void;
  enterFullscreen?: () => Promise<void>;
  exitFullscreen?: () => Promise<void>;
  enterPictureInPicture?: () => Promise<void>;
  next?: () => void;
  previous?: () => void;
  reload?: () => void;
  seekToLiveEdge?: () => void;
}

export const BrightcovePlayerView = forwardRef<
  BrightcovePlayerWebHandle,
  BrightcovePlayerViewWebProps
>(function BrightcovePlayerViewComponent(props, ref) {
  const {
    accountId,
    policyKey,
    videoId = '',
    videoIds,
    repeatMode = 'off',
    loop,
    controlsEnabled = true,
    videoScalingMode = 'fit',
    thumbnailSeekingEnabled = false,
    chapterSeekTime = -1,
    chapterSeekRequestId = 0,
    autoPlay = true,
    volume,
    muted,
    playbackRate,
    adTagUrl,
    adConfigId,
    daiSourceId,
    daiVideoId,
    preloadVideoId,
    onReady,
    onError,
    onPlayerCommandError,
    onPlay,
    onPause,
    onEnded,
    onProgress,
    onLiveStatus,
    onSeekableRangesChanged,
    onTimedMetadata,
    audioDescriptionEnabled,
    onAudioDescriptionAvailable,
    onAudioDescriptionChanged,
    sidecarTracks,
    onSidecarTrackStatus,
    onQueueItemChanged,
    onQueueItemFailed,
    onQueueCompleted,
    onFullscreenChanged,
    onPictureInPictureModeChanged,
    pictureInPictureEnabled = false,
    preferredPeakBitrate,
    onRenditionChanged,
    audioTrackId,
    onAudioTracksAvailable,
    onAudioTrackChanged,
    captionsEnabled,
    captionTrackId,
    customCaptionRenderingEnabled = false,
    onCaptionsAvailable,
    onCaptionTrackChanged,
    onCaptionCueChanged,
    webControlBarComponents,
    onRebufferStart,
    onRebufferEnd,
    onChapterSeekCompleted,
    onAdStarted,
    onAdCompleted,
    onAdBreakStarted,
    onAdBreakEnded,
    onAllAdsCompleted,
    onAdError,
    onAdPaused,
    onAdResumed,
    onAdProgress,
    onAdQuartile,
    onAdSkipped,
    onAdInteraction,
    onAdMetadata,
    onAdOverlayStateChanged,
    onSourceLoading,
    onFirstFrame,
    onSeekStarted,
    onSeekCompleted,
    onDurationChanged,
    onVideoSizeChanged,
    onPreloadQueued,
    onPreloadHandoff,
    onPreloadError,
    style,
    testID,
    playerFactory = defaultPlayerFactory,
  } = props;

  const resolvedVideoId = videoId || (videoIds && videoIds.length > 0 ? videoIds[0] : '');
  const videoIdsKey = videoIds ? videoIds.join(',') : '';
  const videoIdsRef = useRef(videoIds);
  videoIdsRef.current = videoIds;
  const repeatModeRef = useRef(repeatMode);
  repeatModeRef.current = repeatMode;
  const loopRef = useRef(loop);
  loopRef.current = loop;

  const containerRef = useRef<HTMLDivElement | null>(null);
  const playerRef = useRef<WebSdkPlayerInstance | null>(null);
  const activeVideoIdRef = useRef('');
  const sourceGenerationRef = useRef(0);
  const sourceReadyRef = useRef(false);
  const disposedRef = useRef(false);
  const autoPlayRef = useRef(autoPlay);
  const thumbnailSeekingEnabledRef = useRef(thumbnailSeekingEnabled);
  const hasPlayedRef = useRef(false);
  const seekingRef = useRef(false);
  const rebufferingRef = useRef(false);
  const chapterRequestIdRef = useRef(0);
  const pendingChapterSeekRef = useRef<{ requestId: number; target: number } | null>(null);
  const firstFrameEmittedRef = useRef(false);
  // Mirrors Android's readyEmitted / iOS's _readyEmitted: onReady fires once
  // per source generation, never per canplay refire.
  const readyEmittedRef = useRef(false);
  // Mirrors native's sourceFailed: once the current source hit a terminal
  // error, every command except reload (the recovery path) is rejected with
  // invalid_state/source_failed. Cleared by every per-source reset below
  // (source effect, queue advance, handoff, reload).
  const sourceFailedRef = useRef(false);
  const lastLifecycleDurationRef = useRef<number | null>(null);
  const lastLifecycleVideoSizeRef = useRef<{ width: number; height: number } | null>(null);
  const playerProperties = {
    volume,
    muted,
    playbackRate,
    loop,
    repeatMode,
    controlsEnabled,
    videoScalingMode,
    adTagUrl,
    adConfigId,
    daiSourceId,
    daiVideoId,
    preloadVideoId,
    chapterSeekTime,
    chapterSeekRequestId,
    preferredPeakBitrate,
    audioTrackId,
    audioDescriptionEnabled,
    captionsEnabled,
    captionTrackId,
    customCaptionRenderingEnabled,
    sidecarTracks,
  };
  const playerPropertiesRef = useRef(playerProperties);
  const queueIndexRef = useRef(0);
  // The queue-completion contract fires onQueueCompleted exactly once per
  // loaded queue: the natural `ended` at the last item and (before the
  // contract correction) a manual boundary `next` could both reach the emit
  // path. Latched on first emit, reset with every per-source reset below
  // (source effect, reload, queue/handoff swap) — the same shape as the
  // native features' completionState.completionEmitted /
  // _queueCompletedEmitted.
  const queueCompletedEmittedRef = useRef(false);
  const lastRenditionKeyRef = useRef<string | null>(null);
  const lastAudioTracksSignatureRef = useRef<string | null>(null);
  const lastActiveAudioTrackIdRef = useRef<string | null>(null);
  const defaultAudioTrackIdRef = useRef<string | null>(null);
  const previousNonDescriptiveTrackIdRef = useRef<string | null>(null);
  const lastAdAvailabilityKeyRef = useRef<string | null>(null);
  const lastAdStateKeyRef = useRef<string | null>(null);
  // Fullscreen-change dedupe (the lastAdStateKeyRef pattern): Safari may
  // deliver both the standard and the prefixed fullscreen event for one
  // transition, and the handler must not re-emit an unchanged state.
  const lastFullscreenActiveRef = useRef<boolean | null>(null);
  const lastSeekableRangesKeyRef = useRef<string | null>(null);
  const lastLiveStatusKeyRef = useRef<string | null>(null);
  const lastCaptionsSignatureRef = useRef<string | null>(null);
  // '' (not null): every text track's mode defaults to 'disabled', so "no
  // track showing" is the real starting state, not an uninitialized
  // sentinel — starting from null would make the very first check (which
  // also resolves to '' when nothing is enabled) look like a change and
  // spuriously fire onCaptionTrackChanged for an off-to-off transition,
  // unlike native's CaptionsFeature.kt, which only calls setActiveTrackId
  // when the SDK reports an actual selected track.
  const lastActiveCaptionTrackIdRef = useRef<string>('');
  const lastCustomCaptionCueKeyRef = useRef<string | null>(null);
  const sidecarConfiguredRef = useRef<boolean>(false);
  const sidecarSelectedEmittedRef = useRef<boolean>(false);
  const sidecarValidatedRef = useRef<SidecarTrackInput[] | null>(null);
  const observedMetadataTracksRef = useRef<Set<unknown>>(new Set());
  const metadataTrackCleanupsRef = useRef<Array<() => void>>([]);
  const observedCaptionTracksRef = useRef<Set<WebSdkTextTrack>>(new Set());
  const captionTrackCleanupsRef = useRef<Array<() => void>>([]);
  // Set by the source effect: detaches the current source's cue-change
  // listeners and clears the observer registries. Called on every
  // same-player source swap so long queues cannot accumulate listeners.
  const flushTrackObserversRef = useRef<(() => void) | null>(null);
  const adRequestedRef = useRef(false);
  const daiRequestedRef = useRef(false);
  const preloadAbortRef = useRef<(() => void) | null>(null);
  const queueAbortRef = useRef<(() => void) | null>(null);
  const queueRequestGenerationRef = useRef(0);
  const preloadGenerationRef = useRef(0);
  const preloadedModelRef = useRef<unknown>(null);
  const preloadedVideoIdRef = useRef<string | null>(null);
  const preloadSourceVideoIdRef = useRef<string | null>(null);
  const callbacks = {
    onReady,
    onError,
    onPlayerCommandError,
    onPlay,
    onPause,
    onEnded,
    onProgress,
    onLiveStatus,
    onSeekableRangesChanged,
    onTimedMetadata,
    onQueueItemChanged,
    onQueueItemFailed,
    onQueueCompleted,
    onFullscreenChanged,
    onPictureInPictureModeChanged,
    onRenditionChanged,
    onAudioTracksAvailable,
    onAudioTrackChanged,
    onAudioDescriptionAvailable,
    onAudioDescriptionChanged,
    onCaptionsAvailable,
    onCaptionTrackChanged,
    onCaptionCueChanged,
    onSidecarTrackStatus,
    onRebufferStart,
    onRebufferEnd,
    onChapterSeekCompleted,
    onAdStarted,
    onAdCompleted,
    onAdBreakStarted,
    onAdBreakEnded,
    onAllAdsCompleted,
    onAdError,
    onAdPaused,
    onAdResumed,
    onAdProgress,
    onAdQuartile,
    onAdSkipped,
    onAdInteraction,
    onAdMetadata,
    onAdOverlayStateChanged,
    onSourceLoading,
    onFirstFrame,
    onSeekStarted,
    onSeekCompleted,
    onDurationChanged,
    onVideoSizeChanged,
    onPreloadQueued,
    onPreloadHandoff,
    onPreloadError,
  };
  const callbacksRef = useRef(callbacks);

  autoPlayRef.current = autoPlay;
  thumbnailSeekingEnabledRef.current = thumbnailSeekingEnabled;
  playerPropertiesRef.current = playerProperties;
  callbacksRef.current = callbacks;

  const dispatchCommandError = useCallback(
    (
      command: string,
      code: PlayerCommandErrorCode,
      message: string,
      nativeCode: string = code,
    ) => {
      if (disposedRef.current) return;
      callbacksRef.current.onPlayerCommandError?.({
        nativeEvent: { command, code, message, nativeCode },
      });
    },
    [],
  );

  // Commands other than reload are rejected while the current source is in
  // its terminal-failed state (the native sourceFailed contract); reload is
  // the recovery path and stays available.
  const rejectWhenSourceFailed = useCallback(
    (command: string): boolean => {
      if (!sourceFailedRef.current) return false;
      dispatchCommandError(
        command,
        'invalid_state',
        `Cannot execute ${command}: the current source failed`,
        'source_failed',
      );
      return true;
    },
    [dispatchCommandError],
  );

  const executePlay = useCallback(async () => {
    if (rejectWhenSourceFailed('play')) return;
    const player = playerRef.current;
    if (disposedRef.current || !player || !sourceReadyRef.current) {
      dispatchCommandError(
        'play',
        'not_ready',
        'Cannot execute play: the player source is not ready',
        'source_not_ready',
      );
      return;
    }
    try {
      const result = player.play();
      if (isPromiseLike(result)) await result;
    } catch (error) {
      dispatchCommandError(
        'play',
        'failed',
        extractErrorMessage(error),
        'play_rejected',
      );
    }
  }, [dispatchCommandError, rejectWhenSourceFailed]);

  const executePause = useCallback(() => {
    if (rejectWhenSourceFailed('pause')) return;
    const player = playerRef.current;
    if (disposedRef.current || !player || !sourceReadyRef.current) {
      dispatchCommandError(
        'pause',
        'not_ready',
        'Cannot execute pause: the player source is not ready',
        'source_not_ready',
      );
      return;
    }
    try {
      player.pause();
    } catch (error) {
      dispatchCommandError(
        'pause',
        'failed',
        extractErrorMessage(error),
        'pause_failed',
      );
    }
  }, [dispatchCommandError, rejectWhenSourceFailed]);

  const executeSeekTo = useCallback(
    (positionSeconds: number) => {
      if (rejectWhenSourceFailed('seekTo')) return;
      const validationError = validateSeekPosition(positionSeconds);
      if (validationError) {
        dispatchCommandError(
          'seekTo',
          'invalid_argument',
          validationError,
          'invalid_seek_position',
        );
        return;
      }
      const player = playerRef.current;
      if (disposedRef.current || !player || !sourceReadyRef.current) {
        dispatchCommandError(
          'seekTo',
          'not_ready',
          'Cannot execute seekTo: the player source is not ready',
          'source_not_ready',
        );
        return;
      }
      try {
        player.seek(positionSeconds);
      } catch (error) {
        dispatchCommandError(
          'seekTo',
          'failed',
          extractErrorMessage(error),
          'seek_failed',
        );
      }
    },
    [dispatchCommandError, rejectWhenSourceFailed],
  );

  const executeEnterFullscreen = useCallback(async () => {
    const container = containerRef.current;
    if (!container) {
      dispatchCommandError(
        'enterFullscreen',
        'not_ready',
        'Cannot enter fullscreen: the player is not mounted',
        'player_not_ready',
      );
      return;
    }
    // Fullscreen the player's own element (video.js root), not our wrapper
    // container. The in-player FullscreenToggle fullscreens the video.js
    // element itself; if our command fullscreened the container instead, the
    // toggle would stay labelled "Fullscreen" while a fullscreen is already
    // active, and pressing it would request fullscreen on yet another element
    // without ever leaving — so the only way out was Escape. Targeting the
    // same element the toggle targets keeps the two in sync, so the control
    // can both enter and exit.
    const videoEl = playerRef.current?.getVideoElement?.() ?? null;
    const playerEl =
      (videoEl?.closest?.('.video-js') as HTMLElement | null) ?? null;
    const target = playerEl ?? container;
    // Safari (notably iPadOS) still requires the prefixed request method; it
    // exists exactly where the standard one does not.
    const prefixedTarget = target as HTMLElement & {
      webkitRequestFullscreen?: () => Promise<void> | void;
    };
    const request =
      typeof target.requestFullscreen === 'function'
        ? () => target.requestFullscreen()
        : typeof prefixedTarget.webkitRequestFullscreen === 'function'
          ? () => prefixedTarget.webkitRequestFullscreen!()
          : null;
    if (!request) {
      dispatchCommandError(
        'enterFullscreen',
        'unavailable',
        'Fullscreen API is not supported in this environment',
        'fullscreen_unsupported',
      );
      return;
    }
    try {
      await request();
    } catch (error) {
      dispatchCommandError(
        'enterFullscreen',
        'failed',
        extractErrorMessage(error),
        'fullscreen_failed',
      );
    }
  }, [dispatchCommandError]);

  const executeExitFullscreen = useCallback(async () => {
    if (typeof document === 'undefined') {
      dispatchCommandError(
        'exitFullscreen',
        'unavailable',
        'Fullscreen API is not supported in this environment',
        'fullscreen_unsupported',
      );
      return;
    }
    const prefixedDocument = document as DocumentWithWebkitFullscreen;
    const exit =
      typeof document.exitFullscreen === 'function'
        ? () => document.exitFullscreen()
        : typeof prefixedDocument.webkitExitFullscreen === 'function'
          ? () => prefixedDocument.webkitExitFullscreen!()
          : null;
    if (!exit) {
      dispatchCommandError(
        'exitFullscreen',
        'unavailable',
        'Fullscreen API is not supported in this environment',
        'fullscreen_unsupported',
      );
      return;
    }
    try {
      // Both getters report the same element (standard first, prefixed
      // fallback), so either one deciding "something is fullscreen" is a
      // valid exit precondition.
      const fullscreenElement =
        document.fullscreenElement ?? prefixedDocument.webkitFullscreenElement;
      if (fullscreenElement) {
        await exit();
      }
    } catch (error) {
      dispatchCommandError(
        'exitFullscreen',
        'failed',
        extractErrorMessage(error),
        'exit_fullscreen_failed',
      );
    }
  }, [dispatchCommandError]);

  const executeEnterPiP = useCallback(async () => {
    if (!pictureInPictureEnabled) {
      dispatchCommandError(
        'enterPictureInPicture',
        'disabled',
        'Picture-in-Picture is disabled on this player',
        'pip_disabled',
      );
      return;
    }
    const player = playerRef.current;
    const video = player?.getVideoElement();
    if (!video) {
      dispatchCommandError(
        'enterPictureInPicture',
        'not_ready',
        'Cannot enter Picture-in-Picture: video element is not available',
        'video_element_unavailable',
      );
      return;
    }
    // Safari (macOS since 10 / iPadOS) exposes PiP only through the prefixed
    // presentation-mode API; use the standard request where it exists.
    const prefixedVideo = video as VideoElementWithWebkitPresentationMode;
    const request =
      typeof video.requestPictureInPicture === 'function'
        ? () => video.requestPictureInPicture()
        : typeof prefixedVideo.webkitSetPresentationMode === 'function' &&
            typeof prefixedVideo.webkitSupportsPresentationMode === 'function' &&
            prefixedVideo.webkitSupportsPresentationMode('picture-in-picture')
          ? () => prefixedVideo.webkitSetPresentationMode!('picture-in-picture')
          : null;
    if (!request) {
      dispatchCommandError(
        'enterPictureInPicture',
        'unavailable',
        'Picture-in-Picture is not supported in this browser',
        'pip_unsupported',
      );
      return;
    }
    try {
      await request();
    } catch (error) {
      dispatchCommandError(
        'enterPictureInPicture',
        'failed',
        extractErrorMessage(error),
        'pip_failed',
      );
    }
  }, [dispatchCommandError, pictureInPictureEnabled]);

  const executeSeekToLiveEdge = useCallback(() => {
    if (rejectWhenSourceFailed('seekToLiveEdge')) return;
    const player = playerRef.current;
    if (disposedRef.current || !player || !sourceReadyRef.current) {
      dispatchCommandError(
        'seekToLiveEdge',
        'not_ready',
        'Cannot execute seekToLiveEdge: the player source is not ready',
        'source_not_ready',
      );
      return;
    }
    const videoElement = player.getVideoElement();
    if (!videoElement) {
      dispatchCommandError(
        'seekToLiveEdge',
        'not_ready',
        'Cannot execute seekToLiveEdge: video element is not available',
        'video_element_unavailable',
      );
      return;
    }
    const isLive =
      videoElement.duration === Infinity ||
      (!Number.isFinite(videoElement.duration) && videoElement.duration > 0);
    if (!isLive || videoElement.seekable.length === 0) {
      dispatchCommandError(
        'seekToLiveEdge',
        'invalid_state',
        'Cannot execute seekToLiveEdge: current stream is not a live stream',
        'not_live',
      );
      return;
    }
    const liveEdge = videoElement.seekable.end(videoElement.seekable.length - 1);
    try {
      player.seek(liveEdge);
    } catch (error) {
      dispatchCommandError(
        'seekToLiveEdge',
        'failed',
        extractErrorMessage(error),
        'seek_to_live_edge_failed',
      );
    }
  }, [dispatchCommandError, rejectWhenSourceFailed]);

  // Per-source resets for state that a same-player source swap (queue
  // advance, preload handoff, reload, videoIds change) must not leak across:
  // pending chapter seeks, custom-caption cue dedupe, caption/audio-track
  // signatures, and the sidecar validation/selection latches. A swap on the
  // same player element keeps the old source's cues/status firing otherwise.
  const resetSourceScopedState = useCallback(() => {
    // A same-player source swap leaves the element loaded but not ready for
    // the new source: until the new source's canplay, commands must report
    // not_ready rather than dispatch into the previous source's player state.
    sourceReadyRef.current = false;
    hasPlayedRef.current = false;
    seekingRef.current = false;
    if (rebufferingRef.current) {
      rebufferingRef.current = false;
      callbacksRef.current.onRebufferEnd?.({ nativeEvent: null });
    }
    lastRenditionKeyRef.current = null;
    lastAudioTracksSignatureRef.current = null;
    lastActiveAudioTrackIdRef.current = null;
    defaultAudioTrackIdRef.current = null;
    lastCaptionsSignatureRef.current = null;
    lastActiveCaptionTrackIdRef.current = '';
    lastCustomCaptionCueKeyRef.current = null;
    pendingChapterSeekRef.current = null;
    lastSeekableRangesKeyRef.current = null;
    lastLiveStatusKeyRef.current = null;
    lastLifecycleDurationRef.current = null;
    lastLifecycleVideoSizeRef.current = null;
    lastFullscreenActiveRef.current = null;
    lastAdAvailabilityKeyRef.current = null;
    lastAdStateKeyRef.current = null;
    previousNonDescriptiveTrackIdRef.current = null;
    flushTrackObserversRef.current?.();
    const hadSidecarTracks = sidecarConfiguredRef.current;
    sidecarConfiguredRef.current = false;
    sidecarValidatedRef.current = null;
    if (hadSidecarTracks) {
      sidecarSelectedEmittedRef.current = false;
      callbacksRef.current.onSidecarTrackStatus?.({
        nativeEvent: {
          status: 'reset',
          language: '',
          label: '',
          error: '',
          nativeCode: '',
        },
      });
    }
  }, []);

  const loadVideoIndex = useCallback((index: number) => {
    const currentVideoIds = videoIdsRef.current;
    if (!currentVideoIds || index < 0 || index >= currentVideoIds.length) return;
    queueIndexRef.current = index;
    const nextId = currentVideoIds[index];
    const player = playerRef.current;
    if (!player) return;
    // repeatMode "one" loops only the current item, exactly like native's
    // ExoPlayer REPEAT_MODE_ONE / iOS repeatMode "one": `ended` never fires,
    // so the queue never completes and `next` never auto-wraps. Set/unset per
    // item here because the element resets `loop` semantics on every
    // loadBrightcoveVideoModel. The standalone `loop` prop stays a separate,
    // videoId-scoped mechanism, matching native (a `loop` prop of true wins
    // over a queue repeatMode of "off" only for the standalone-loop contract).
    try {
      const videoEl = player.getVideoElement();
      if (videoEl) {
        videoEl.loop = repeatModeRef.current === 'one' || loopRef.current === true;
      }
    } catch {
      // ignore
    }
    queueAbortRef.current?.();
    queueAbortRef.current = null;
    const requestGeneration = queueRequestGenerationRef.current + 1;
    queueRequestGenerationRef.current = requestGeneration;
    // A queue advance swaps the active source on the same player instance,
    // so every per-source latch must reset with it: the active id drives
    // onReady/rendition/audio-description payloads, and without clearing
    // adRequested/firstFrame the new item would never report its own first
    // frame or request its own client-side ads.
    activeVideoIdRef.current = nextId;
    adRequestedRef.current = false;
    daiRequestedRef.current = false;
    firstFrameEmittedRef.current = false;
    readyEmittedRef.current = false;
    sourceFailedRef.current = false;
    resetSourceScopedState();
    callbacksRef.current.onAudioTracksAvailable?.({ nativeEvent: { tracks: [] } });
    callbacksRef.current.onAudioTrackChanged?.({
      nativeEvent: { id: '', language: '' },
    });
    callbacksRef.current.onCaptionsAvailable?.({ nativeEvent: { tracks: [] } });
    callbacksRef.current.onCaptionTrackChanged?.({
      nativeEvent: { id: '', language: '' },
    });
    callbacksRef.current.onQueueItemChanged?.({
      nativeEvent: { videoId: nextId, index },
    });
    const req = player.getVideoByIdFromPlaybackApi({ videoId: nextId });
    queueAbortRef.current = req.abort;
    req.promise
      .then(model => {
        if (
          disposedRef.current ||
          playerRef.current !== player ||
          queueRequestGenerationRef.current !== requestGeneration ||
          activeVideoIdRef.current !== nextId
        ) return;
        queueAbortRef.current = null;
        player.loadBrightcoveVideoModel(model);
      })
      .catch(err => {
        if (
          disposedRef.current ||
          playerRef.current !== player ||
          queueRequestGenerationRef.current !== requestGeneration ||
          activeVideoIdRef.current !== nextId
        ) return;
        queueAbortRef.current = null;
        const error = classifyWebPlayerError(err);
        callbacksRef.current.onQueueItemFailed?.({
          nativeEvent: { videoId: nextId, index, ...error },
        });
        if (index + 1 < currentVideoIds.length) {
          loadVideoIndex(index + 1);
          return;
        }
        // Nothing is left to play, so this is a terminal failure: latch it as
        // every other terminal error does, so commands other than reload are
        // rejected with source_failed until a new source or reload (native
        // latches the same case through its source-error path).
        sourceFailedRef.current = true;
        callbacksRef.current.onError?.({ nativeEvent: error });
      });
  }, [resetSourceScopedState]);

  // preferredPeakBitrate is a ceiling, not an exact selection: restrict the
  // adaptive selector to levels at or below the ceiling (or every level when
  // unset/0) and let it keep choosing among those — the same "preference,
  // not a command" contract as the native bridges' setPeakBitrate /
  // preferredPeakRate. The web SDK exposes no quality-levels-changed event,
  // so the ceiling is re-applied on every canplay firing (a refire means the
  // ladder was rebuilt or recovered) and on a prop change — a fresh levels
  // list from a source swap is covered by the canplay that follows it.
  const applyPreferredPeakBitrate = useCallback(() => {
    const player = playerRef.current;
    if (!player || !sourceReadyRef.current) return;
    const ceiling = playerPropertiesRef.current.preferredPeakBitrate ?? 0;
    try {
      const levels = player.getQualityLevels();
      if (levels.length === 0) return;
      if (ceiling <= 0) {
        levels.forEach(level => {
          level.enabled = true;
        });
        return;
      }
      const anyWithinCeiling = levels.some(level => level.bitrate <= ceiling);
      if (anyWithinCeiling) {
        levels.forEach(level => {
          level.enabled = level.bitrate <= ceiling;
        });
      } else {
        const lowestBitrate = Math.min(...levels.map(l => l.bitrate));
        levels.forEach(level => {
          level.enabled = level.bitrate === lowestBitrate;
        });
      }
    } catch {
      // ignore: quality levels are a best-effort preference, never fatal.
    }
  }, []);

  // audioTrackId names the desired track; clearing it (empty/undefined)
  // reverts to whichever track the manifest itself marks as the default
  // (DEFAULT=YES) — the same "explicit selection, else fall back to the
  // source's own default" contract as the native bridges' Clear action.
  // Unlike quality levels, AudioTrack.enabled IS the selection itself (a
  // real AudioTrackList only ever has one track enabled at a time), so
  // selecting a track is a single selectAudioTrack call, not a per-level
  // restriction loop.
  const applyAudioTrackSelection = useCallback(() => {
    const player = playerRef.current;
    if (!player || !sourceReadyRef.current) return;
    const requestedId = playerPropertiesRef.current.audioTrackId;
    try {
      const tracks = player.getAudioTracks();
      if (tracks.length === 0) return;
      if (requestedId) {
        const requested = tracks.find(track => track.id === requestedId);
        if (requested && !requested.enabled) {
          player.selectAudioTrack(requested);
        }
        return;
      }
      const defaultId = defaultAudioTrackIdRef.current;
      if (!defaultId) return;
      const currentlyEnabled = tracks.find(track => track.enabled);
      if (currentlyEnabled && currentlyEnabled.id !== defaultId) {
        const fallback = tracks.find(track => track.id === defaultId);
        if (fallback) player.selectAudioTrack(fallback);
      }
    } catch {
      // ignore: audio track selection is a best-effort preference, never fatal.
    }
  }, []);

  const applyAudioDescriptionSelection = useCallback(() => {
    const player = playerRef.current;
    if (!player || !sourceReadyRef.current) return;
    const { audioDescriptionEnabled: enabled } = playerPropertiesRef.current;
    try {
      const tracks = player.getAudioTracks();
      if (tracks.length === 0) return;
      const descTrack = tracks.find(isDescriptiveTrack);
      if (enabled) {
        if (descTrack && !descTrack.enabled) {
          const currentNormal = tracks.find(
            t => t.enabled && !isDescriptiveTrack(t),
          );
          if (currentNormal) {
            previousNonDescriptiveTrackIdRef.current = currentNormal.id;
          }
          player.selectAudioTrack(descTrack);
        }
      } else {
        const activeDesc = tracks.find(t => t.enabled && isDescriptiveTrack(t));
        if (activeDesc) {
          const prevId = previousNonDescriptiveTrackIdRef.current;
          const target =
            (prevId &&
              tracks.find(t => t.id === prevId && !isDescriptiveTrack(t))) ||
            tracks.find(t => !isDescriptiveTrack(t));
          if (target && !target.enabled) {
            player.selectAudioTrack(target);
          }
        }
      }
    } catch {
      // ignore: audio description selection is a best-effort preference.
    }
  }, []);

  const applyControlsEnabled = useCallback(() => {
    const player = playerRef.current;
    if (!player) return;
    const { controlsEnabled: enabled = true } = playerPropertiesRef.current;
    try {
      const uiManager = player.getUiManager?.();
      const containerComponent = uiManager?.getPlayerContainerUiComponent?.();
      const controlBar = containerComponent?.getChild?.('ControlBar');
      if (
        !controlBar ||
        typeof controlBar.show !== 'function' ||
        typeof controlBar.hide !== 'function'
      ) {
        console.error(
          '[BrightcoveWebPlayer] ControlBar is unavailable through the UI manager',
        );
        return;
      }
      if (enabled) {
        controlBar.show();
      } else {
        controlBar.hide();
      }
    } catch (error) {
      console.error(
        '[BrightcoveWebPlayer] Failed to update ControlBar visibility',
        error,
      );
    }
  }, []);

  const performChapterSeek = useCallback(() => {
    const player = playerRef.current;
    if (!player || !sourceReadyRef.current) return;
    const { chapterSeekTime: target, chapterSeekRequestId: requestId } =
      playerPropertiesRef.current;
    if (requestId <= 0 || requestId === chapterRequestIdRef.current) return;
    if (target < 0) {
      chapterRequestIdRef.current = requestId;
      return;
    }
    if (!Number.isFinite(target) || target < 0) {
      chapterRequestIdRef.current = requestId;
      callbacksRef.current.onChapterSeekCompleted?.({
        nativeEvent: { requestId, positionSeconds: target, completed: false },
      });
      return;
    }
    const videoElement = player.getVideoElement();
    if (!videoElement) return;
    if (Number.isFinite(videoElement.duration) && target > videoElement.duration + 0.5) {
      chapterRequestIdRef.current = requestId;
      callbacksRef.current.onChapterSeekCompleted?.({
        nativeEvent: {
          requestId,
          positionSeconds: target,
          completed: false,
        },
      });
      return;
    }
    chapterRequestIdRef.current = requestId;
    pendingChapterSeekRef.current = { requestId, target };
    try {
      player.seek(target);
    } catch {
      pendingChapterSeekRef.current = null;
      callbacksRef.current.onChapterSeekCompleted?.({
        nativeEvent: { requestId, positionSeconds: target, completed: false },
      });
    }
  }, []);

  const cancelPreload = useCallback(() => {
    preloadGenerationRef.current += 1;
    preloadAbortRef.current?.();
    preloadAbortRef.current = null;
    preloadedModelRef.current = null;
    preloadedVideoIdRef.current = null;
    preloadSourceVideoIdRef.current = null;
  }, []);

  const startPreload = useCallback(() => {
    const player = playerRef.current;
    const targetVideoId = playerPropertiesRef.current.preloadVideoId?.trim() || '';
    if (!targetVideoId || targetVideoId === activeVideoIdRef.current) {
      cancelPreload();
      return;
    }
    if (
      preloadedVideoIdRef.current === targetVideoId &&
      preloadedModelRef.current !== null
    ) {
      return;
    }
    if (!player || !sourceReadyRef.current) return;

    preloadAbortRef.current?.();
    const generation = ++preloadGenerationRef.current;
    const sourceGeneration = sourceGenerationRef.current;
    preloadedModelRef.current = null;
    preloadedVideoIdRef.current = null;
    preloadSourceVideoIdRef.current = activeVideoIdRef.current;

    const request = player.getVideoByIdFromPlaybackApi({
      videoId: targetVideoId,
    });
    preloadAbortRef.current = request.abort;
    request.promise
      .then(model => {
        if (
          generation !== preloadGenerationRef.current ||
          sourceGeneration !== sourceGenerationRef.current ||
          playerRef.current !== player ||
          disposedRef.current
        ) {
          return;
        }
        preloadAbortRef.current = null;
        if (!model) {
          callbacksRef.current.onPreloadError?.({
            nativeEvent: {
              videoId: targetVideoId,
              code: 'not_found',
              message: 'Brightcove returned no video model for the preload request',
              nativeCode: 'preload_empty_response',
            },
          });
          return;
        }
        preloadedModelRef.current = model;
        preloadedVideoIdRef.current = targetVideoId;
        callbacksRef.current.onPreloadQueued?.({
          nativeEvent: { videoId: targetVideoId },
        });
      })
      .catch(error => {
        if (
          generation !== preloadGenerationRef.current ||
          sourceGeneration !== sourceGenerationRef.current ||
          playerRef.current !== player ||
          disposedRef.current
        ) {
          return;
        }
        preloadAbortRef.current = null;
        const classified = classifyWebPlayerError(error);
        callbacksRef.current.onPreloadError?.({
          nativeEvent: {
            videoId: targetVideoId,
            code: classified.code,
            message: classified.message,
            nativeCode: 'preload_' + classified.nativeCode,
          },
        });
      });
  }, [cancelPreload]);

  // captionsEnabled and captionTrackId together form one selection, mirroring
  // the native bridges' combined-prop contract (see CaptionsFeature.kt):
  // captionsEnabled=false always means "no track showing" regardless of
  // captionTrackId; captionsEnabled=true with no (or an unknown) id falls
  // back to the first selectable track. mode is the real DOM selection
  // mechanism (a real TextTrackList only ever shows one text track at a
  // time, matching AudioTrack.enabled's "at most one active" semantics).
  //
  // When a manifest embeds native HLS SUBTITLES groups (as most VOD sources
  // with captions do), videojs-http-streaming independently auto-registers
  // each group a second time as a native kind:'subtitles' TextTrack,
  // labeled by the manifest's raw NAME attribute rather than a stable id,
  // and immediately honors the manifest's own DEFAULT=YES on that native
  // track — entirely outside this component's control. Left alone, that
  // duplicate renders a caption cue the customer never asked for (confirmed
  // live: "English" showing on load despite captionsEnabled={false}).
  // Called unconditionally on every playerTextTracksChanged, independent of
  // whether the kind:'captions' selection below is reasserted, since a
  // native track can flip back on (e.g. the SDK's own control-bar caption
  // menu also lists these by their raw manifest label) at any time.
  const disableNativeSubtitleTracks = useCallback((tracks: WebSdkTextTrack[]) => {
    tracks.forEach(track => {
      if (track.kind === 'subtitles') track.mode = 'disabled';
    });
  }, []);

  // Only kind 'captions' tracks — the ones the Brightcove Playback API's
  // model.textTracks explicitly lists and the SDK adds via addTextTrack,
  // carrying the stable per-source ids CaptionsAvailableEventData promises
  // — are selectable; see disableNativeSubtitleTracks for why kind
  // 'subtitles' is excluded. mode is the real DOM selection mechanism (a
  // real TextTrackList only ever shows one text track at a time, matching
  // AudioTrack.enabled's "at most one active" semantics).
  const applyCaptionSelection = useCallback(() => {
    const player = playerRef.current;
    if (!player || !sourceReadyRef.current) return;
    try {
      const allTracks = player.getTextTracks();
      disableNativeSubtitleTracks(allTracks);
      const selectable = allTracks.filter(track => track.kind === 'captions');
      if (selectable.length === 0) return;
      const { captionsEnabled: enabled, captionTrackId: requestedId } =
        playerPropertiesRef.current;
      const customRendering =
        playerPropertiesRef.current.customCaptionRenderingEnabled;
      const target = enabled
        ? requestedId
          ? selectable.find(track => track.id === requestedId) ?? null
          : selectable[0]
        : null;
      selectable.forEach(track => {
        track.mode =
          track === target ? (customRendering ? 'hidden' : 'showing') : 'disabled';
      });
    } catch {
      // ignore: caption selection is a best-effort preference, never fatal.
    }
  }, [disableNativeSubtitleTracks]);

  const applySidecarTrack = useCallback(
    (playerInstance?: WebSdkPlayerInstance | null) => {
      const { sidecarTracks: reqTracks } = playerPropertiesRef.current;
      if (!reqTracks || reqTracks.length === 0) return;

      const player = playerInstance || playerRef.current;
      if (!player) return;

      // Validation emits once per props transaction: applySidecarTrack runs
      // both from the props effect and again once the player source is ready,
      // and re-validating the same value would duplicate every failed/configured
      // emission.
      if (sidecarValidatedRef.current === reqTracks) return;
      sidecarValidatedRef.current = reqTracks;

      const seenLanguages = new Set<string>();
      reqTracks.forEach(track => {
        const reqUrl = track?.url;
        const reqLanguage = track?.language;
        const reqLabel = track?.label;
        const label = reqLabel || reqLanguage;

        const emitFailed = (nativeCode: string) => {
          callbacksRef.current.onSidecarTrackStatus?.({
            nativeEvent: {
              status: 'failed',
              language: reqLanguage || '',
              label: label || '',
              error: 'invalid_configuration',
              nativeCode,
            },
          });
        };

        if (!reqUrl || !reqUrl.trim()) return;
        if (!reqLanguage || !reqLanguage.trim()) {
          emitFailed('missing_language_tag');
          return;
        }

        let isHttps = false;
        try {
          const parsed = new URL(reqUrl);
          isHttps = parsed.protocol === 'https:' && parsed.hostname.length > 0;
        } catch {
          isHttps = false;
        }
        if (!isHttps || !reqUrl.toLowerCase().startsWith('https://')) {
          emitFailed('insecure_or_invalid_url');
          return;
        }

        if (!BCP47_REGEX.test(reqLanguage)) {
          emitFailed('invalid_language_tag');
          return;
        }

        if (seenLanguages.has(reqLanguage.toLowerCase())) {
          emitFailed('duplicate_language');
          return;
        }
        seenLanguages.add(reqLanguage.toLowerCase());

        try {
          const trackId = 'sidecar-' + reqLanguage;
          const alreadyAdded = player
            .getTextTracks()
            .some(t => t.id === trackId);
          if (typeof player.addTextTrack === 'function' && !alreadyAdded) {
            player.addTextTrack({
              id: trackId,
              kind: 'captions',
              language: reqLanguage,
              label,
              src: reqUrl,
            });
            sidecarConfiguredRef.current = true;
            callbacksRef.current.onSidecarTrackStatus?.({
              nativeEvent: {
                status: 'configured',
                language: reqLanguage,
                label,
                error: '',
                nativeCode: '',
              },
            });
          }
        } catch {
          callbacksRef.current.onSidecarTrackStatus?.({
            nativeEvent: {
              status: 'failed',
              language: reqLanguage,
              label,
              error: 'load',
              nativeCode: 'sidecar_vtt_load_failed',
            },
          });
        }
      });
    },
    [],
  );

  const executeNext = useCallback(() => {
    if (rejectWhenSourceFailed('next')) return;
    const player = playerRef.current;
    if (disposedRef.current || !player || !sourceReadyRef.current) {
      dispatchCommandError(
        'next',
        'not_ready',
        'Cannot execute next: the player source is not ready',
        'source_not_ready',
      );
      return;
    }
    const currentVideoIds = videoIdsRef.current;
    if (!currentVideoIds || currentVideoIds.length === 0) {
      // Same typed no-queue rejection the native features emit.
      dispatchCommandError(
        'next',
        'invalid_state',
        'Cannot advance the queue: no queue is loaded in this player',
        'queue_not_loaded',
      );
      return;
    }
    const nextIdx = queueIndexRef.current + 1;
    if (nextIdx < currentVideoIds.length) {
      loadVideoIndex(nextIdx);
      return;
    }
    if (repeatModeRef.current === 'all') {
      // Wrapping mirrors native repeat-all: item 0 follows the last item.
      loadVideoIndex(0);
      return;
    }
    // At the last item, a manual `next` cannot advance the queue. Report
    // the typed at-end rejection — the same queue_at_end contract the
    // native features emit — instead of firing onQueueCompleted, which is
    // the natural-completion event only (the last item's own `ended`).
    dispatchCommandError(
      'next',
      'invalid_state',
      "Cannot advance the queue: the last item is already playing and the repeat mode does not wrap the queue",
      'queue_at_end',
    );
  }, [loadVideoIndex, dispatchCommandError, rejectWhenSourceFailed]);

  const executePrevious = useCallback(() => {
    if (rejectWhenSourceFailed('previous')) return;
    const player = playerRef.current;
    if (disposedRef.current || !player || !sourceReadyRef.current) {
      dispatchCommandError(
        'previous',
        'not_ready',
        'Cannot execute previous: the player source is not ready',
        'source_not_ready',
      );
      return;
    }
    const currentVideoIds = videoIdsRef.current;
    if (!currentVideoIds || currentVideoIds.length === 0) {
      // Same typed no-queue rejection the native features emit.
      dispatchCommandError(
        'previous',
        'invalid_state',
        'Cannot go to the previous queue item: no queue is loaded in this player',
        'queue_not_loaded',
      );
      return;
    }
    const previousIdx = queueIndexRef.current - 1;
    if (previousIdx >= 0) {
      loadVideoIndex(previousIdx);
      return;
    }
    if (repeatModeRef.current === 'all') {
      // Wrapping mirrors native repeat-all: the last item precedes item 0.
      loadVideoIndex(currentVideoIds.length - 1);
      return;
    }
    // At the first item without wrap, restart the current item — the same
    // previous-at-first contract the native features implement. "At first"
    // is a valid position, so this never fails while a queue is loaded.
    const videoEl = player.getVideoElement();
    try {
      if (videoEl) videoEl.currentTime = 0;
      player.play();
    } catch (error) {
      dispatchCommandError(
        'previous',
        'failed',
        extractErrorMessage(error),
        'previous_restart_failed',
      );
    }
  }, [loadVideoIndex, dispatchCommandError, rejectWhenSourceFailed]);

  const executeReload = useCallback(() => {
    const player = playerRef.current;
    // Mirrors Android/iOS: reload is the recovery path from a source that
    // failed before reaching readiness, so it must NOT require the old source
    // to be ready. Only a live player is required; the fetch below re-drives
    // the source from scratch.
    if (disposedRef.current || !player) {
      dispatchCommandError(
        'reload',
        'not_ready',
        'Cannot execute reload: the player is not ready',
        'player_not_ready',
      );
      return;
    }
    if (!resolvedVideoId.trim()) {
      dispatchCommandError(
        'reload',
        'invalid_argument',
        'Cannot execute reload: videoId is required',
        'missing_video_id',
      );
      return;
    }
    // Reload invalidates whatever the queue/preload machinery had in flight:
    // an un-aborted queue fetch would resolve later and loadBrightcoveVideoModel
    // over this reload (last-resolved wins instead of last-requested), and
    // stale queueIndex/activeVideoId would make onReady/onQueueItemChanged
    // report the previous item. Join the same generation the queue uses and
    // reset the per-source state exactly like a source change.
    queueRequestGenerationRef.current += 1;
    queueAbortRef.current?.();
    queueAbortRef.current = null;
    preloadAbortRef.current?.();
    preloadAbortRef.current = null;
    preloadedModelRef.current = null;
    preloadedVideoIdRef.current = null;
    preloadSourceVideoIdRef.current = null;
    sourceReadyRef.current = false;
    sourceFailedRef.current = false;
    readyEmittedRef.current = false;
    activeVideoIdRef.current = resolvedVideoId;
    adRequestedRef.current = false;
    daiRequestedRef.current = false;
    firstFrameEmittedRef.current = false;
    resetSourceScopedState();
    const videoIdsForReload = videoIdsRef.current;
    if (videoIdsForReload && videoIdsForReload.length > 0) {
      const reloadIndex = videoIdsForReload.indexOf(resolvedVideoId);
      queueIndexRef.current = reloadIndex >= 0 ? reloadIndex : 0;
      // A reload restarts the queue from the reloaded item: the queue can
      // complete again, so the once-per-queue completion latch re-arms.
      queueCompletedEmittedRef.current = false;
    }
    callbacksRef.current.onSourceLoading?.({
      nativeEvent: { videoId: resolvedVideoId },
    });
    try {
      const req = player.getVideoByIdFromPlaybackApi({ videoId: resolvedVideoId });
      const requestGeneration = queueRequestGenerationRef.current;
      queueAbortRef.current = req.abort;
      req.promise
        .then(model => {
          if (
            disposedRef.current ||
            playerRef.current !== player ||
            queueRequestGenerationRef.current !== requestGeneration ||
            activeVideoIdRef.current !== resolvedVideoId
          )
            return;
          queueAbortRef.current = null;
          try {
            // A queue's reload restarts its item: the changed-item event must
            // report the reloaded item, same as the mount path.
            const videoIdsForItem = videoIdsRef.current;
            if (videoIdsForItem && videoIdsForItem.length > 0) {
              callbacksRef.current.onQueueItemChanged?.({
                nativeEvent: {
                  videoId: videoIdsForItem[queueIndexRef.current] ?? resolvedVideoId,
                  index: queueIndexRef.current,
                },
              });
            }
            player.loadBrightcoveVideoModel(model);
          } catch (error) {
            const classified = classifyWebPlayerError(error);
            callbacksRef.current.onError?.({
              nativeEvent: classified,
            });
            dispatchCommandError(
              'reload',
              'failed',
              classified.message,
              'reload_failed',
            );
          }
        })
        .catch(err => {
          if (
            disposedRef.current ||
            playerRef.current !== player ||
            queueRequestGenerationRef.current !== requestGeneration
          )
            return;
          queueAbortRef.current = null;
          const classified = classifyWebPlayerError(err);
          callbacksRef.current.onError?.({
            nativeEvent: classified,
          });
          dispatchCommandError(
            'reload',
            'failed',
            classified.message,
            'reload_failed',
          );
        });
    } catch (err) {
      const classified = classifyWebPlayerError(err);
      callbacksRef.current.onError?.({
        nativeEvent: classified,
      });
      dispatchCommandError(
        'reload',
        'failed',
        classified.message,
        'reload_failed',
      );
    }
  }, [resolvedVideoId, dispatchCommandError, resetSourceScopedState]);

  useImperativeHandle(
    ref,
    () => ({
      play: executePlay,
      pause: executePause,
      seekTo: executeSeekTo,
      enterFullscreen: executeEnterFullscreen,
      exitFullscreen: executeExitFullscreen,
      enterPictureInPicture: executeEnterPiP,
      seekToLiveEdge: executeSeekToLiveEdge,
      next: executeNext,
      previous: executePrevious,
      reload: executeReload,
    }),
    [
      executePlay,
      executePause,
      executeSeekTo,
      executeEnterFullscreen,
      executeExitFullscreen,
      executeEnterPiP,
      executeSeekToLiveEdge,
      executeNext,
      executePrevious,
      executeReload,
    ],
  );

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return undefined;

    const generation = ++sourceGenerationRef.current;
    disposedRef.current = false;
    sourceReadyRef.current = false;
    sourceFailedRef.current = false;
    readyEmittedRef.current = false;
    activeVideoIdRef.current = resolvedVideoId;
    // A replaced videoIds prop starts a brand-new queue: the old index is a
    // position inside the previous list and must never leak into
    // onQueueItemChanged/next/previous for the new one.
    queueIndexRef.current = 0;
    queueCompletedEmittedRef.current = false;
    resetSourceScopedState();
    adRequestedRef.current = false;
    daiRequestedRef.current = false;
    firstFrameEmittedRef.current = false;
    chapterRequestIdRef.current =
      playerPropertiesRef.current.chapterSeekRequestId;
    const {
      volume: initialVolume,
      muted: initialMuted,
      playbackRate: initialPlaybackRate,
      loop: initialLoop,
    } = playerPropertiesRef.current;
    let player: WebSdkPlayerInstance | null = null;
    let abortRequest: (() => void) | null = null;
    const isCurrentSource = () =>
      !disposedRef.current &&
      sourceGenerationRef.current === generation &&
      playerRef.current === player;
    const adEventListeners: Array<{
      event: string;
      callback: (eventData?: unknown) => void;
    }> = [];
    let loadDaiStream = () => false;
    // Shared component-level registries so a same-player source swap can flush
    // the previous source's cue-change listeners, not just a full unmount.
    const observedMetadataTracks = observedMetadataTracksRef.current;
    const metadataCleanups = metadataTrackCleanupsRef.current;
    const observedCaptionTracks = observedCaptionTracksRef.current;
    const customCaptionTrackCleanups = captionTrackCleanupsRef.current;
    const flushTrackObservers = () => {
      metadataCleanups.splice(0).forEach(cleanup => cleanup());
      customCaptionTrackCleanups.splice(0).forEach(cleanup => cleanup());
      observedMetadataTracks.clear();
      observedCaptionTracks.clear();
    };
    flushTrackObserversRef.current = flushTrackObservers;

    const emitCustomCaptionCue = (track: WebSdkTextTrack | null) => {
      if (!playerPropertiesRef.current.customCaptionRenderingEnabled) return;
      const activeCues = track
        ? (track as unknown as {
            activeCues?: {
              length: number;
              [index: number]: unknown;
            };
          }).activeCues
        : undefined;
      const cues: WebSdkCaptionCue[] = [];
      for (let index = 0; index < (activeCues?.length ?? 0); index += 1) {
        const rawCue = activeCues?.[index];
        if (!rawCue || typeof rawCue !== 'object') continue;
        const cue = rawCue as Partial<WebSdkCaptionCue>;
        cues.push({
          text: typeof cue.text === 'string' ? cue.text : '',
          startTime:
            typeof cue.startTime === 'number' && Number.isFinite(cue.startTime)
              ? cue.startTime
              : 0,
          endTime:
            typeof cue.endTime === 'number' && Number.isFinite(cue.endTime)
              ? cue.endTime
              : 0,
        });
      }
      const text = cues.map(cue => cue.text).filter(Boolean).join('\n');
      const startTime = cues.length > 0 ? cues[0].startTime : 0;
      const endTime =
        cues.length > 0 ? Math.max(...cues.map(cue => cue.endTime)) : 0;
      const key = `${track?.id ?? ''}|${text}|${startTime}|${endTime}`;
      if (lastCustomCaptionCueKeyRef.current === key) return;
      lastCustomCaptionCueKeyRef.current = key;
      callbacksRef.current.onCaptionCueChanged?.({
        nativeEvent: { text, startTime, endTime },
      });
    };

    const bindCustomCaptionTrack = (track: WebSdkTextTrack) => {
      if (
        !playerPropertiesRef.current.customCaptionRenderingEnabled ||
        track.kind !== 'captions' ||
        !('addEventListener' in track) ||
        observedCaptionTracks.has(track)
      )
        return;
      observedCaptionTracks.add(track);
      const captionTrack = track as unknown as {
        addEventListener: (event: string, callback: () => void) => void;
        removeEventListener?: (event: string, callback: () => void) => void;
      };
      const onCueChange = () => {
        if (!isCurrentSource()) return;
        let selectedTrack: WebSdkTextTrack | null = null;
        try {
          selectedTrack =
            player
              ?.getTextTracks()
              .find(
                candidate =>
                  candidate.kind === 'captions' &&
                  (candidate.mode === 'showing' || candidate.mode === 'hidden'),
              ) ?? null;
        } catch {
          return;
        }
        if (selectedTrack === track) emitCustomCaptionCue(track);
      };
      captionTrack.addEventListener('cuechange', onCueChange);
      customCaptionTrackCleanups.push(() =>
        captionTrack.removeEventListener?.('cuechange', onCueChange),
      );
      emitCustomCaptionCue(track);
    };

    const bindMetadataTrack = (track: unknown, type: 'id3-text' | 'cue-point') => {
      if (!track || observedMetadataTracks.has(track)) return;
      observedMetadataTracks.add(track);
      const t = track as {
        addEventListener?: (event: string, cb: () => void) => void;
        removeEventListener?: (event: string, cb: () => void) => void;
        activeCues?: Array<{
          startTime?: number;
          id?: string;
          text?: string;
          value?: unknown;
          frame?: { id?: string };
        }>;
      };

      const onCueChange = () => {
        if (
          disposedRef.current ||
          sourceGenerationRef.current !== generation ||
          playerRef.current !== player
        )
          return;
        const cues = t.activeCues || [];
        for (let i = 0; i < cues.length; i++) {
          const cue = cues[i];
          const time =
            typeof cue.startTime === 'number'
              ? cue.startTime
              : (player?.getVideoElement()?.currentTime ?? 0);
          if (type === 'id3-text') {
            const key =
              cue.id ||
              (cue.value as { key?: string })?.key ||
              cue.frame?.id ||
              'TXXX';
            const value =
              cue.text ||
              (cue.value as { value?: string })?.value ||
              (typeof cue.value === 'string' ? cue.value : '');
            callbacksRef.current.onTimedMetadata?.({
              nativeEvent: { time, type, data: { key, value } },
            });
          } else {
            const key = 'type';
            const value =
              cue.text ||
              (cue.value as { type?: string })?.type ||
              (typeof cue.value === 'string' ? cue.value : 'point');
            callbacksRef.current.onTimedMetadata?.({
              nativeEvent: { time, type, data: { key, value } },
            });
          }
        }
      };

      if (typeof t.addEventListener === 'function') {
        t.addEventListener('cuechange', onCueChange);
        metadataCleanups.push(() => t.removeEventListener?.('cuechange', onCueChange));
      }
    };

    const emitError = (error: unknown) => {
      if (
        disposedRef.current ||
        sourceGenerationRef.current !== generation ||
        playerRef.current !== player
      )
        return;
      // The web SDK delivers SSAI ad failures on the same PlayerError event
      // as content failures. An ad failing must not fail the content source
      // (the native contract): route ad-class codes to onAdError without
      // latching sourceFailed, and only genuine content failures to onError.
      if (isAdClassWebPlayerError(error)) {
        // Ad-class codes are not content failures, so they never latch
        // sourceFailed. They are classified onto the ad-error contract
        // ('load' | 'playback' | 'unknown'), not the content PlayerErrorCode
        // set, whose values onAdError does not define.
        callbacksRef.current.onAdError?.({
          nativeEvent: classifyWebAdError(error),
        });
        return;
      }
      // A terminal player error fails the current source: commands other
      // than reload are rejected until a new source or reload resets it
      // (the native sourceFailed contract).
      sourceFailedRef.current = true;
      callbacksRef.current.onError?.({
        nativeEvent: classifyWebPlayerError(error),
      });
    };

    const updateLiveState = () => {
      const videoElement = player?.getVideoElement();
      if (!videoElement) return;
      const isLive =
        videoElement.duration === Infinity ||
        (!Number.isFinite(videoElement.duration) && videoElement.duration > 0);
      const ranges = [];
      if (isLive && videoElement.seekable.length > 0) {
        for (let index = 0; index < videoElement.seekable.length; index += 1) {
          ranges.push({
            startTime: videoElement.seekable.start(index),
            endTime: videoElement.seekable.end(index),
          });
        }
      }
      const liveEdge = ranges.length > 0 ? ranges[ranges.length - 1].endTime : 0;
      const hasDvr = isLive && ranges.length > 0 && liveEdge > ranges[0].startTime;
      const rangeKey = `${isLive}|${ranges.map(range => `${range.startTime}:${range.endTime}`).join('|')}`;
      if (lastSeekableRangesKeyRef.current !== rangeKey) {
        lastSeekableRangesKeyRef.current = rangeKey;
        callbacksRef.current.onSeekableRangesChanged?.({
          nativeEvent: { ranges, liveEdge },
        });
      }
      const liveStatusKey = `${isLive}|${hasDvr}`;
      if (lastLiveStatusKeyRef.current !== liveStatusKey) {
        lastLiveStatusKeyRef.current = liveStatusKey;
        callbacksRef.current.onLiveStatus?.({
          nativeEvent: { isLive, hasDvr },
        });
      }
    };

    const handleCanPlay = () => {
      if (
        disposedRef.current ||
        sourceGenerationRef.current !== generation ||
        playerRef.current !== player
      )
        return;
      if (loadDaiStream()) return;
      // Native platforms fire onReady exactly once per source generation
      // (Android's readyEmitted, iOS's _readyEmitted). canplay fires again
      // on every readyState recovery (stall re-buffer, track switch) and on
      // same-player source swaps, so only the first firing per source may
      // emit onReady, run one-shot setup, or re-trigger autoplay — a refire
      // must never resurrect playback after a user pause.
      if (readyEmittedRef.current) {
        // A refire is a readyState recovery on the SAME source. Only the
        // idempotent state refreshes belong here; re-running one-shot setup
        // or autoplay would resurrect playback after a user pause.
        updateLiveState();
        // The rendition ladder can rebuild under the same source (e.g. an
        // SSAI period transition) — an SSAI-ladder rebuild can produce a
        // fresh levels list that no other event re-applies the ceiling to.
        applyPreferredPeakBitrate();
        return;
      }

      readyEmittedRef.current = true;
      sourceReadyRef.current = true;
      // HTML media resets playbackRate to 1 on every new resource, and the
      // rate prop's effect only re-applies on a prop change — a same-player
      // source swap (queue advance, preload handoff, reload) would silently
      // drop the requested rate without this reapply at each source's first
      // canplay.
      {
        const rate = playerPropertiesRef.current.playbackRate;
        if (rate !== undefined && isPlaybackRateValid(rate)) {
          try {
            player?.setPlaybackRate(rate);
          } catch {
            // The rate was already validated by the prop effect; a transient
            // SDK failure here leaves the element's default rate rather than
            // failing the source.
          }
        }
      }
      callbacksRef.current.onReady?.({
        nativeEvent: { videoId: activeVideoIdRef.current },
      });
      updateLiveState();
      applyPreferredPeakBitrate();
      applyAudioDescriptionSelection();
      applyControlsEnabled();
      applySidecarTrack(player);
      performChapterSeek();
      startPreload();
      if (typeof player?.getId3MetadataTrack === 'function') {
        const id3Track = player.getId3MetadataTrack();
        if (id3Track) bindMetadataTrack(id3Track, 'id3-text');
      }
      if (typeof player?.getMediaCuePointsTrack === 'function') {
        const cueTrack = player.getMediaCuePointsTrack();
        if (cueTrack) bindMetadataTrack(cueTrack, 'cue-point');
      }
      handleAudioTracksChanged();
      handleTextTracksChanged();
      if (!autoPlayRef.current) return;
      try {
        const result = player?.play();
        if (isPromiseLike(result)) {
          result.then(
            () => undefined,
            error =>
              dispatchCommandError(
                'play',
                'failed',
                extractErrorMessage(error),
                'autoplay_rejected',
              ),
          );
        }
      } catch (error) {
        dispatchCommandError(
          'play',
          'failed',
          extractErrorMessage(error),
          'autoplay_failed',
        );
      }
    };

    const handlePlayerError = (eventData?: unknown) => {
      if (eventData && typeof eventData === 'object' && 'error' in eventData) {
        emitError((eventData as { error: unknown }).error);
      } else {
        emitError(eventData);
      }
    };

    // playerAudioTracksChanged fires on the SDK's real AudioTrackList
    // 'change'/'addtrack'/'removetrack' events — 'change' is what flips when
    // selectAudioTrack (or the manifest's own DEFAULT=YES track) makes a
    // different track the enabled one, so it doubles as both the "list is
    // now known" and the "active track changed" signal, unlike quality
    // levels (which has no equivalent "this one is now playing" event and
    // needed the video element's 'resize' event instead).
    const handleAudioTracksChanged = () => {
      if (
        disposedRef.current ||
        sourceGenerationRef.current !== generation ||
        playerRef.current !== player
      )
        return;
      let tracks: WebSdkAudioTrack[] = [];
      try {
        tracks = player?.getAudioTracks() ?? [];
      } catch {
        return;
      }
      if (tracks.length === 0) {
        // A source with no audio tracks must still emit the authoritative
        // empty list (same as the captions zero case): a transition from a
        // multi-track source to a zero-track one must clear the app's track
        // list, not keep rendering the previous source's.
        if (lastAudioTracksSignatureRef.current !== null) {
          lastAudioTracksSignatureRef.current = null;
          lastActiveAudioTrackIdRef.current = null;
          defaultAudioTrackIdRef.current = null;
          callbacksRef.current.onAudioTracksAvailable?.({
            nativeEvent: { tracks: [] },
          });
          callbacksRef.current.onAudioTrackChanged?.({
            nativeEvent: { id: '', language: '' },
          });
        }
        return;
      }

      if (defaultAudioTrackIdRef.current === null) {
        const enabledAtStartup = tracks.find(track => track.enabled) ?? tracks[0];
        defaultAudioTrackIdRef.current = enabledAtStartup.id;
      }

      // The underlying AudioTrackList can grow as videojs-http-streaming
      // finishes registering every audio group in the manifest — the same
      // reason native's EVENT_AUDIO_TRACKS_AVAILABLE has no "already
      // emitted" guard either (AudioTracksFeature.kt re-emits every time the
      // list changes, not just once). Re-emitting only when the actual id
      // set changes, rather than on every enabled-flag flip, avoids a
      // redundant event on every selectAudioTrack call.
      const tracksSignature = tracks.map(track => track.id).join('|');
      const listChanged = lastAudioTracksSignatureRef.current !== tracksSignature;
      if (listChanged) {
        lastAudioTracksSignatureRef.current = tracksSignature;
        callbacksRef.current.onAudioTracksAvailable?.({
          nativeEvent: {
            tracks: tracks.map(track => ({
              id: track.id,
              language: track.language,
              label: track.label,
            })),
          },
        });
      }

      const activeTrack = tracks.find(track => track.enabled);
      const activeTrackId = activeTrack?.id ?? '';
      if (lastActiveAudioTrackIdRef.current !== activeTrackId) {
        lastActiveAudioTrackIdRef.current = activeTrackId;
        callbacksRef.current.onAudioTrackChanged?.({
          nativeEvent: {
            id: activeTrackId,
            language: activeTrack?.language ?? '',
          },
        });
      }

      const descAvailable = tracks.some(isDescriptiveTrack);
      const descEnabled = tracks.some(t => t.enabled && isDescriptiveTrack(t));
      const adAvailabilityKey = `${activeVideoIdRef.current}:${descAvailable}`;
      if (lastAdAvailabilityKeyRef.current !== adAvailabilityKey) {
        lastAdAvailabilityKeyRef.current = adAvailabilityKey;
        callbacksRef.current.onAudioDescriptionAvailable?.({
          nativeEvent: {
            videoId: activeVideoIdRef.current,
            available: descAvailable,
          },
        });
      }
      const adStateKey = `${activeVideoIdRef.current}:${descEnabled}:${descAvailable}`;
      if (lastAdStateKeyRef.current !== adStateKey) {
        lastAdStateKeyRef.current = adStateKey;
        callbacksRef.current.onAudioDescriptionChanged?.({
          nativeEvent: {
            videoId: activeVideoIdRef.current,
            enabled: descEnabled,
            available: descAvailable,
          },
        });
      }

      // Only reassert the prop-driven selection when the list itself just
      // became known or grew — never on every playerAudioTracksChanged
      // firing, or a selection just made through the SDK's own native
      // control-bar audio-track menu would be immediately reverted: that
      // menu sets enabled directly on the real AudioTrackList, firing this
      // same 'change' event, before React ever gets a chance to re-render
      // with a correspondingly updated audioTrackId prop (confirmed live —
      // the exact bug this guard fixes). A prop change reapplies through
      // its own dedicated effect below, independent of this handler.
      if (listChanged) {
        applyAudioTrackSelection();
      }
    };

    // playerTextTracksChanged fires on the SDK's real TextTrackList
    // 'change'/'addtrack'/'removetrack' events. 'change' flips whenever
    // applyCaptionSelection (or a customer's own mode mutation) makes a
    // different track 'showing', so — like audio tracks — this one event
    // doubles as both "the caption list is now known" and "the active track
    // changed" signal.
    const handleTextTracksChanged = () => {
      if (
        disposedRef.current ||
        sourceGenerationRef.current !== generation ||
        playerRef.current !== player
      )
        return;
      let allTracks: WebSdkTextTrack[] = [];
      try {
        allTracks = player?.getTextTracks() ?? [];
      } catch {
        return;
      }
      // A native track can flip 'showing' again at any time (e.g. through
      // the SDK's own control-bar caption menu, which lists these too), so
      // this always runs, independent of whether the kind:'captions'
      // selection below is reasserted.
      disableNativeSubtitleTracks(allTracks);

      // Only kind 'captions' tracks are addressable — see
      // applyCaptionSelection for why native kind:'subtitles' tracks (a
      // manifest's HLS SUBTITLES groups, auto-registered a second time by
      // videojs-http-streaming) are excluded here too: reporting them would
      // advertise ids onCaptionTrackChanged's own selection logic can never
      // select by (they're label-keyed, not the Playback API's stable ids).
      const tracks = allTracks.filter(track => track.kind === 'captions');
      const customRendering =
        playerPropertiesRef.current.customCaptionRenderingEnabled;
      if (customRendering) {
        tracks.forEach(bindCustomCaptionTrack);
      }
      if (tracks.length === 0) {
        if (customRendering) emitCustomCaptionCue(null);
        // A source with no caption tracks must still emit the authoritative
        // empty list — native platforms reset tracks to [] on every source
        // change, so an app must never keep rendering the previous source's
        // track list.
        if (lastCaptionsSignatureRef.current !== null) {
          lastCaptionsSignatureRef.current = null;
          lastActiveCaptionTrackIdRef.current = '';
          callbacksRef.current.onCaptionsAvailable?.({
            nativeEvent: { tracks: [] },
          });
          callbacksRef.current.onCaptionTrackChanged?.({
            nativeEvent: { id: '', language: '' },
          });
        }
        return;
      }

      // The underlying TextTrackList can grow as sidecar tracks or
      // additional manifest groups finish registering — the same reason
      // audio tracks re-emit on every list change rather than once.
      const tracksSignature = tracks.map(track => track.id).join('|');
      const listChanged = lastCaptionsSignatureRef.current !== tracksSignature;
      if (listChanged) {
        lastCaptionsSignatureRef.current = tracksSignature;
        callbacksRef.current.onCaptionsAvailable?.({
          nativeEvent: {
            tracks: tracks.map(track => ({
              id: track.id,
              language: track.language,
              label: track.label,
            })),
          },
        });
      }

      const activeTrack = tracks.find(
        track =>
          track.mode === 'showing' || (customRendering && track.mode === 'hidden'),
      );
      const activeTrackId = activeTrack?.id ?? '';
      if (lastActiveCaptionTrackIdRef.current !== activeTrackId) {
        lastActiveCaptionTrackIdRef.current = activeTrackId;
        callbacksRef.current.onCaptionTrackChanged?.({
          nativeEvent: {
            id: activeTrackId,
            language: activeTrack?.language ?? '',
          },
        });
      }
      if (customRendering) emitCustomCaptionCue(activeTrack ?? null);

      if (typeof player?.getId3MetadataTrack === 'function') {
        const id3Track = player.getId3MetadataTrack();
        if (id3Track) bindMetadataTrack(id3Track, 'id3-text');
      }
      if (typeof player?.getMediaCuePointsTrack === 'function') {
        const cueTrack = player.getMediaCuePointsTrack();
        if (cueTrack) bindMetadataTrack(cueTrack, 'cue-point');
      }
      try {
        const metaTracks = (player?.getTextTracks() ?? []).filter(
          t => t.kind === 'metadata',
        );
        metaTracks.forEach(t => {
          const isId3 = Boolean((t as { inBandMetadataTrackDispatchType?: unknown }).inBandMetadataTrackDispatchType || t.label === 'id3');
          bindMetadataTrack(t, isId3 ? 'id3-text' : 'cue-point');
        });
      } catch {
        // ignore
      }

      const configuredTracks = playerPropertiesRef.current.sidecarTracks;
      if (configuredTracks && configuredTracks.length > 0) {
        const match = configuredTracks.find(track => {
          const lang = track?.language?.toLowerCase();
          return (
            lang &&
            activeTrack &&
            activeTrack.mode === 'showing' &&
            (activeTrack.id === 'sidecar-' + track.language ||
              activeTrack.language.toLowerCase() === lang)
          );
        });
        if (match) {
          if (!sidecarSelectedEmittedRef.current) {
            sidecarSelectedEmittedRef.current = true;
            callbacksRef.current.onSidecarTrackStatus?.({
              nativeEvent: {
                status: 'selected',
                language: match.language,
                label: match.label || match.language,
                error: '',
                nativeCode: '',
              },
            });
          }
        } else {
          sidecarSelectedEmittedRef.current = false;
        }
      }

      // Only reassert the prop-driven selection when the list itself just
      // became known or grew — never on every playerTextTracksChanged
      // firing, or a selection just made through the SDK's own native
      // control-bar caption menu would be immediately reverted: that menu
      // sets mode directly on the real TextTrackList, firing this same
      // 'change' event, before React ever gets a chance to re-render with
      // correspondingly updated captionsEnabled/captionTrackId props
      // (confirmed live — the exact bug this guard fixes). A prop change
      // reapplies through its own dedicated effect below, independent of
      // this handler.
      if (listChanged) {
        applyCaptionSelection();
      }
    };

    let videoElementListenersCleanup: (() => void) | null = null;

    const cleanup = () => {
      disposedRef.current = true;
      sourceReadyRef.current = false;
      sourceFailedRef.current = false;
      sourceGenerationRef.current += 1;
      preloadGenerationRef.current += 1;
      preloadAbortRef.current?.();
      preloadAbortRef.current = null;
      queueRequestGenerationRef.current += 1;
      queueAbortRef.current?.();
      queueAbortRef.current = null;
      hasPlayedRef.current = false;
      seekingRef.current = false;
      if (rebufferingRef.current) {
        rebufferingRef.current = false;
        callbacksRef.current.onRebufferEnd?.({ nativeEvent: null });
      }
      pendingChapterSeekRef.current = null;
      // Authoritative per-source resets — the same shape the queue-advance
      // path emits in loadVideoIndex. On a videoId change the whole player is
      // disposed below, so these fire here instead; without them a new source
      // with no caption/audio tracks keeps the old lists (and a controlled
      // captionTrackId/audioTrackId) stuck forever.
      callbacksRef.current.onAudioTracksAvailable?.({ nativeEvent: { tracks: [] } });
      callbacksRef.current.onAudioTrackChanged?.({
        nativeEvent: { id: '', language: '' },
      });
      callbacksRef.current.onCaptionsAvailable?.({ nativeEvent: { tracks: [] } });
      callbacksRef.current.onCaptionTrackChanged?.({
        nativeEvent: { id: '', language: '' },
      });
      flushTrackObservers();
      flushTrackObserversRef.current = null;
      if (playerPropertiesRef.current.customCaptionRenderingEnabled) {
        lastCustomCaptionCueKeyRef.current = null;
        callbacksRef.current.onCaptionCueChanged?.({
          nativeEvent: { text: '', startTime: 0, endTime: 0 },
        });
      }
      callbacksRef.current.onLiveStatus?.({
        nativeEvent: { isLive: false, hasDvr: false },
      });
      lastLiveStatusKeyRef.current = null;
      if (
        lastAdAvailabilityKeyRef.current !== null ||
        lastAdStateKeyRef.current !== null
      ) {
        lastAdAvailabilityKeyRef.current = null;
        lastAdStateKeyRef.current = null;
        previousNonDescriptiveTrackIdRef.current = null;
        callbacksRef.current.onAudioDescriptionAvailable?.({
          nativeEvent: { videoId: '', available: false },
        });
        callbacksRef.current.onAudioDescriptionChanged?.({
          nativeEvent: { videoId: '', enabled: false, available: false },
        });
      }
      const hadSidecarTracks = sidecarConfiguredRef.current;
      sidecarConfiguredRef.current = false;
      sidecarValidatedRef.current = null;
      if (hadSidecarTracks) {
        sidecarSelectedEmittedRef.current = false;
        callbacksRef.current.onSidecarTrackStatus?.({
          nativeEvent: {
            status: 'reset',
            language: '',
            label: '',
            error: '',
            nativeCode: '',
          },
        });
      }
      abortRequest?.();
      abortRequest = null;
      videoElementListenersCleanup?.();
      videoElementListenersCleanup = null;
      if (!player) return;
      player.removeEventListener(PLAYER_CAN_PLAY_EVENT, handleCanPlay);
      player.removeEventListener(PLAYER_ERROR_EVENT, handlePlayerError);
      player.removeEventListener(
        PLAYER_AUDIO_TRACKS_CHANGED_EVENT,
        handleAudioTracksChanged,
      );
      player.removeEventListener(
        PLAYER_TEXT_TRACKS_CHANGED_EVENT,
        handleTextTracksChanged,
      );
      adEventListeners.forEach(({ event, callback }) => {
        player?.removeEventListener(event, callback);
      });
      try {
        player.detach();
      } catch (error) {
        console.error('[BrightcoveWebPlayer] Failed to detach player', error);
      }
      try {
        player.dispose();
      } catch (error) {
        console.error('[BrightcoveWebPlayer] Failed to dispose player', error);
      }
      if (playerRef.current === player) playerRef.current = null;
    };

    if (!accountId.trim()) {
      callbacksRef.current.onError?.({
        nativeEvent: {
          code: 'invalid_configuration',
          message: 'accountId is required',
          nativeCode: 'missing_account_id',
        },
      });
      return cleanup;
    }
    if (!policyKey.trim()) {
      callbacksRef.current.onError?.({
        nativeEvent: {
          code: 'invalid_configuration',
          message: 'policyKey is required',
          nativeCode: 'missing_policy_key',
        },
      });
      return cleanup;
    }
    if (!resolvedVideoId.trim()) {
      callbacksRef.current.onError?.({
        nativeEvent: {
          code: 'invalid_configuration',
          message: 'videoId or videoIds is required',
          nativeCode: 'missing_video_id',
        },
      });
      return cleanup;
    }

    callbacksRef.current.onSourceLoading?.({
      nativeEvent: { videoId: resolvedVideoId },
    });

    try {
      player = playerFactory({
        accountId,
        enableThumbnails: thumbnailSeekingEnabledRef.current,
        enableAds: Boolean(playerPropertiesRef.current.adTagUrl?.trim()),
        enableSsai: Boolean(playerPropertiesRef.current.adConfigId?.trim()),
        enableDai: Boolean(
          playerPropertiesRef.current.daiSourceId?.trim() &&
            playerPropertiesRef.current.daiVideoId?.trim(),
        ),
      });
      playerRef.current = player;
      player.updateConfiguration({
        brightcove: {
          policyKey,
          adConfigId: playerPropertiesRef.current.adConfigId?.trim() || null,
        },
        ui: {
          language: 'en',
          playsinline: true,
          // Restricts the control bar to only the buttons this sample's
          // installed features actually back — the SDK's own default is
          // every button in DefaultControlBarComponents, unconditionally,
          // since one shared Player implementation serves every sample.
          // Falls back to the SDK's own default (every button) when a
          // sample was assembled before this generation, so an un-regenerated
          // bridge copy still compiles and runs, just without the narrowing.
          ...(webControlBarComponents
            ? { defaultControlBarComponents: webControlBarComponents }
            : {}),
        },
        integrations: thumbnailSeekingEnabledRef.current
          ? {
              thumbnails: {},
                  ...(playerPropertiesRef.current.adTagUrl?.trim()
                ? {
                    imaClientSide: {
                      serverUrl: playerPropertiesRef.current.adTagUrl,
                      requestMode: 'ondemand',
                      hardTimeouts: true,
                      showVpaidControls: false,
                      useMediaCuePoints: false,
                    },
                  }
                : {}),
              ...(playerPropertiesRef.current.adConfigId?.trim()
                ? { ssai: {} }
                : {}),
              ...(playerPropertiesRef.current.daiSourceId?.trim() &&
              playerPropertiesRef.current.daiVideoId?.trim()
                ? { imaDai: {} }
                : {}),
            }
          : {
              ...(playerPropertiesRef.current.adTagUrl?.trim()
                ? {
                    imaClientSide: {
                      serverUrl: playerPropertiesRef.current.adTagUrl,
                      requestMode: 'ondemand',
                      hardTimeouts: true,
                      showVpaidControls: false,
                      useMediaCuePoints: false,
                    },
                  }
                : {}),
              ...(playerPropertiesRef.current.adConfigId?.trim()
                ? { ssai: {} }
                : {}),
              ...(playerPropertiesRef.current.daiSourceId?.trim() &&
              playerPropertiesRef.current.daiVideoId?.trim()
                ? { imaDai: {} }
                : {}),
            },
      });
      player.attach(container);
      let requestAdsOnPlay: (() => void) | null = null;
      const adIntegration = player.getIntegrationsManager?.()
        .imaClientSideIntegration;
      const daiIntegration = player.getIntegrationsManager?.()
        .imaDaiIntegration;
      if (
        daiIntegration &&
        playerPropertiesRef.current.daiSourceId?.trim() &&
        playerPropertiesRef.current.daiVideoId?.trim()
      ) {
        loadDaiStream = () => {
          if (daiRequestedRef.current) return false;
          const fallbackSource = player?.getCurrentSource?.();
          if (!fallbackSource) return false;
          const daiApi = (
            globalThis as unknown as {
              google?: { ima?: { dai?: { api?: WebSdkDaiRuntimeApi } } };
            }
          ).google?.ima?.dai?.api;
          if (!daiApi) return false;
          const streamRequest = new daiApi.VodStreamRequest();
          streamRequest.contentSourceId = playerPropertiesRef.current.daiSourceId;
          streamRequest.videoId = playerPropertiesRef.current.daiVideoId;
          daiRequestedRef.current = true;
          daiIntegration.load({
            streamRequest,
            fallbackSource,
          });
          return true;
        };
        const retryDaiAfterSdkLoad = () => {
          loadDaiStream();
        };
        player.addEventListener('imaDaiSdkLoaded', retryDaiAfterSdkLoad);
        adEventListeners.push({
          event: 'imaDaiSdkLoaded',
          callback: retryDaiAfterSdkLoad,
        });
      }
      if (adIntegration && playerPropertiesRef.current.adTagUrl?.trim()) {
        requestAdsOnPlay = () => {
          const tag = playerPropertiesRef.current.adTagUrl?.trim();
          if (!tag || adRequestedRef.current) return;
          adRequestedRef.current = true;
          adIntegration.requestAd(tag);
        };
        const getAd = () => adIntegration.getCurrentAd();
        const getAdId = () => getAd()?.getAdId() || '';
        const getAdPayload = (): AdEventData => {
          const ad = getAd();
          return {
            adTitle: ad?.getTitle() || '',
            duration: ad?.getDuration() || 0,
          };
        };
        const getAdMetadata = (): AdMetadataEventData | null => {
          const ad = getAd();
          if (!ad) return null;
          return {
            adId: ad.getAdId(),
            adTitle: ad.getTitle() || '',
            advertiserName: ad.getAdvertiserName() || '',
            durationSeconds: ad.getDuration() || 0,
            isLinear: ad.isLinear(),
            width: ad.getWidth() || 0,
            height: ad.getHeight() || 0,
            isSkippable: ad.getSkipTimeOffset() >= 0,
            skipTimeOffsetSeconds: ad.getSkipTimeOffset() || 0,
          };
        };
        const addAdListener = (
          event: string,
          callback: (eventData?: unknown) => void,
        ) => {
          player?.addEventListener(event, callback);
          adEventListeners.push({ event, callback });
        };
        addAdListener('imaClientSideAdsPodStarted', () => {
          callbacksRef.current.onAdBreakStarted?.({
            nativeEvent: { index: -1 },
          });
        });
        addAdListener('imaClientSideAdsPodEnded', () => {
          callbacksRef.current.onAdBreakEnded?.({
            nativeEvent: { index: -1 },
          });
        });
        addAdListener('imaClientSideAdStarted', () => {
          callbacksRef.current.onAdStarted?.({
            nativeEvent: getAdPayload(),
          });
          const metadata = getAdMetadata();
          if (metadata) {
            callbacksRef.current.onAdMetadata?.({ nativeEvent: metadata });
          }
          // A non-linear (overlay) ad became visible: the same
          // onAdOverlayStateChanged surface the native CSAI features emit.
          const ad = getAd();
          if (ad && !ad.isLinear()) {
            callbacksRef.current.onAdOverlayStateChanged?.({
              nativeEvent: { adId: ad.getAdId(), visible: true },
            });
          }
        });
        addAdListener('imaClientSideAdComplete', () => {
          callbacksRef.current.onAdCompleted?.({
            nativeEvent: getAdPayload(),
          });
          const ad = getAd();
          if (ad && !ad.isLinear()) {
            callbacksRef.current.onAdOverlayStateChanged?.({
              nativeEvent: { adId: ad.getAdId(), visible: false },
            });
          }
        });
        addAdListener('imaClientSideAllAdsCompleted', () => {
          callbacksRef.current.onAllAdsCompleted?.({
            nativeEvent: { completed: true },
          });
        });
        addAdListener('imaClientSidePaused', () => {
          const adId = getAdId();
          if (adId) callbacksRef.current.onAdPaused?.({ nativeEvent: { adId } });
        });
        addAdListener('imaClientSideResumed', () => {
          const adId = getAdId();
          if (adId) callbacksRef.current.onAdResumed?.({ nativeEvent: { adId } });
        });
        addAdListener('imaClientSideSkipped', () => {
          const adId = getAdId();
          if (adId) callbacksRef.current.onAdSkipped?.({ nativeEvent: { adId } });
        });
        addAdListener('imaClientSideFirstQuartile', () => {
          const adId = getAdId();
          if (adId) callbacksRef.current.onAdQuartile?.({ nativeEvent: { adId, quartile: 25 } });
        });
        addAdListener('imaClientSideMidPoint', () => {
          const adId = getAdId();
          if (adId) callbacksRef.current.onAdQuartile?.({ nativeEvent: { adId, quartile: 50 } });
        });
        addAdListener('imaClientSideThirdQuartile', () => {
          const adId = getAdId();
          if (adId) callbacksRef.current.onAdQuartile?.({ nativeEvent: { adId, quartile: 75 } });
        });
        addAdListener('imaClientSideAdClick', () => {
          const adId = getAdId();
          if (adId) callbacksRef.current.onAdInteraction?.({ nativeEvent: { adId, interaction: 'clicked' } });
        });
        addAdListener('imaClientSideAdError', eventData => {
          callbacksRef.current.onAdError?.({
            nativeEvent: classifyImaClientSideAdError(eventData),
          });
        });
      }
      let updateSsaiTimeline = () => {};
      const ssaiIntegration = player.getIntegrationsManager?.()
        .ssaiIntegration;
      if (ssaiIntegration && playerPropertiesRef.current.adConfigId?.trim()) {
        let previousAd: WebSdkSsaiAd | null = null;
        let previousAdKey: string | null = null;
        updateSsaiTimeline = () => {
          const state = ssaiIntegration.getRelativeTimelineState();
          const ad = state?.linearAd || null;
          const adKey = ad
            ? `${ad.absoluteStartTime()}|${ad.absoluteEndTime()}|${ad.adTitle()}`
            : null;
          if (adKey === previousAdKey) return;

          if (previousAd) {
            callbacksRef.current.onAdCompleted?.({
              nativeEvent: {
                adTitle: previousAd.adTitle() || '',
                duration: previousAd.duration() || 0,
              },
            });
          }
          if (ad) {
            if (!previousAd) {
              callbacksRef.current.onAdBreakStarted?.({
                nativeEvent: {
                  // The shared contract reserves index for a stable break
                  // position and requires -1 when the source does not
                  // surface one; the SSAI roll's positional indexOf is not
                  // the video's break index, so it must not leak here.
                  index: -1,
                },
              });
            }
            callbacksRef.current.onAdStarted?.({
              nativeEvent: {
                adTitle: ad.adTitle() || '',
                duration: ad.duration() || 0,
              },
            });
          } else if (previousAd) {
            callbacksRef.current.onAdBreakEnded?.({
              nativeEvent: { index: -1 },
            });
          }
          previousAd = ad;
          previousAdKey = adKey;
        };
      }
      const videoEl = player.getVideoElement();
      if (videoEl) {
        // `videoScalingMode` is the cross-platform resize contract. The native
        // bridges map fit/fill to their SDK scaling modes; on web the equivalent
        // is object-fit contain/cover on the actual media element.
        videoEl.style.objectFit =
          playerPropertiesRef.current.videoScalingMode === 'fill'
            ? 'cover'
            : 'contain';
        // The first queue item honors repeatMode "one" the same way
        // loadVideoIndex applies it to every later item; the standalone loop
        // prop keeps its own scope (see the loop/repeatMode effects).
        if (initialLoop || playerPropertiesRef.current.repeatMode === 'one') {
          videoEl.loop = true;
        }
        const finishRebuffer = () => {
          if (!rebufferingRef.current) return;
          rebufferingRef.current = false;
          callbacksRef.current.onRebufferEnd?.({ nativeEvent: null });
        };
        const onPlayNative = () => {
          requestAdsOnPlay?.();
          callbacksRef.current.onPlay?.({ nativeEvent: null });
        };
        const onPlayingNative = () => {
          if (!isCurrentSource()) return;
          hasPlayedRef.current = true;
          finishRebuffer();
        };
        const onWaitingNative = () => {
          if (!isCurrentSource()) return;
          if (
            hasPlayedRef.current &&
            !seekingRef.current &&
            !rebufferingRef.current
          ) {
            rebufferingRef.current = true;
            callbacksRef.current.onRebufferStart?.({ nativeEvent: null });
          }
        };
        const onAdProgressNative = () => {
          if (!adIntegration || !container.querySelector('.vjs-ad-playing')) return;
          const ad = adIntegration.getCurrentAd();
          const adId = ad?.getAdId() || '';
          if (!adId) return;
          callbacksRef.current.onAdProgress?.({
            nativeEvent: {
              adId,
              positionSeconds: videoEl.currentTime,
              durationSeconds: ad?.getDuration() || 0,
            },
          });
        };
        const onSeekingNative = () => {
          if (!isCurrentSource()) return;
          const wasSeeking = seekingRef.current;
          seekingRef.current = true;
          finishRebuffer();
          if (!wasSeeking) {
            callbacksRef.current.onSeekStarted?.({
              nativeEvent: {
                requestedPositionSeconds: videoEl.currentTime,
              },
            });
          }
        };
        const onSeekedNative = () => {
          if (!isCurrentSource()) return;
          seekingRef.current = false;
          const pending = pendingChapterSeekRef.current;
          if (pending) {
            callbacksRef.current.onChapterSeekCompleted?.({
              nativeEvent: {
                requestId: pending.requestId,
                positionSeconds: videoEl.currentTime,
                completed: Math.abs(videoEl.currentTime - pending.target) <= 1,
              },
            });
          }
          callbacksRef.current.onSeekCompleted?.({
            nativeEvent: {
              positionSeconds: videoEl.currentTime,
              completed: true,
            },
          });
          pendingChapterSeekRef.current = null;
        };
        const onPauseNative = () => {
          if (!isCurrentSource()) return;
          hasPlayedRef.current = false;
          finishRebuffer();
          callbacksRef.current.onPause?.({ nativeEvent: null });
        };
        const onEndedNative = () => {
          if (!isCurrentSource()) return;
          hasPlayedRef.current = false;
          finishRebuffer();
          callbacksRef.current.onEnded?.({ nativeEvent: null });
          const preloadedModel = preloadedModelRef.current;
          const preloadedVideoId = preloadedVideoIdRef.current;
          if (preloadedModel && preloadedVideoId) {
            if (!player || disposedRef.current) return;
            const previousVideoId =
              preloadSourceVideoIdRef.current || activeVideoIdRef.current;
            preloadedModelRef.current = null;
            preloadedVideoIdRef.current = null;
            preloadSourceVideoIdRef.current = null;
            preloadAbortRef.current = null;
            sourceReadyRef.current = false;
            sourceFailedRef.current = false;
            activeVideoIdRef.current = preloadedVideoId;
            // The preload handoff swaps the source on the same player
            // instance — reset the per-source latches so the new item
            // reports its own first frame and requests its own ads.
            adRequestedRef.current = false;
            daiRequestedRef.current = false;
            firstFrameEmittedRef.current = false;
            readyEmittedRef.current = false;
            resetSourceScopedState();
            // The handed-off source is outside the videoIds queue: the old
            // queue index and its once-per-queue completion latch must not
            // leak into the new source's own `ended` (a post-handoff end must
            // not fire onQueueCompleted, and a later re-mount of the queue
            // starts from item 0 re-armed, like the videoIds-change reset).
            queueIndexRef.current = 0;
            queueCompletedEmittedRef.current = false;
            try {
              player.loadBrightcoveVideoModel(preloadedModel);
              callbacksRef.current.onPreloadHandoff?.({
                nativeEvent: {
                  previousVideoId,
                  currentVideoId: preloadedVideoId,
                },
              });
            } catch (error) {
              callbacksRef.current.onPreloadError?.({
                nativeEvent: {
                  videoId: preloadedVideoId,
                  code: 'playback',
                  message: extractErrorMessage(error),
                  nativeCode: 'preload_handoff_failed',
                },
              });
            }
            return;
          }
          const currentVideoIds = videoIdsRef.current;
          // A handed-off preload source is not a queue item: its `ended` must
          // not advance or complete the videoIds queue. The queue index is
          // reset to 0 at handoff, so gate on the active video belonging to
          // the queue rather than on the index alone.
          const activeIsQueueItem =
            currentVideoIds != null &&
            currentVideoIds.includes(activeVideoIdRef.current);
          if (currentVideoIds && currentVideoIds.length > 0 && activeIsQueueItem) {
            const nextIdx = queueIndexRef.current + 1;
            if (nextIdx < currentVideoIds.length) {
              loadVideoIndex(nextIdx);
            } else if (repeatModeRef.current === 'all') {
              // Wrapping never completes the queue, matching native
              // repeat-all: item 0 follows the last item's natural end.
              loadVideoIndex(0);
            } else if (!queueCompletedEmittedRef.current) {
              // Natural completion at the last item: exactly once per loaded
              // queue. A second `ended` (e.g. a re-dispatched event after the
              // element resets) must not fire the callback again.
              queueCompletedEmittedRef.current = true;
              callbacksRef.current.onQueueCompleted?.({ nativeEvent: null });
            }
          }
        };
        const onTimeUpdateNative = () => {
          if (!isCurrentSource()) return;
          updateLiveState();
          updateSsaiTimeline();
          callbacksRef.current.onProgress?.({
            nativeEvent: {
              currentTime: videoEl.currentTime,
              // A live stream reports duration Infinity; the contract carries a
              // finite Double, so report 0 when the duration is not finite
              // (matching Android's coerce/normalize and iOS's numeric guard).
              duration: Number.isFinite(videoEl.duration) ? videoEl.duration : 0,
            },
          });
        };
        const emitDurationChanged = () => {
          const duration = videoEl.duration;
          if (
            !Number.isFinite(duration) ||
            duration < 0 ||
            lastLifecycleDurationRef.current === duration
          ) {
            return;
          }
          lastLifecycleDurationRef.current = duration;
          callbacksRef.current.onDurationChanged?.({
            nativeEvent: { durationSeconds: duration },
          });
        };
        const emitVideoSizeChanged = () => {
          const { videoWidth: width, videoHeight: height } = videoEl;
          if (!width || !height) return;
          const previous = lastLifecycleVideoSizeRef.current;
          if (previous?.width === width && previous?.height === height) return;
          lastLifecycleVideoSizeRef.current = { width, height };
          callbacksRef.current.onVideoSizeChanged?.({
            nativeEvent: { width, height },
          });
        };
        const onLoadedMetadataNative = () => {
          if (!isCurrentSource()) return;
          emitDurationChanged();
          emitVideoSizeChanged();
        };
        const onDurationChangeNative = () => {
          if (!isCurrentSource()) return;
          emitDurationChanged();
        };
        const onLoadedDataNative = () => {
          if (!isCurrentSource()) return;
          if (firstFrameEmittedRef.current) return;
          firstFrameEmittedRef.current = true;
          callbacksRef.current.onFirstFrame?.({
            nativeEvent: { videoId: activeVideoIdRef.current },
          });
          emitVideoSizeChanged();
        };
        const onEnterPiPNative = () => {
          callbacksRef.current.onPictureInPictureModeChanged?.({
            nativeEvent: { active: true },
          });
        };
        const onLeavePiPNative = () => {
          callbacksRef.current.onPictureInPictureModeChanged?.({
            nativeEvent: { active: false },
          });
        };
        // Safari reports PiP only through the prefixed presentation-mode
        // event; the mode string replaces the standard enter/leave pair.
        const onWebkitPresentationModeChanged = () => {
          const mode = (videoEl as VideoElementWithWebkitPresentationMode)
            .presentationMode;
          callbacksRef.current.onPictureInPictureModeChanged?.({
            nativeEvent: { active: mode === 'picture-in-picture' },
          });
        };
        // 'resize' fires on the tech whenever the real video element's
        // decoded videoWidth/videoHeight change — the same signal iOS reads
        // via AVPlayerItem's presentationSize KVO and Android reads via
        // ExoPlayer's RENDITION_CHANGED. It is the actual currently-playing
        // rendition, distinct from getQualityLevels()' enabled flags (which
        // only restrict which levels the adaptive selector may choose among).
        const onResizeNative = () => {
          if (!isCurrentSource() || !sourceReadyRef.current) return;
          emitVideoSizeChanged();
          const width = videoEl.videoWidth;
          const height = videoEl.videoHeight;
          if (!width || !height) return;
          const currentPlayer = playerRef.current;
          let bitrate = 0;
          let frameRate = 0;
          let matchedLevelId: string | undefined;
          try {
            const matchedLevel = currentPlayer
              ?.getQualityLevels()
              .find(level => level.width === width && level.height === height);
            bitrate = matchedLevel?.bitrate ?? 0;
            frameRate = matchedLevel?.frameRate ?? 0;
            matchedLevelId = matchedLevel?.id;
          } catch {
            // ignore: rendition reporting is best-effort telemetry.
          }
          const renditionKey = `${activeVideoIdRef.current}|${bitrate}|${width}|${height}|${frameRate}`;
          if (lastRenditionKeyRef.current === renditionKey) return;
          lastRenditionKeyRef.current = renditionKey;
          // frameRate participates in the dedupe key (a browser rendition
          // change with identical bitrate/size but a different frame rate is
          // still a new rendition) but is not part of the shared contract's
          // payload: the native SDK rendition model does not expose it. The
          // web has no stable rendition/source identifiers, so the contract's
          // id fields carry the closest honest values (sourceId names the
          // active source's video, renditionId names the matched level).
          const sourceId = activeVideoIdRef.current;
          const renditionId = matchedLevelId ?? `${width}x${height}`;
          callbacksRef.current.onRenditionChanged?.({
            nativeEvent: {
              sourceId,
              videoId: activeVideoIdRef.current,
              renditionId,
              bitrate,
              width,
              height,
            },
          });
        };

        videoEl.addEventListener('play', onPlayNative);
        videoEl.addEventListener('playing', onPlayingNative);
        videoEl.addEventListener('pause', onPauseNative);
        videoEl.addEventListener('waiting', onWaitingNative);
        if (adIntegration) videoEl.addEventListener('timeupdate', onAdProgressNative);
        videoEl.addEventListener('seeking', onSeekingNative);
        videoEl.addEventListener('seeked', onSeekedNative);
        videoEl.addEventListener('loadedmetadata', onLoadedMetadataNative);
        videoEl.addEventListener('durationchange', onDurationChangeNative);
        videoEl.addEventListener('loadeddata', onLoadedDataNative);
        videoEl.addEventListener('ended', onEndedNative);
        videoEl.addEventListener('timeupdate', onTimeUpdateNative);
        videoEl.addEventListener('enterpictureinpicture', onEnterPiPNative);
        videoEl.addEventListener('leavepictureinpicture', onLeavePiPNative);
        videoEl.addEventListener(
          'webkitpresentationmodechanged',
          onWebkitPresentationModeChanged,
        );
        videoEl.addEventListener('resize', onResizeNative);

        const onFullscreenChangeNative = () => {
          if (typeof document !== 'undefined') {
            // video.js fullscreens its own child player div rather than the
            // container or the video element, so a contained fullscreen
            // element must count as active too — while an unrelated
            // document-level fullscreen element (outside this player) must
            // not. Safari reports the element through the prefixed getter.
            const fullscreenElement =
              document.fullscreenElement ??
              (document as DocumentWithWebkitFullscreen).webkitFullscreenElement ??
              null;
            const isFs =
              fullscreenElement === container ||
              fullscreenElement === videoEl ||
              (fullscreenElement !== null && container.contains(fullscreenElement));
            if (lastFullscreenActiveRef.current === isFs) return;
            lastFullscreenActiveRef.current = isFs;
            callbacksRef.current.onFullscreenChanged?.({
              nativeEvent: { active: isFs },
            });
          }
        };
        if (typeof document !== 'undefined') {
          document.addEventListener('fullscreenchange', onFullscreenChangeNative);
          document.addEventListener(
            'webkitfullscreenchange',
            onFullscreenChangeNative as EventListener,
          );
        }

        videoElementListenersCleanup = () => {
          videoEl.removeEventListener('play', onPlayNative);
          videoEl.removeEventListener('playing', onPlayingNative);
          videoEl.removeEventListener('pause', onPauseNative);
          videoEl.removeEventListener('waiting', onWaitingNative);
          if (adIntegration) videoEl.removeEventListener('timeupdate', onAdProgressNative);
          videoEl.removeEventListener('seeking', onSeekingNative);
          videoEl.removeEventListener('seeked', onSeekedNative);
          videoEl.removeEventListener('loadedmetadata', onLoadedMetadataNative);
          videoEl.removeEventListener('durationchange', onDurationChangeNative);
          videoEl.removeEventListener('loadeddata', onLoadedDataNative);
          videoEl.removeEventListener('ended', onEndedNative);
          videoEl.removeEventListener('timeupdate', onTimeUpdateNative);
          videoEl.removeEventListener('enterpictureinpicture', onEnterPiPNative);
          videoEl.removeEventListener('leavepictureinpicture', onLeavePiPNative);
          videoEl.removeEventListener(
            'webkitpresentationmodechanged',
            onWebkitPresentationModeChanged,
          );
          videoEl.removeEventListener('resize', onResizeNative);
          if (typeof document !== 'undefined') {
            document.removeEventListener('fullscreenchange', onFullscreenChangeNative);
            document.removeEventListener(
              'webkitfullscreenchange',
              onFullscreenChangeNative as EventListener,
            );
          }
        };
      }

      if (initialVolume !== undefined) {
        const normalizedVolume = normalizeVolume(initialVolume);
        if (normalizedVolume !== null) {
          updateVideoVolume(player, normalizedVolume);
        }
      }
      if (initialMuted !== undefined) {
        updateVideoMuted(player, initialMuted);
      }
      if (initialPlaybackRate !== undefined) {
        if (isPlaybackRateValid(initialPlaybackRate)) {
          player.setPlaybackRate(initialPlaybackRate);
        }
      }
      player.addEventListener(PLAYER_CAN_PLAY_EVENT, handleCanPlay);
      player.addEventListener(PLAYER_ERROR_EVENT, handlePlayerError);
      player.addEventListener(
        PLAYER_AUDIO_TRACKS_CHANGED_EVENT,
        handleAudioTracksChanged,
      );
      player.addEventListener(
        PLAYER_TEXT_TRACKS_CHANGED_EVENT,
        handleTextTracksChanged,
      );
      const request = player.getVideoByIdFromPlaybackApi({ videoId: resolvedVideoId });
      abortRequest = request.abort;
      request.promise
        .then(model => {
          if (
            disposedRef.current ||
            sourceGenerationRef.current !== generation ||
            playerRef.current !== player
          )
            return;
          try {
            // The initial fetch resolves a queue's first item (videoIds[0]) or
            // the single videoId — either way it is item 0 of the active
            // queue, and the contract fires onQueueItemChanged once per
            // loaded item including the first. The mount path does not go
            // through loadVideoIndex, so emit it here.
            const currentVideoIds = videoIdsRef.current;
            if (currentVideoIds && currentVideoIds.length > 0) {
              callbacksRef.current.onQueueItemChanged?.({
                nativeEvent: {
                  videoId: currentVideoIds[queueIndexRef.current] ?? activeVideoIdRef.current,
                  index: queueIndexRef.current,
                },
              });
            }
            player?.loadBrightcoveVideoModel(model);
            applySidecarTrack(player);
            loadDaiStream();
          } catch (error) {
            emitError(error);
          }
        })
        .catch(emitError);
    } catch (error) {
      if (player) playerRef.current = null;
      callbacksRef.current.onError?.({
        nativeEvent: {
          code: 'invalid_configuration',
          message: `Failed to initialize player: ${extractErrorMessage(error)}`,
          nativeCode: 'player_initialization_failed',
        },
      });
      if (player) {
        try {
          player.detach();
        } catch (detachError) {
          console.error(
            '[BrightcoveWebPlayer] Failed to detach failed player',
            detachError,
          );
        }
        try {
          player.dispose();
        } catch (disposeError) {
          console.error(
            '[BrightcoveWebPlayer] Failed to dispose failed player',
            disposeError,
          );
        }
        player = null;
      }
    }

    return cleanup;
  }, [
    accountId,
    policyKey,
    resolvedVideoId,
    playerFactory,
    dispatchCommandError,
    videoIdsKey,
    loadVideoIndex,
    applyPreferredPeakBitrate,
    applyAudioTrackSelection,
    applyAudioDescriptionSelection,
    applyControlsEnabled,
    applySidecarTrack,
    performChapterSeek,
    startPreload,
    applyCaptionSelection,
    disableNativeSubtitleTracks,
    webControlBarComponents,
    resetSourceScopedState,
  ]);

  useEffect(() => {
    applyAudioDescriptionSelection();
  }, [audioDescriptionEnabled, applyAudioDescriptionSelection]);

  useEffect(() => {
    performChapterSeek();
  }, [chapterSeekTime, chapterSeekRequestId, performChapterSeek]);

  useEffect(() => {
    startPreload();
  }, [preloadVideoId, startPreload]);

  useEffect(() => {
    applyControlsEnabled();
  }, [controlsEnabled, applyControlsEnabled]);

  useEffect(() => {
    applySidecarTrack();
  }, [sidecarTracks, applySidecarTrack]);

  useEffect(() => {
    const player = playerRef.current;
    if (!player || volume === undefined) return;
    const normalizedVolume = normalizeVolume(volume);
    if (normalizedVolume === null) return;
    try {
      updateVideoVolume(player, normalizedVolume);
    } catch (error) {
      dispatchCommandError(
        'setVolumeLevel',
        'failed',
        extractErrorMessage(error),
        'volume_failed',
      );
    }
  }, [volume, dispatchCommandError]);

  useEffect(() => {
    const player = playerRef.current;
    if (!player || muted === undefined) return;
    try {
      updateVideoMuted(player, muted);
    } catch (error) {
      dispatchCommandError(
        'setMuted',
        'failed',
        extractErrorMessage(error),
        'mute_failed',
      );
    }
  }, [muted, dispatchCommandError]);

  useEffect(() => {
    const player = playerRef.current;
    if (!player || loop === undefined) return;
    try {
      const videoEl = player.getVideoElement();
      // The queue's repeatMode "one" also loops the element (see
      // loadVideoIndex): the standalone loop prop stays authoritative for
      // its own scope, and leaving "one" keeps looping only while loop or
      // the queue mode asks for it.
      if (videoEl) videoEl.loop = loop || repeatModeRef.current === 'one';
    } catch {
      // ignore
    }
  }, [loop]);

  // adTagUrl / adConfigId / daiSourceId / daiVideoId configure which ad
  // integrations the SDK builds into the player at creation time; changing
  // them afterwards cannot reconfigure the running player (unlike native,
  // which rebuilds its playback pipeline per source). The contract is
  // initialization-only, and a live change is reported loudly instead of
  // being silently ignored — a silent no-op would leave the app believing
  // ads were enabled for the new values.
  const initialAdConfigKey = `${adTagUrl ?? ''}|${adConfigId ?? ''}|${daiSourceId ?? ''}|${daiVideoId ?? ''}`;
  const initialAdConfigKeyRef = useRef(initialAdConfigKey);
  useEffect(() => {
    if (initialAdConfigKeyRef.current === initialAdConfigKey) return;
    initialAdConfigKeyRef.current = initialAdConfigKey;
    dispatchCommandError(
      'setAdConfiguration',
      'invalid_configuration',
      'adTagUrl, adConfigId, daiSourceId, and daiVideoId are initialization-only on web: they select the ad integrations when the player is created and cannot be changed on a running player (reload re-fetches the source on the same player instance and does not rebuild the integrations). Remount the player with the new values.',
      'ad_config_init_only',
    );
  }, [initialAdConfigKey, dispatchCommandError]);

  useEffect(() => {
    // A repeatMode change must reach the already-loaded item immediately,
    // matching native's applyRepeatModeToNative on every prop change: "one"
    // loops the current item from now on; leaving "one" must clear the
    // element loop unless the standalone loop prop keeps it.
    const player = playerRef.current;
    if (!player) return;
    try {
      const videoEl = player.getVideoElement();
      if (videoEl) {
        videoEl.loop = repeatMode === 'one' || loopRef.current === true;
      }
    } catch {
      // ignore
    }
  }, [repeatMode]);

  useEffect(() => {
    applyPreferredPeakBitrate();
  }, [preferredPeakBitrate, applyPreferredPeakBitrate]);

  useEffect(() => {
    applyAudioTrackSelection();
  }, [audioTrackId, applyAudioTrackSelection]);

  useEffect(() => {
    applyCaptionSelection();
    if (!customCaptionRenderingEnabled) {
      lastCustomCaptionCueKeyRef.current = null;
      callbacksRef.current.onCaptionCueChanged?.({
        nativeEvent: { text: '', startTime: 0, endTime: 0 },
      });
    }
  }, [
    captionsEnabled,
    captionTrackId,
    customCaptionRenderingEnabled,
    applyCaptionSelection,
  ]);

  useEffect(() => {
    const player = playerRef.current;
    if (!player) return;
    const videoEl = player.getVideoElement();
    if (!videoEl) return;
    videoEl.style.objectFit = videoScalingMode === 'fill' ? 'cover' : 'contain';
  }, [videoScalingMode]);

  useEffect(() => {
    const player = playerRef.current;
    if (!player || playbackRate === undefined) return;
    if (!isPlaybackRateValid(playbackRate)) return;
    try {
      player.setPlaybackRate(playbackRate);
    } catch (error) {
      dispatchCommandError(
        'setPlaybackRate',
        'failed',
        extractErrorMessage(error),
        'playback_rate_failed',
      );
    }
  }, [playbackRate, dispatchCommandError]);

  return (
    <View style={[styles.root, style]} testID={testID}>
      <div ref={containerRef} style={domContainerStyle} />
    </View>
  );
});

const styles = StyleSheet.create({
  root: {
    overflow: 'hidden',
    position: 'relative',
  },
});

const domContainerStyle: React.CSSProperties = {
  width: '100%',
  height: '100%',
  position: 'relative',
};
