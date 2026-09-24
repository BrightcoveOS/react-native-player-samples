package com.brightcove.reactnativeplayer.offline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The routing table for local-store operations. A download created by this
 * bridge routes to its remembered account/policy catalog; one with no
 * remembered credentials (an older build's record, or a restored SDK store)
 * must still be operable through the private operational catalog rather than
 * resolving to null and disappearing from JS.
 */
class OfflineCatalogTargetTest {
  private val remembered = mapOf(
    "5702148954001" to BrightcoveOfflinePlaybackModule.OfflineCredentials("123", "policy"),
  )

  @Test
  fun rememberedDownloadRoutesToItsAccountCatalog() {
    val target = resolveOfflineCatalogTarget("5702148954001", remembered)
    assertEquals(
      OfflineCatalogTarget.Account("123", "policy"),
      target,
    )
  }

  @Test
  fun downloadWithoutRememberedCredentialsRoutesToOperational() {
    assertTrue(
      resolveOfflineCatalogTarget("legacy-or-orphan", remembered) is OfflineCatalogTarget.Operational,
    )
  }

  @Test
  fun emptyCredentialsMapStillResolvesEveryIdToOperational() {
    assertTrue(
      resolveOfflineCatalogTarget("anything", emptyMap()) is OfflineCatalogTarget.Operational,
    )
  }
}
