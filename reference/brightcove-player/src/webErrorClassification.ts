// The web event/error contract deliberately shares its payload types with the
// native contract (BrightcovePlayerViewNativeComponent.ts) through type-only
// re-exports, so the two surfaces cannot drift apart: a prop means the same
// thing on web, iOS, and Android or it does not type-check. RN's Codegen
// `Double` is an alias for `number`, so the native declarations are valid
// verbatim in a browser context.
//
// Web-only events with no native counterpart are declared and documented here,
// never silently: the HTML5 media pipeline surfaces them for free and the
// native SDKs do not, so they are extras rather than a divergence of a shared
// contract.
export type {
  PlayerErrorCode,
  PlayerCommandErrorCode,
  ReadyEventData,
  VideoSizeChangedEventData,
  PlaybackProgressEventData,
  LiveStatusEventData,
  SeekableRangesChangedEventData,
  RepeatMode,
  VideoScalingMode,
  QueueItemChangedEventData,
  QueueItemFailedEventData,
  AudioDescriptionAvailableEventData,
  AudioDescriptionChangedEventData,
  RenditionChangedEventData,
  ChapterSeekCompletedEventData,
  PlayerErrorEventData,
  PlayerCommandErrorEventData,
  CaptionsAvailableEventData,
  CaptionTrackChangedEventData,
  PictureInPictureModeChangedEventData,
  FullscreenChangedEventData,
  AdEventData,
  AdBreakEventData,
  AllAdsCompletedEventData,
  AudioTracksAvailableEventData,
  AudioTrackChangedEventData,
  TimedMetadataEventData,
  PreloadQueuedEventData,
  PreloadHandoffEventData,
  PreloadErrorEventData,
  AdPausedEventData,
  AdResumedEventData,
  AdProgressEventData,
  AdQuartileEventData,
  AdSkippedEventData,
  AdInteractionEventData,
  AdMetadataEventData,
  AdOverlayStateChangedEventData,
  AdErrorEventData,
  SidecarTrackStatusEventData,
  CaptionCueEventData,
} from './BrightcovePlayerViewNativeComponent';

// Web-only, not part of the native Codegen contract: the HTML5 media element
// surfaces these signals natively (media events + the fetch-driven source
// pipeline), while the Brightcove native SDKs deliver their equivalents
// through other events (onProgress duration, onReady after first frame,
// onVideoSizeChanged) or not at all. They are additive browser-only extras.
export type SourceLoadingEventData = Readonly<{
  videoId: string;
}>;

export type FirstFrameEventData = Readonly<{
  videoId: string;
}>;

export type SeekStartedEventData = Readonly<{
  requestedPositionSeconds: number;
}>;

export type SeekCompletedEventData = Readonly<{
  positionSeconds: number;
  completed: boolean;
}>;

export type DurationChangedEventData = Readonly<{
  durationSeconds: number;
}>;

interface WebSdkError {
  category?: string;
  code?: string | number;
  message?: string;
  description?: string;
  name?: string;
  errorObject?: {
    message?: string;
    statusText?: string;
  };
}

function readError(error: unknown): WebSdkError {
  if (error && typeof error === 'object') return error as WebSdkError;
  if (typeof error === 'string') return { message: error };
  return {};
}

function extractErrorMessage(error: WebSdkError): string {
  return (
    error.message ||
    error.description ||
    error.errorObject?.message ||
    error.errorObject?.statusText ||
    'Unknown playback error'
  );
}

