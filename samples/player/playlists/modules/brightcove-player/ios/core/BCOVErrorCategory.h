#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Maps a native NSError to the normalized cross-platform error category
 * documented in the TS contract, so error.code is a value a customer can
 * branch on identically on iOS and Android. The raw domain:code is preserved
 * separately by the caller as nativeCode (see BCOVNativeErrorCode).
 *
 * Anything not positively recognized is reported as `unknown`, never
 * guessed: an access failure (a 401/403 from an expired/invalid policy key
 * or a geo-restriction) and a 5xx server error are NOT a missing video, so
 * they must never be reported as not_found — the whole value of `code` is
 * that it does not lie.
 *
 * Single source of truth: both the core single-video path
 * (BrightcovePlayerView's catalog/playback errors) and any feature that
 * performs its own catalog resolution (e.g. BrightcovePlaylistsFeature,
 * BrightcovePreloadingFeature, BrightcoveSourceLoadingModesFeature) call
 * this same function, so a change to the classification rules only has one
 * place to make it.
 */
NSString *BCOVErrorCategory(NSError *_Nullable error);

/**
 * The diagnostic native error identity for an NSError: domain:code, except
 * for a Playback API error, which uses the Playback API's own typed
 * error_code (and error_subcode, if present) since that is more useful for
 * debugging than the generic BCOVPlaybackServiceErrorCodeAPIError value every
 * API error shares.
 */
NSString *BCOVNativeErrorCode(NSError *error);

/**
 * Determines the aggregate PlayerErrorCode for a queue where every item
 * failed to resolve. Preserves truth rather than guessing a single cause:
 * if every item failed with the same category, reports that category;
 * otherwise reports `unknown` rather than picking one arbitrarily.
 */
NSString *BCOVAggregateQueueErrorCategory(NSArray<NSString *> *codes);

NS_ASSUME_NONNULL_END
