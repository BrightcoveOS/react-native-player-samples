package com.brightcove.reactnativeplayer.chapternavigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChapterNavigationFeatureTest {
  @Test
  fun convertsFiniteChapterTimesToMilliseconds() {
    assertEquals(10_000L, chapterSeekPositionMillis(10.0))
    assertEquals(10_500L, chapterSeekPositionMillis(10.5))
  }

  @Test
  fun rejectsInvalidChapterTimes() {
    assertNull(chapterSeekPositionMillis(-1.0))
    assertNull(chapterSeekPositionMillis(Double.NaN))
    assertNull(chapterSeekPositionMillis(Double.POSITIVE_INFINITY))
  }

  // A target beyond the duration must be rejected before seeking: ExoPlayer
  // clamps it, DID_SEEK_TO then reports the clamped position, the tolerance
  // check rejects the confirmation, and the pending-request latch would stay
  // armed forever — silently dropping every later chapter seek.
  @Test
  fun rejectsChapterSeekBeyondKnownDuration() {
    assertEquals(true, chapterSeekTargetIsOutOfRange(120.0, 60.0))
    assertEquals(true, chapterSeekTargetIsOutOfRange(60.6, 60.0))
  }

  @Test
  fun allowsChapterSeekWithinKnownDuration() {
    assertEquals(false, chapterSeekTargetIsOutOfRange(60.0, 60.0))
    assertEquals(false, chapterSeekTargetIsOutOfRange(60.5, 60.0))
    assertEquals(false, chapterSeekTargetIsOutOfRange(0.0, 60.0))
    assertEquals(false, chapterSeekTargetIsOutOfRange(30.0, 60.0))
  }

  // An unknown duration (SDK reported nothing yet, or a live stream) skips
  // validation, matching iOS's non-numeric-duration case.
  @Test
  fun skipsDurationValidationWhenDurationUnknown() {
    assertEquals(false, chapterSeekTargetIsOutOfRange(120.0, null))
    assertEquals(false, chapterSeekTargetIsOutOfRange(120.0, 0.0))
    assertEquals(false, chapterSeekTargetIsOutOfRange(120.0, -1.0))
    assertEquals(false, chapterSeekTargetIsOutOfRange(120.0, Double.NaN))
  }
}
