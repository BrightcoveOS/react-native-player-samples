package com.brightcove.reactnativeplayer.preloading

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PreloadingFeatureTest {
  @Test
  fun ownedPropsAreCorrect() {
    val feature = PreloadingFeature()
    assertEquals(setOf("preloadVideoId"), feature.ownedProps)
  }

  @Test
  fun exportsAllThreeLifecycleEvents() {
    val feature = PreloadingFeature()
    assertEquals(
      mapOf(
        "topPreloadQueued" to "onPreloadQueued",
        "topPreloadHandoff" to "onPreloadHandoff",
        "topPreloadError" to "onPreloadError",
      ),
      feature.exportedEvents,
    )
  }

  @Test
  fun rejectsAPropItDoesNotOwn() {
    val feature = PreloadingFeature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("videoId", "5421538222001")
    }
  }
}
