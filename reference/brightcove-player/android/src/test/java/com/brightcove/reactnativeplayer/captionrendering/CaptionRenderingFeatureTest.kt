package com.brightcove.reactnativeplayer.captionrendering

import androidx.media3.common.text.Cue
import org.junit.Assert.assertEquals
import org.junit.Test

class CaptionRenderingFeatureTest {
  @Test
  fun emptyCueListFormatsAsEmptyString() {
    assertEquals("", formatCueText(emptyList()))
  }

  @Test
  fun formatsSingleAndMultipleCueTextsWithNewlines() {
    val cue1 = Cue.Builder().setText("First line").build()
    val cue2 = Cue.Builder().setText("Second line").build()
    assertEquals("First line", formatCueText(listOf(cue1)))
    assertEquals("First line\nSecond line", formatCueText(listOf(cue1, cue2)))
  }
}
