package com.brightcove.reactnativeplayer.quality

import androidx.media3.common.Format
import org.junit.Assert.assertEquals
import org.junit.Test

class QualityFeatureTest {
  @Test
  fun normalizesUnknownRenditionValues() {
    assertEquals(0, knownQualityInt(Format.NO_VALUE))
    assertEquals(0, knownQualityInt(-1))
    assertEquals(1_500_000, knownQualityInt(1_500_000))
    assertEquals(0.0, knownQualityFrameRate(Format.NO_VALUE.toFloat()), 0.0)
    assertEquals(30.0, knownQualityFrameRate(30f), 0.0)
  }
}
