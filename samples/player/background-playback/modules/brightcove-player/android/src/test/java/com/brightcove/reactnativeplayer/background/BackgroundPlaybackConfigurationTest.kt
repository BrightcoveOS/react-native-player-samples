package com.brightcove.reactnativeplayer.background

import android.Manifest
import org.junit.Assert.assertEquals
import org.junit.Test

class BackgroundPlaybackConfigurationTest {
  @Test
  fun requiresForegroundServicePermissionOnAllSupportedAndroidVersions() {
    assertEquals(
      setOf(Manifest.permission.FOREGROUND_SERVICE),
      BackgroundPlaybackConfiguration.requiredManifestPermissions(33),
    )
  }

  @Test
  fun requiresMediaPlaybackForegroundServicePermissionOnAndroid14() {
    assertEquals(
      setOf(
        Manifest.permission.FOREGROUND_SERVICE,
        Manifest.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK,
      ),
      BackgroundPlaybackConfiguration.requiredManifestPermissions(34),
    )
  }
}
