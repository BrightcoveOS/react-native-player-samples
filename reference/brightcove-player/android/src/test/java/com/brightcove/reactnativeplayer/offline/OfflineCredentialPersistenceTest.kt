package com.brightcove.reactnativeplayer.offline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OfflineCredentialPersistenceTest {
  @Test
  fun roundTripsCredentials() {
    val credentials = BrightcoveOfflinePlaybackModule.OfflineCredentials("123", "policy")

    assertEquals(credentials, OfflineCredentialPersistence.decode(OfflineCredentialPersistence.encode(credentials)))
  }

  @Test
  fun rejectsMalformedCredentials() {
    assertNull(OfflineCredentialPersistence.decode("123"))
    assertNull(OfflineCredentialPersistence.decode("\u001fpolicy"))
  }
}
