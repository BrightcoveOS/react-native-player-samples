package com.brightcove.reactnativeplayer.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlayerCommandValidationTest {
  @Test
  fun acceptsFiniteNonNegativeSeekPositions() {
    assertNull(seekPositionError(0.0))
    assertNull(seekPositionError(30.25))
  }

  @Test
  fun rejectsNonFiniteSeekPositions() {
    assertEquals("positionSeconds must be finite", seekPositionError(Double.NaN))
    assertEquals("positionSeconds must be finite", seekPositionError(Double.POSITIVE_INFINITY))
  }

  @Test
  fun rejectsNegativeSeekPositions() {
    assertEquals("positionSeconds must be non-negative", seekPositionError(-0.001))
  }
}
