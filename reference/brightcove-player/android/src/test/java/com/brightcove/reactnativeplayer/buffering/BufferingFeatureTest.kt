package com.brightcove.reactnativeplayer.buffering

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Test

class BufferingFeatureTest {
  @Test
  fun initialPreparationDoesNotEmitARebuffer() {
    val events = mutableListOf<String>()
    val tracker = tracker(events)

    tracker.onPlayerSnapshot(Player.STATE_BUFFERING, isPlaying = false, seekInProgress = false)
    tracker.onPrepared()
    tracker.onPlayerSnapshot(Player.STATE_READY, isPlaying = false, seekInProgress = false)

    assertEquals(emptyList<String>(), events)
  }

  @Test
  fun normalPlaybackStallEmitsOnePairedEpisode() {
    val events = mutableListOf<String>()
    val tracker = tracker(events)
    tracker.onPrepared()
    tracker.onPlayerSnapshot(Player.STATE_READY, isPlaying = true, seekInProgress = false)

    tracker.onPlayerSnapshot(Player.STATE_BUFFERING, isPlaying = false, seekInProgress = false)
    tracker.onPlayerSnapshot(Player.STATE_BUFFERING, isPlaying = false, seekInProgress = false)
    tracker.onPlayerSnapshot(Player.STATE_READY, isPlaying = true, seekInProgress = false)

    assertEquals(listOf("start", "end"), events)
  }

  @Test
  fun seekBufferingDoesNotLookLikeARebuffer() {
    val events = mutableListOf<String>()
    val tracker = tracker(events)
    tracker.onPrepared()
    tracker.onPlayerSnapshot(Player.STATE_READY, isPlaying = true, seekInProgress = false)

    tracker.onPlayerSnapshot(Player.STATE_BUFFERING, isPlaying = false, seekInProgress = true)
    tracker.onPlayerSnapshot(Player.STATE_READY, isPlaying = true, seekInProgress = false)

    assertEquals(emptyList<String>(), events)
  }

  @Test
  fun resetClosesAnActiveEpisodeBeforeDiscardingState() {
    val events = mutableListOf<String>()
    val tracker = tracker(events)
    tracker.onPrepared()
    tracker.onPlayerSnapshot(Player.STATE_READY, isPlaying = true, seekInProgress = false)
    tracker.onPlayerSnapshot(Player.STATE_BUFFERING, isPlaying = false, seekInProgress = false)

    tracker.reset()
    tracker.onPrepared()
    tracker.onPlayerSnapshot(Player.STATE_READY, isPlaying = true, seekInProgress = false)
    tracker.onPlayerSnapshot(Player.STATE_BUFFERING, isPlaying = false, seekInProgress = false)
    tracker.finish()

    assertEquals(listOf("start", "end", "start", "end"), events)
  }

  private fun tracker(events: MutableList<String>) = RebufferTracker(
    onStart = { events += "start" },
    onEnd = { events += "end" },
  )
}
