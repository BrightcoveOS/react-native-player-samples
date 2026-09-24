package com.brightcove.reactnativeplayer.cast

import com.google.android.gms.cast.framework.CastState
import org.junit.Assert.assertEquals
import org.junit.Test

class CastFeatureTest {
  @Test
  fun normalizesKnownCastStates() {
    assertEquals("no_devices", CastFeature.normalizedCastState(CastState.NO_DEVICES_AVAILABLE))
    assertEquals("not_connected", CastFeature.normalizedCastState(CastState.NOT_CONNECTED))
    assertEquals("connecting", CastFeature.normalizedCastState(CastState.CONNECTING))
    assertEquals("connected", CastFeature.normalizedCastState(CastState.CONNECTED))
  }

  @Test
  fun normalizesUnknownCastStates() {
    assertEquals("unknown", CastFeature.normalizedCastState(-1))
  }
}