export function classifyWebPlayerError(error: unknown): {
  code: import('./BrightcovePlayerViewNativeComponent').PlayerErrorCode;
  message: string;
  nativeCode: string;
} {
  const sdkError = readError(error);
  const rawCode =
    sdkError.code !== undefined
      ? String(sdkError.code)
      : sdkError.name || 'unknown';
  const numericCode =
    typeof sdkError.code === 'number' ? sdkError.code : Number(sdkError.code);
  const category = sdkError.category || '';
  const message = extractErrorMessage(sdkError);

  let code: import('./BrightcovePlayerViewNativeComponent').PlayerErrorCode =
    'unknown';
  if (
    category === 'Network' ||
    (numericCode >= 1000 && numericCode <= 1004) ||
    numericCode === 2002 ||
    numericCode === 4001
  ) {
    code = 'network';
  } else if (
    [2000, 2001, 4002, 4003, 4005, 6013, 6014, 6034].includes(numericCode) ||
    (numericCode >= 5000 && numericCode <= 5003)
  ) {
    code = 'not_playable';
  } else if (
    category === 'Eme' ||
    (numericCode >= 3000 && numericCode <= 3010) ||
    numericCode === 4004 ||
    numericCode === 5005
  ) {
    code = 'drm';
  } else if ([6000, 6001, 6005, 6006].includes(numericCode)) {
    code = 'invalid_configuration';
  } else if ([6019, 6020, 6021, 6027].includes(numericCode)) {
    code = 'not_found';
  } else if (
    [4000, 4006].includes(numericCode) ||
    (numericCode >= 5004 && numericCode <= 5008)
  ) {
    code = numericCode === 4006 ? 'unknown' : 'playback';
  }

  return { code, message, nativeCode: rawCode };
}

// The web SDK delivers SSAI ad failures through the same PlayerError event
// as content failures, but with the ad-class error codes (the video.js ads
// plugin's Preroll/Midroll/Postroll codes and the SSAI/IMA integration's
// VMAP/session codes, 5009-5027). The native contract reports an ad failure
// through onAdError and never fails the content source, so the web error
// path routes these codes the same way instead of latching sourceFailed on
// a playing video.
const AD_CLASS_ERROR_CODES: ReadonlySet<number> = new Set<number>([
  5009, 5010, 5011, 5012, // Ads preroll/postroll/midroll/before-preroll
  5013, 5014, // RestorePlayerFailed, AdsMacroReplacementFailed
  5015, 5016, 5017, 5018, 5019, 5020, 5021, // IMA integration errors
  // SSAI Open Measurement errors happen after the stitched source exists and
  // are ad-only failures. VMAP request/parsing errors (5022-5024, 5027) happen
  // before any stitched source can load, so they intentionally stay on the
  // content onError path instead — the same fatal-source contract as iOS and
  // Android.
  5025, 5026,
]);

/**
 * Whether a classified web player error is an ad failure rather than a
 * content-playback failure. The web SDK bundles both through PlayerError;
 * the numeric ad-class codes are the only discriminator.
 */
export function isAdClassWebPlayerError(error: unknown): boolean {
  const sdkError = readError(error);
  const numericCode =
    typeof sdkError.code === 'number' ? sdkError.code : Number(sdkError.code);
  return AD_CLASS_ERROR_CODES.has(numericCode);
}

/**
 * The ad-error contract's codes (AdErrorEventData.code): 'load' when the ad or
 * its tag/VMAP could not be fetched or parsed, 'playback' when an ad loaded but
 * failed to play, 'unknown' when the failure cannot be placed in either. This
 * is a different vocabulary from PlayerErrorCode, so a content classification
 * is never passed through as an ad-error code.
 */
type AdErrorCode = 'load' | 'playback' | 'unknown';

/**
 * Classifies an SSAI ad failure — an ad-class PlayerError, see
 * isAdClassWebPlayerError — onto the ad-error contract. The ad-class codes do
 * not say whether the ad failed to load or to play, so the one positive signal
 * is the error category: a Network failure means an ad resource could not be
 * fetched, which is a load failure. Anything else is 'unknown' rather than a
 * guess, the same answer the native bridges give for an ad error they cannot
 * type.
 */
export function classifyWebAdError(error: unknown): {
  code: AdErrorCode;
  message: string;
  nativeCode: string;
} {
  const sdkError = readError(error);
  return {
    code: sdkError.category === 'Network' ? 'load' : 'unknown',
    message: extractErrorMessage(sdkError),
    nativeCode:
      sdkError.code !== undefined
        ? String(sdkError.code)
        : sdkError.name || 'unknown',
  };
}

