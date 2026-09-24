package com.brightcove.reactnativeplayer.lifecycle

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackLifecycleFeatureTest {
  @Test
  fun emitsOnlyPositiveDimensionChanges() {
    assertTrue(shouldEmitVideoSize(1920, 1080, 0, 0))
    assertTrue(shouldEmitVideoSize(1280, 720, 1920, 1080))
    assertFalse(shouldEmitVideoSize(1920, 1080, 1920, 1080))
    assertFalse(shouldEmitVideoSize(0, 1080, 0, 0))
    assertFalse(shouldEmitVideoSize(1920, 0, 0, 0))
  }
}
