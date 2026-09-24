package com.brightcove.reactnativeplayer.audiodescription

import androidx.media3.common.C
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioDescriptionFeatureTest {
  @Test
  fun recognizesTheMedia3DescriptionRole() {
    assertTrue(hasAudioDescriptionRole(C.ROLE_FLAG_DESCRIBES_VIDEO))
    assertTrue(
      hasAudioDescriptionRole(C.ROLE_FLAG_DESCRIBES_VIDEO or C.ROLE_FLAG_COMMENTARY),
    )
    assertFalse(hasAudioDescriptionRole(C.ROLE_FLAG_COMMENTARY))
  }

}
