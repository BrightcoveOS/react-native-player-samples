package com.brightcove.reactnativeplayer.live

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveFeatureTest {
  @Test
  fun extractsTimelineWindowProperties() {
    val event = Event(EventType.VIDEO_DURATION_CHANGED)
    event.properties[Event.MIN_POSITION_LONG] = 120_000L
    event.properties[Event.MAX_POSITION_LONG] = 600_000L

    assertEquals(
      SeekableRangeWindow(120_000L, 600_000L, 600_000L),
      extractSeekableRange(event, 600_000L),
    )
  }

  @Test
  fun clampsLiveEdgeExceedingWindowEnd() {
    val event = Event(EventType.VIDEO_DURATION_CHANGED)
    event.properties[Event.MIN_POSITION_LONG] = 120_000L
    event.properties[Event.MAX_POSITION_LONG] = 600_000L

    // A live-edge value slightly greater than MAX_POSITION_LONG must not invalidate/clear
    // a valid live-DVR window; the reported liveEdge is clamped to the seekable window end.
    assertEquals(
      SeekableRangeWindow(120_000L, 600_000L, 600_000L),
      extractSeekableRange(event, 600_005L),
    )
    assertEquals(
      SeekableRangeWindow(100L, 200L, 200L),
      extractSeekableRange(
        Event(EventType.VIDEO_DURATION_CHANGED).apply {
          properties[Event.MIN_POSITION_LONG] = 100L
          properties[Event.MAX_POSITION_LONG] = 200L
        },
        201L,
      ),
    )
  }

  @Test
  fun rejectsInvalidWindowPropertiesAndEdges() {
    val cases = listOf(
      Triple(100L, 100L, 100L),   // end == start (zero duration)
      Triple(200L, 100L, 200L),   // end < start (inverted)
      Triple(-1L, 100L, 100L),    // negative start
      Triple(100L, 200L, 0L),     // zero liveEdge
      Triple(100L, 200L, -10L),   // negative liveEdge
      Triple(100L, 200L, 99L),    // liveEdge before start
    )

    cases.forEach { (start, end, liveEdge) ->
      val event = Event(EventType.VIDEO_DURATION_CHANGED)
      event.properties[Event.MIN_POSITION_LONG] = start
      event.properties[Event.MAX_POSITION_LONG] = end
      assertNull("Expected null for ($start, $end, $liveEdge)", extractSeekableRange(event, liveEdge))
    }
  }

  @Test
  fun freshEdgeMustRemainInsideStoredWindow() {
    val stored = SeekableRangeWindow(120_000L, 600_000L, 600_000L)

    assertTrue(stored.isValid())
    assertTrue(isValidSeekableRange(stored.start, stored.end, 590_000L))
    assertTrue(isValidSeekableRange(stored.start, stored.end, 600_000L))
    assertTrue(isValidSeekableRange(stored.start, stored.end, 600_001L))
    assertTrue(!isValidSeekableRange(stored.start, stored.end, 119_999L))
    assertTrue(!isValidSeekableRange(stored.start, stored.end, 0L))
    assertTrue(!isValidSeekableRange(stored.start, stored.end, -1L))
  }

  @Test
  fun pausedProgressWithoutBoundsDoesNotRepresentRangeInvalidation() {
    val event = Event(EventType.PROGRESS)
    event.properties[Event.PLAYHEAD_POSITION_LONG] = 480_000L

    assertTrue(!hasSeekableRangeBounds(event))
  }

  @Test
  fun liveFeatureSupportsSeekToLiveEdgeCommand() {
    val feature = LiveFeature()
    assertTrue("seekToLiveEdge" in feature.supportedCommands)
    assertTrue(feature.ownedProps.isEmpty())
  }

  // The seekToLiveEdge guard table is two typed failures: a source that is
  // not live-with-DVR (not_live_dvr) versus a live-DVR source whose seekable
  // window is not populated/valid yet (no_dvr_range_yet) — the same split
  // the iOS feature reports. A caller can tell "wait for ranges" from "this
  // source can never seek to the edge".
  @Test
  fun seekToLiveEdgeClassifiesVodOrPlainLiveAsNotLiveDvr() {
    val feature = LiveFeature()
    assertEquals(
      SeekToLiveEdgeOutcome.NOT_LIVE_DVR,
      feature.seekToLiveEdgeOutcome(isLive = false, hasDvr = false, hasValidRange = false),
    )
    assertEquals(
      SeekToLiveEdgeOutcome.NOT_LIVE_DVR,
      feature.seekToLiveEdgeOutcome(isLive = true, hasDvr = false, hasValidRange = true),
    )
    // No video display at all behaves like a non-live source.
    assertEquals(
      SeekToLiveEdgeOutcome.NOT_LIVE_DVR,
      feature.seekToLiveEdgeOutcome(isLive = false, hasDvr = false, hasValidRange = true),
    )
  }

  @Test
  fun seekToLiveEdgeClassifiesLiveDvrWithoutRangeAsNoDvrRangeYet() {
    val feature = LiveFeature()
    assertEquals(
      SeekToLiveEdgeOutcome.NO_DVR_RANGE_YET,
      feature.seekToLiveEdgeOutcome(isLive = true, hasDvr = true, hasValidRange = false),
    )
  }

  @Test
  fun seekToLiveEdgeSoughtOnlyForLiveDvrWithValidRange() {
    val feature = LiveFeature()
    assertEquals(
      SeekToLiveEdgeOutcome.SOUGHT,
      feature.seekToLiveEdgeOutcome(isLive = true, hasDvr = true, hasValidRange = true),
    )
  }

  @Test
  fun invalidEdgeIsNotReportedAsSuccessful() {
    assertTrue(!isValidSeekableRange(0L, 0L, 0L))
  }
}
