package com.brightcove.reactnativeplayer.audiotracks

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioTrackIdMapTest {
  @Test
  fun sourceScopedIdsRejectAnIdFromAnEarlierSource() {
    val map = AudioTrackIdMap()

    map.reset()
    map.replace(listOf("English"))
    val sourceAId = map.all().single().id

    map.reset()
    map.replace(listOf("English"))

    assertNotEquals(sourceAId, map.all().single().id)
    assertNull(map.entryForId(sourceAId))
    assertEquals(AudioTrackSelectionAction.Clear, map.selectionAction(sourceAId, null, null))
  }

  @Test
  fun roleVariantsWithTheSameLanguageKeepSeparateSelectionKeys() {
    val map = AudioTrackIdMap()
    map.reset()
    map.replace(listOf("en (Main)", "en (Alternate)"))

    val entries = map.all()
    assertEquals(2, entries.map { it.id }.distinct().size)
    assertEquals("en (Main)", map.entryForId(entries[0].id)?.selectionKey)
    assertEquals("en (Alternate)", map.entryForId(entries[1].id)?.selectionKey)
  }

  @Test
  fun invalidIdAfterAppliedSelectionClearsTheOverride() {
    val map = AudioTrackIdMap()
    map.reset()
    map.replace(listOf("en (Main)"))
    val applied = map.all().single()

    assertEquals(
      AudioTrackSelectionAction.Clear,
      map.selectionAction("not-current", applied.id, applied.selectionKey),
    )
  }

  @Test
  fun resetRemovesEntriesWhileTheControlledRequestCanRemainStale() {
    val map = AudioTrackIdMap()
    map.reset()
    map.replace(listOf("en (Main)"))
    val oldId = map.all().single().id

    map.reset()

    assertEquals(emptyList<AudioTrackEntry>(), map.all())
    assertNull(map.entryForId(oldId))
  }

  @Test
  fun selectionStateMachineHandlesSelectClearStaleIdAndPendingConfirmation() {
    val map = AudioTrackIdMap()
    map.reset()
    map.replace(listOf("en (Main)", "es (Spanish)", "fr (French)"))

    val tracks = map.all()
    val trackEn = tracks[0]
    val trackEs = tracks[1]
    val trackFr = tracks[2]

    // 1. Initial state (no selection, no applied): action for trackEs is Select
    val selectAction = map.selectionAction(trackEs.id, null, null)
    assertTrue(selectAction is AudioTrackSelectionAction.Select)
    assertEquals(trackEs.id, (selectAction as AudioTrackSelectionAction.Select).entry.id)
    assertEquals("es (Spanish)", selectAction.entry.selectionKey)

    // 2. Pending selection confirmation: once confirmed/applied, requesting the same track produces None
    val appliedAction = map.selectionAction(trackEs.id, trackEs.id, trackEs.selectionKey)
    assertEquals(AudioTrackSelectionAction.None, appliedAction)

    // 3. Switching to another valid track (trackFr) produces Select(trackFr)
    val switchAction = map.selectionAction(trackFr.id, trackEs.id, trackEs.selectionKey)
    assertTrue(switchAction is AudioTrackSelectionAction.Select)
    assertEquals(trackFr.id, (switchAction as AudioTrackSelectionAction.Select).entry.id)

    // 4. Clear: requesting null or empty when a track is applied returns Clear
    assertEquals(
      AudioTrackSelectionAction.Clear,
      map.selectionAction(null, trackEs.id, trackEs.selectionKey),
    )
    assertEquals(
      AudioTrackSelectionAction.Clear,
      map.selectionAction("", trackEs.id, trackEs.selectionKey),
    )

    // 5. Clear when nothing is applied returns None
    assertEquals(
      AudioTrackSelectionAction.None,
      map.selectionAction(null, null, null),
    )
    assertEquals(
      AudioTrackSelectionAction.None,
      map.selectionAction("", null, null),
    )

    // 6. Stale / invalid ID rejection: requesting an unknown ID when a track is applied returns Clear
    assertEquals(
      AudioTrackSelectionAction.Clear,
      map.selectionAction("stale-or-invalid-id", trackEs.id, trackEs.selectionKey),
    )

    // 7. Source reset increments generation: old track IDs become stale on the new generation
    val oldTrackId = trackEs.id
    map.reset()
    map.replace(listOf("en (Main)", "es (Spanish)"))
    val newTracks = map.all()
    val newTrackEs = newTracks[1]

    assertNotEquals(oldTrackId, newTrackEs.id)
    assertEquals(
      AudioTrackSelectionAction.Clear,
      map.selectionAction(oldTrackId, null, null),
    )
  }
}
