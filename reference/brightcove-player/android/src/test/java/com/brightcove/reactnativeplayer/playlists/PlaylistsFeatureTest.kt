package com.brightcove.reactnativeplayer.playlists

import com.brightcove.player.model.Video
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaylistsFeatureTest {
  @Test
  fun ownedPropsAndExportedEventsAreCorrect() {
    val feature = PlaylistsFeature()
    assertEquals(setOf("videoIds", "repeatMode", "shuffle"), feature.ownedProps)
    assertEquals(setOf("next", "previous"), feature.supportedCommands)
    assertTrue(feature.exportedEvents.containsKey("topQueueItemChanged"))
    assertTrue(feature.exportedEvents.containsKey("topQueueItemFailed"))
    assertTrue(feature.exportedEvents.containsKey("topQueueCompleted"))
  }

  @Test
  fun claimsSourceLoadingOnlyWhenVideoIdsIsNonEmpty() {
    val feature = PlaylistsFeature()
    assertFalse(feature.claimsSourceLoading())
  }

  @Test
  fun setPropRejectsUnknownProps() {
    val feature = PlaylistsFeature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("unknownProp", "value")
    }
  }

  @Test
  fun repeatModeValidationAcceptsValidModes() {
    val feature = PlaylistsFeature()
    // Should not throw
    feature.setProp("repeatMode", "off")
    feature.setProp("repeatMode", "one")
    feature.setProp("repeatMode", "all")
  }

  @Test
  fun repeatModeValidationRejectsInvalidModes() {
    val feature = PlaylistsFeature()
    assertThrows(IllegalArgumentException::class.java) {
      feature.setProp("repeatMode", "invalid_mode")
    }
    assertThrows(IllegalArgumentException::class.java) {
      feature.setProp("repeatMode", "loop")
    }
  }

  @Test
  fun shuffleValidationAcceptsBooleans() {
    val feature = PlaylistsFeature()
    feature.setProp("shuffle", true)
    feature.setProp("shuffle", false)
  }

  @Test
  fun shuffleRejectsNonBoolean() {
    val feature = PlaylistsFeature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("shuffle", "true")
    }
  }

  @Test
  fun repeatModeRejectsNonString() {
    val feature = PlaylistsFeature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("repeatMode", 1)
    }
  }

  // Regression: a wrong-typed videoIds used to coerce to emptyList(), which is
  // indistinguishable from a legitimately empty queue — the source silently
  // reloaded onto the single-video path with no onError/onQueueItemFailed. It
  // must reject loudly, consistent with repeatMode/shuffle.
  @Test
  fun videoIdsRejectsANonListValue() {
    val feature = PlaylistsFeature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("videoIds", "not-a-list")
    }
  }

  @Test
  fun videoIdsRejectsANonStringElement() {
    val feature = PlaylistsFeature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("videoIds", listOf("5702148954001", 123))
    }
  }

  @Test
  fun videoIdsAcceptsAListOfStrings() {
    val feature = PlaylistsFeature()
    feature.setProp("videoIds", listOf("5702148954001", "5702143016001"))
    assertTrue(feature.claimsSourceLoading())
  }

  @Test
  fun teardownAndResetClearStateSafely() {
    val feature = PlaylistsFeature()
    feature.onSourceReset()
    feature.onDispose()
    // Should be safe to call multiple times without throwing
    feature.onDispose()
  }

  // Regression for a duplicate-id ambiguity flagged in review: a videoIds
  // queue can legitimately contain the same catalog id twice (e.g. a bumper
  // repeated between items). resolvedIndexOf must match by object identity
  // only — never falling back to id equality, which would silently return
  // the *first* occurrence for either duplicate and feed a wrong index into
  // onQueueItemChanged / completion tracking.
  @Test
  fun resolvedIndexOfMatchesByIdentityNotId() {
    val feature = PlaylistsFeature()
    val firstBumper = Video(mapOf("id" to "5702148954001"))
    val secondBumper = Video(mapOf("id" to "5702148954001"))
    feature.addResolvedItemForTest(firstBumper, originalIndex = 0)
    feature.addResolvedItemForTest(secondBumper, originalIndex = 2)

    assertEquals(0, feature.resolvedIndexOf(firstBumper))
    assertEquals(1, feature.resolvedIndexOf(secondBumper))
  }

  // A Video the feature never added (e.g. a copy the SDK handed back with the
  // same id, rather than the exact instance passed to videoView.add) must not
  // match anything by id. Returning -1 here is what lets the caller fall back
  // to "no event" / the last-known index rather than reporting a wrong one.
  @Test
  fun resolvedIndexOfReturnsNoMatchForAnUnresolvedCopyWithTheSameId() {
    val feature = PlaylistsFeature()
    val added = Video(mapOf("id" to "5702148954001"))
    val sdkCopyWithSameId = Video(mapOf("id" to "5702148954001"))
    feature.addResolvedItemForTest(added, originalIndex = 0)

    assertEquals(-1, feature.resolvedIndexOf(sdkCopyWithSameId))
  }

  @Test
  fun resolvedIndexOfReturnsNoMatchForNullVideo() {
    val feature = PlaylistsFeature()
    assertEquals(-1, feature.resolvedIndexOf(null))
  }

  @Test
  fun willChangeVideoPrefersIdentityOverStaleCurrentMediaItemIndex() {
    val feature = PlaylistsFeature()
    val first = Video(mapOf("id" to "5421538222001"))
    val second = Video(mapOf("id" to "5421538223001"))
    feature.addResolvedItemForTest(first, originalIndex = 0)
    feature.addResolvedItemForTest(second, originalIndex = 1)

    assertEquals(1, feature.willChangeVideoTargetIndex(second, currentMediaItemIndex = 0))
  }

  @Test
  fun willChangeVideoUsesNativeIndexOnlyWhenIdentityIsUnknown() {
    val feature = PlaylistsFeature()
    val first = Video(mapOf("id" to "5421538222001"))
    val second = Video(mapOf("id" to "5421538223001"))
    feature.addResolvedItemForTest(first, originalIndex = 0)
    feature.addResolvedItemForTest(second, originalIndex = 1)
    val sdkCopy = Video(mapOf("id" to "5421538223001"))

    assertEquals(1, feature.willChangeVideoTargetIndex(sdkCopy, currentMediaItemIndex = 1))
    assertEquals(-1, feature.willChangeVideoTargetIndex(sdkCopy, currentMediaItemIndex = 7))
  }
}
