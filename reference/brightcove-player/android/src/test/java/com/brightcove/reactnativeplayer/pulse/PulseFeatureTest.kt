package com.brightcove.reactnativeplayer.pulse

import org.junit.Assert.assertEquals
import org.junit.Test

class PulseFeatureTest {
  @Test
  fun parsesCommaSeparatedPositions() {
    assertEquals(listOf(15f, 60.5f), parsePulseMidrollPositions("15, 60.5"))
  }

  @Test(expected = IllegalArgumentException::class)
  fun rejectsInvalidPositions() {
    parsePulseMidrollPositions("15,not-a-number")
  }
}
