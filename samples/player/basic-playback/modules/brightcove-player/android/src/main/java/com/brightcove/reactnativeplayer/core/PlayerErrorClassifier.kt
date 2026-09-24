package com.brightcove.reactnativeplayer.core

import androidx.media3.common.PlaybackException

/**
 * Pure mapping from a native SDK error to the normalized cross-platform error
 * category documented in the TS contract, so `error.code` is a value a customer
 * can branch on identically on iOS and Android. Kept free of Android view/SDK
 * state so it is unit-testable on the JVM (see PlayerErrorClassifierTest) — the
 * error contract is a promise the sample advertises, so it is verified in CI
 * rather than only exercised through a mocked native component.
 *
 * Anything not positively recognized is `unknown`, never guessed: reporting an
 * access failure (expired/invalid policy key, geo-restriction) or a 5xx as
 * "this video does not exist" would be a false statement in a contract whose
 * whole value is that `code` never lies.
 */
object PlayerErrorClassifier {
  /**
   * Maps a catalog (Playback API) error code to the normalized category. An
   * ACCESS failure is deliberately not mapped to not_found: it is a real error
   * but not a missing video, so it falls through to unknown.
   */
  fun catalogErrorCategory(nativeCode: String): String =
    when {
      nativeCode.contains("NOT_FOUND", ignoreCase = true) -> "not_found"
      nativeCode.contains("NOT_PLAYABLE", ignoreCase = true) -> "not_playable"
      nativeCode.contains("NETWORK", ignoreCase = true) ||
        nativeCode.contains("TIMEOUT", ignoreCase = true) -> "network"
      else -> "unknown"
    }

  /**
   * Classifies both Playback API error shapes once: a server catalog code, or a
   * transport exception that occurred before any response. Callers receive the
   * normalized JS code and the diagnostic native code as one pair so queue
   * item events and terminal source errors cannot drift apart.
   */
  fun classifyCatalogError(
    catalogCode: String?,
    throwable: Throwable?,
  ): Pair<String, String> {
    val normalizedCatalogCode = catalogCode?.ifBlank { null }
    if (normalizedCatalogCode == null && throwable != null) {
      return (if (throwable is java.io.IOException) "network" else "unknown") to
        throwable.javaClass.simpleName
    }
    val nativeCode = normalizedCatalogCode ?: "catalog_error"
    return catalogErrorCategory(nativeCode) to nativeCode
  }

  /**
   * Maps a Media3 playback error to the normalized category by switching on the
   * documented PlaybackException.errorCode ranges — not by substring-matching
   * class names or message text, which are not API and drift between releases.
   * A null code (an untyped/generic event) is `unknown`; the caller must not
   * terminally latch that over a pending authoritative typed result.
   */
  fun playbackErrorCategory(errorCode: Int?): String {
    val code = errorCode ?: return "unknown"
    return when (code) {
      in PlaybackException.ERROR_CODE_DRM_UNSPECIFIED..
        PlaybackException.ERROR_CODE_DRM_LICENSE_EXPIRED -> "drm"
      in PlaybackException.ERROR_CODE_IO_UNSPECIFIED..
        PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE -> "network"
      in PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED..
        PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED,
      in PlaybackException.ERROR_CODE_DECODER_INIT_FAILED..
        PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> "not_playable"
      else -> "playback"
    }
  }

  /**
   * Whether an untyped ERROR event's Throwable (no PlaybackException/
   * DrmSessionException to classify by errorCode — see playbackErrorCategory)
   * is nonetheless a positively-identified TERMINAL failure that must not be
   * silently ignored while waiting for a typed replacement that will never
   * arrive.
   *
   * Only an IllegalStateException with the exact `Unsupported type: ` prefix
   * qualifies: this is the message shape PlaybackMediaItem.Builder.build's
   * `default:` branch throws for a source whose delivery type ExoMediaPlayback
   * cannot build a MediaSource (confirmed against exoplayer2-10.4.25 sources).
   * ExoMediaPlayback re-emits it untyped, with no SOURCE_NOT_FOUND and no
   * guaranteed PlaybackException to follow, so without this the caller drops
   * it and the player hangs on Loading forever (videoLoaded already true,
   * neither onReady nor onError ever fires). Other IllegalStateExceptions must
   * remain unknown because their cause is not established by their type alone.
   *
   * Deliberately narrow (a specific class and verified message prefix, not "any Throwable"): onLoadError's
   * IOException (a recoverable segment-fetch blip Media3 documents as
   * non-fatal) and a DRM session manager's untyped pre-echo Exception (which
   * precedes the typed onPlayerError PlaybackException) must still return
   * false here and be ignored by the caller, or their authoritative typed
   * result would be dropped/pre-empted by a premature terminal classification.
   */
  fun isTerminalUntypedThrowable(throwable: Throwable?): Boolean =
    throwable is IllegalStateException &&
      throwable.message?.startsWith("Unsupported type: ") == true

  /**
   * Determines the aggregate PlayerErrorCode for a queue where every item
   * failed to resolve. Preserves truth rather than guessing a single cause:
   * - If every item failed with the same category, reports that category.
   * - If failure categories are mixed, reports `unknown` rather than picking
   *   one arbitrarily (a mixed batch has no single honest category).
   */
  fun aggregateQueueErrorCategory(codes: List<String>): String {
    if (codes.isEmpty()) return "unknown"
    val distinct = codes.toSet()
    return if (distinct.size == 1) distinct.first() else "unknown"
  }
}
