package com.brightcove.reactnativeplayer.ads

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AdsFeatureTest {
  @Test
  fun exportsAllAdEventNames() {
    val feature = AdsFeature()
    val events = feature.exportedEvents

    assertEquals("onAdStarted", events["topAdStarted"])
    assertEquals("onAdCompleted", events["topAdCompleted"])
    assertEquals("onAdBreakStarted", events["topAdBreakStarted"])
    assertEquals("onAdBreakEnded", events["topAdBreakEnded"])
    assertEquals("onAllAdsCompleted", events["topAllAdsCompleted"])
    assertEquals("onAdError", events["topAdError"])
    assertEquals("onAdPaused", events["topAdPaused"])
    assertEquals("onAdResumed", events["topAdResumed"])
    assertEquals("onAdProgress", events["topAdProgress"])
    assertEquals("onAdQuartile", events["topAdQuartile"])
    assertEquals("onAdSkipped", events["topAdSkipped"])
    assertEquals("onAdInteraction", events["topAdInteraction"])
    assertEquals("onAdMetadata", events["topAdMetadata"])
    assertEquals("onAdOverlayStateChanged", events["topAdOverlayStateChanged"])
  }

  @Test
  fun ownsAdTagUrlProp() {
    val feature = AdsFeature()
    assertEquals(setOf("adTagUrl"), feature.ownedProps)
  }

  @Test
  fun convertsAdTimeMillisecondsToSeconds() {
    val posMs = 15400L
    val durMs = 30000L
    assertEquals(15.4, posMs / 1000.0, 0.001)
    assertEquals(30.0, durMs / 1000.0, 0.001)
  }
}
