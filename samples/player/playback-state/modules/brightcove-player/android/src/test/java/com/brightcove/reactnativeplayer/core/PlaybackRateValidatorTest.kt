package com.brightcove.reactnativeplayer.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackRateValidatorTest {
  @Test
  fun acceptsValidPositiveRates() {
    assertEquals(1.0f, PlaybackRateValidator.validate(1.0))
    assertEquals(0.5f, PlaybackRateValidator.validate(0.5))
    assertEquals(1.5f, PlaybackRateValidator.validate(1.5))
    assertEquals(2.0f, PlaybackRateValidator.validate(2.0))
  }

  @Test
  fun rejectsZeroAndNegativeRates() {
    assertNull(PlaybackRateValidator.validate(0.0))
    assertNull(PlaybackRateValidator.validate(-0.0))
    assertNull(PlaybackRateValidator.validate(-1.0))
    assertNull(PlaybackRateValidator.validate(-0.5))
  }

  @Test
  fun rejectsNaNAndInfinities() {
    assertNull(PlaybackRateValidator.validate(Double.NaN))
    assertNull(PlaybackRateValidator.validate(Double.POSITIVE_INFINITY))
    assertNull(PlaybackRateValidator.validate(Double.NEGATIVE_INFINITY))
  }

  @Test
  fun rejectsValuesExceedingFloatRange() {
    // Value that is finite in Double but overflows Float to Infinity
    assertNull(PlaybackRateValidator.validate(1.0e39))
    // Subnormal / zero when cast to Float
    assertNull(PlaybackRateValidator.validate(0.0))
  }

  @Test
  fun preservesPreviousValidRateOnInvalidInput() {
    var storedRate = 1.0f
    fun updateRate(requested: Double) {
      val valid = PlaybackRateValidator.validate(requested)
      if (valid != null) {
        storedRate = valid
      }
    }

    updateRate(2.0)
    assertEquals(2.0f, storedRate)

    updateRate(0.0)
    assertEquals(2.0f, storedRate)

    updateRate(-1.5)
    assertEquals(2.0f, storedRate)

    updateRate(Double.NaN)
    assertEquals(2.0f, storedRate)

    updateRate(Double.POSITIVE_INFINITY)
    assertEquals(2.0f, storedRate)

    updateRate(0.75)
    assertEquals(0.75f, storedRate)
  }
}
