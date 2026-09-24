package com.brightcove.reactnativeplayer.core

import androidx.media3.common.PlaybackException
import org.junit.Assert.assertEquals
import org.junit.Test

// Verifies the normalized error contract the DRM sample advertises against the
// real Media3 PlaybackException codes and the catalog error tokens — so `code`
// is proven in CI rather than only exercised through a mocked native component.
class PlayerErrorClassifierTest {
  // Every DRM code in the Media3 range must map to "drm" — including the
  // highest one, LICENSE_EXPIRED, which sits just above DEVICE_REVOKED and is a
  // common Widevine failure. Asserting the whole contiguous range guards
  // against a range bound that stops short of a real DRM code.
  @Test
  fun drmPlaybackCodesMapToDrm() {
    for (code in PlaybackException.ERROR_CODE_DRM_UNSPECIFIED..
      PlaybackException.ERROR_CODE_DRM_LICENSE_EXPIRED) {
      assertEquals("drm", PlayerErrorClassifier.playbackErrorCategory(code))
    }
    // Named spot-checks of the codes the contract calls out explicitly.
    assertEquals("drm", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_DRM_SCHEME_UNSUPPORTED))
    assertEquals("drm", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_DRM_PROVISIONING_FAILED))
    assertEquals("drm", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED))
    assertEquals("drm", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_DRM_DEVICE_REVOKED))
    assertEquals("drm", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_DRM_LICENSE_EXPIRED))
  }

  // Every IO code in the Media3 range maps to "network" — including the top two
  // (CLEARTEXT_NOT_PERMITTED, READ_POSITION_OUT_OF_RANGE) that sit above
  // NO_PERMISSION. Asserting the whole contiguous range guards against a bound
  // that stops short of a real IO code (the DRM range had exactly that bug).
  @Test
  fun ioCodesMapToNetwork() {
    for (code in PlaybackException.ERROR_CODE_IO_UNSPECIFIED..
      PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE) {
      assertEquals("network", PlayerErrorClassifier.playbackErrorCategory(code))
    }
    assertEquals("network", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED))
    assertEquals("network", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED))
    assertEquals("network", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE))
  }

  @Test
  fun parsingAndDecoderCodesMapToNotPlayable() {
    assertEquals("not_playable", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED))
    assertEquals("not_playable", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED))
  }

  @Test
  fun unmappedTypedCodeIsPlayback() {
    assertEquals("playback", PlayerErrorClassifier.playbackErrorCategory(
      PlaybackException.ERROR_CODE_UNSPECIFIED))
  }

  // The core of the review: a generic/untyped ERROR (no PlaybackException) must
  // NOT be classified as anything terminal — it returns unknown, and the caller
  // must not latch it over a pending authoritative typed result.
  @Test
  fun untypedErrorIsUnknown() {
    assertEquals("unknown", PlayerErrorClassifier.playbackErrorCategory(null))
  }

  @Test
  fun catalogTokensMapToTheirCategories() {
    assertEquals("not_found", PlayerErrorClassifier.catalogErrorCategory("VIDEO_NOT_FOUND"))
    assertEquals("not_playable", PlayerErrorClassifier.catalogErrorCategory("VIDEO_NOT_PLAYABLE"))
    assertEquals("network", PlayerErrorClassifier.catalogErrorCategory("NETWORK_ERROR"))
    assertEquals("network", PlayerErrorClassifier.catalogErrorCategory("REQUEST_TIMEOUT"))
  }

  // An access failure (bad/expired policy key, geo-restriction) is real but is
  // NOT a missing video, so it must fall through to unknown, never not_found.
  @Test
  fun accessFailureIsUnknownNotNotFound() {
    assertEquals("unknown", PlayerErrorClassifier.catalogErrorCategory("ACCESS_DENIED"))
    assertEquals("unknown", PlayerErrorClassifier.catalogErrorCategory("FORBIDDEN"))
  }

  // The exact type PlaybackMediaItem.Builder.build throws for a source whose
  // delivery type ExoMediaPlayback cannot build a MediaSource for (confirmed
  // against exoplayer2-10.4.25 sources) — the untyped-ERROR path with no
  // SOURCE_NOT_FOUND and no guaranteed PlaybackException to follow, which used
  // to hang the player on Loading forever. Must be positively recognized as
  // terminal so it reaches onError instead of being silently dropped.
  @Test
  fun unsupportedDeliveryTypeIsTerminal() {
    assertEquals(
      true,
      PlayerErrorClassifier.isTerminalUntypedThrowable(
        IllegalStateException("Unsupported type: RTMP"),
      ),
    )
  }

  @Test
  fun unrelatedIllegalStateExceptionIsNotTerminal() {
    assertEquals(
      false,
      PlayerErrorClassifier.isTerminalUntypedThrowable(
        IllegalStateException("Player is already released"),
      ),
    )
  }

  // onLoadError's untyped precursor is always an IOException (a recoverable
  // segment-fetch blip Media3 documents as non-fatal) — it must NOT be
  // classified as terminal, or a recoverable blip would kill playback and
  // suppress onReady before the stream ever gets a chance to recover.
  @Test
  fun loadErrorIOExceptionIsNotTerminal() {
    assertEquals(
      false,
      PlayerErrorClassifier.isTerminalUntypedThrowable(java.io.IOException("segment fetch failed")),
    )
  }

  // A DRM session manager's untyped pre-echo (a generic Exception, not
  // IllegalStateException) precedes the typed onPlayerError PlaybackException
  // that carries the real ERROR_CODE_DRM_* classification — it must NOT be
  // classified as terminal here, or the untyped pre-echo would latch `drm`'s
  // authoritative typed replacement out of the race.
  @Test
  fun drmSessionManagerPreEchoIsNotTerminal() {
    assertEquals(
      false,
      PlayerErrorClassifier.isTerminalUntypedThrowable(Exception("drm session error")),
    )
  }

  @Test
  fun nullThrowableIsNotTerminal() {
    assertEquals(false, PlayerErrorClassifier.isTerminalUntypedThrowable(null))
  }

  @Test
  fun aggregateQueueErrorCategoryReportsSharedCategory() {
    assertEquals(
      "not_found",
      PlayerErrorClassifier.aggregateQueueErrorCategory(listOf("not_found", "not_found")),
    )
    assertEquals(
      "network",
      PlayerErrorClassifier.aggregateQueueErrorCategory(listOf("network")),
    )
  }

  // A mixed batch of failure categories has no single honest cause: reporting
  // any one of them (e.g. the first) would claim more than the data supports.
  @Test
  fun aggregateQueueErrorCategoryReportsUnknownForMixedCategories() {
    assertEquals(
      "unknown",
      PlayerErrorClassifier.aggregateQueueErrorCategory(listOf("not_found", "network")),
    )
  }

  @Test
  fun aggregateQueueErrorCategoryReportsUnknownForEmptyList() {
    assertEquals("unknown", PlayerErrorClassifier.aggregateQueueErrorCategory(emptyList()))
  }

  @Test
  fun classifyCatalogErrorPrefersTheTypedCatalogCode() {
    assertEquals(
      "not_found" to "VIDEO_NOT_FOUND",
      PlayerErrorClassifier.classifyCatalogError(
        "VIDEO_NOT_FOUND",
        java.io.IOException("transport noise"),
      ),
    )
  }

  @Test
  fun classifyCatalogErrorMapsIOExceptionWithoutCatalogCodeToNetwork() {
    assertEquals(
      "network" to "IOException",
      PlayerErrorClassifier.classifyCatalogError(null, java.io.IOException("offline")),
    )
  }

  @Test
  fun classifyCatalogErrorMapsUntypedThrowableToUnknownWithItsClass() {
    assertEquals(
      "unknown" to "IllegalStateException",
      PlayerErrorClassifier.classifyCatalogError(null, IllegalStateException("broken")),
    )
  }

  @Test
  fun classifyCatalogErrorUsesCatalogFallbackWhenNoDetailsExist() {
    assertEquals(
      "unknown" to "catalog_error",
      PlayerErrorClassifier.classifyCatalogError(null, null),
    )
  }
}