// IMA's AdError as the web SDK's IMA integration delivers it: the integration
// forwards IMA's AdErrorEvent as `originalEvent`, whose getError() carries the
// typed failure.
interface ImaAdError {
  getType?: () => unknown;
  getMessage?: () => unknown;
  getErrorCode?: () => unknown;
}

/**
 * Classifies a client-side IMA ad error onto the ad-error contract by IMA's own
 * error type, exactly as the native bridges map it: 'adLoadError' is 'load' and
 * 'adPlayError' is 'playback'. A payload that carries no IMA error is 'unknown',
 * with whatever message and code the event itself has.
 */
export function classifyImaClientSideAdError(eventData: unknown): {
  code: AdErrorCode;
  message: string;
  nativeCode: string;
} {
  const data =
    eventData && typeof eventData === 'object'
      ? (eventData as {
          message?: unknown;
          code?: unknown;
          originalEvent?: { getError?: () => unknown };
        })
      : {};
  const imaError =
    typeof data.originalEvent?.getError === 'function'
      ? (data.originalEvent.getError() as ImaAdError | undefined)
      : undefined;
  const imaType = imaError?.getType?.();
  const imaMessage = imaError?.getMessage?.();
  const imaCode = imaError?.getErrorCode?.();
  let code: AdErrorCode = 'unknown';
  if (imaType === 'adLoadError') code = 'load';
  else if (imaType === 'adPlayError') code = 'playback';
  let message = 'IMA client-side ad error';
  if (typeof imaMessage === 'string' && imaMessage) message = imaMessage;
  else if (typeof data.message === 'string' && data.message) message = data.message;
  let nativeCode = 'ima_client_side_ad_error';
  if (typeof imaCode === 'number' || typeof imaCode === 'string') nativeCode = String(imaCode);
  else if (typeof data.code === 'number' || typeof data.code === 'string') nativeCode = String(data.code);
  return { code, message, nativeCode };
}

export function validateSeekPosition(positionSeconds: number): string | null {
  if (!Number.isFinite(positionSeconds))
    return 'positionSeconds must be finite';
  if (positionSeconds < 0) return 'positionSeconds must be non-negative';
  if (positionSeconds > Number.MAX_SAFE_INTEGER / 1000)
    return 'positionSeconds is too large';
  return null;
}

export function validateVolume(volume: number): string | null {
  if (!Number.isFinite(volume)) return 'volume must be finite';
  if (volume < 0 || volume > 1) return 'volume must be between 0 and 1';
  return null;
}

/**
 * Normalizes a requested volume to the shared contract: out-of-range finite
 * values are clamped to [0, 1] and a non-finite value (NaN/Infinity) is
 * rejected (null) so the previous volume stays in effect. This mirrors the
 * native bridges exactly — Android clamps with `coerceIn` and ignores NaN,
 * iOS clamps with MIN/MAX and ignores NaN — so a shared error handler sees
 * the same behavior on every platform.
 */
export function normalizeVolume(volume: number): number | null {
  if (Number.isNaN(volume)) return null;
  if (!Number.isFinite(volume)) return volume > 0 ? 1 : 0;
  if (volume < 0) return 0;
  if (volume > 1) return 1;
  return volume;
}

/**
 * Whether a requested playback rate is accepted by the shared contract.
 * Values <= 0, NaN, and non-finite values are rejected; the caller keeps the
 * previously-applied rate (identically on both native platforms).
 */
export function isPlaybackRateValid(rate: number): boolean {
  return Number.isFinite(rate) && rate > 0;
}

export function validatePlaybackRate(rate: number): string | null {
  if (!Number.isFinite(rate)) return 'playbackRate must be finite';
  if (rate <= 0) return 'playbackRate must be greater than 0';
  return null;
}
