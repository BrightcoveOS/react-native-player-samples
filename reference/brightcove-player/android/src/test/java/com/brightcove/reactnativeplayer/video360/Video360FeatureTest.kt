package com.brightcove.reactnativeplayer.video360

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class Video360FeatureTest {
  @Test
  fun ownedPropsAndExportedEventsAreCorrect() {
    val feature = Video360Feature()
    assertEquals(setOf("vrMode"), feature.ownedProps)
    assertTrue(feature.exportedEvents.containsKey("topProjectionFormatChanged"))
    assertTrue(feature.exportedEvents.containsKey("topVideo360ModeChanged"))
  }

  @Test
  fun setPropRejectsUnknownProps() {
    val feature = Video360Feature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("unknownProp", true)
    }
  }

  @Test
  fun vrModeRejectsNonBoolean() {
    val feature = Video360Feature()
    assertThrows(IllegalStateException::class.java) {
      feature.setProp("vrMode", "true")
    }
  }

  // setProp before attach() must not crash: host is nil until attach, and
  // applyVrMode()/every emit* helper must no-op rather than NPE.
  @Test
  fun setPropIsSafeBeforeAttach() {
    val feature = Video360Feature()
    feature.setProp("vrMode", true)
    feature.setProp("vrMode", false)
  }

  @Test
  fun onSourceResetIsSafeBeforeAttach() {
    val feature = Video360Feature()
    feature.onSourceReset()
  }

  @Test
  fun onDisposeIsSafeWithoutAttach() {
    val feature = Video360Feature()
    feature.onDispose()
    // Should be safe to call multiple times without throwing
    feature.onDispose()
  }
}
