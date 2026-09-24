package com.brightcove.reactnativeplayer.sourceloadingmodes

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SourceLoadingModeSelectionTest {
  @Test
  fun selectingANewModeClearsTheOthers() {
    val selection = SourceLoadingModeSelection()
      .apply("videoReferenceId", "ref-1")
      .apply("playlistId", "pl-1")

    assertEquals("", selection.videoReferenceId)
    assertEquals("pl-1", selection.playlistId)
    assertEquals(1, selection.activeModeCount())
  }

  // The regression: a late empty update for the previously-selected mode must
  // not wipe the newly-selected mode when Fabric applies the two changed props
  // in the other order.
  @Test
  fun clearingTheOldModeAfterSelectingANewOneKeepsTheNewMode() {
    val selection = SourceLoadingModeSelection()
      .apply("playlistId", "pl-1")
      .apply("videoReferenceId", "")

    assertEquals("pl-1", selection.playlistId)
    assertEquals("", selection.videoReferenceId)
    assertEquals(1, selection.activeModeCount())
  }

  @Test
  fun clearingTheActiveModeLeavesNoActiveMode() {
    val selection = SourceLoadingModeSelection()
      .apply("sourceUrl", "https://cdn.example.com/v.mp4")
      .apply("sourceUrl", "")

    assertEquals(0, selection.activeModeCount())
  }

  @Test
  fun unknownPropIsRejected() {
    assertThrows(IllegalStateException::class.java) {
      SourceLoadingModeSelection().apply("nope", "x")
    }
  }

  @Test
  fun directUrlDoesNotRequireCredentials() {
    assertFalse(
      SourceLoadingModeSelection()
        .apply("sourceUrl", "https://cdn.example.com/v.mp4")
        .requiresCredentials(),
    )
  }

  @Test
  fun referenceAndPlaylistModesRequireCredentials() {
    assertTrue(SourceLoadingModeSelection().apply("videoReferenceId", "ref").requiresCredentials())
    assertTrue(SourceLoadingModeSelection().apply("playlistId", "pl").requiresCredentials())
    assertTrue(
      SourceLoadingModeSelection().apply("playlistReferenceId", "pl-ref").requiresCredentials(),
    )
  }

  @Test
  fun noActiveModeDoesNotRequireCredentials() {
    assertFalse(SourceLoadingModeSelection().requiresCredentials())
  }
}
