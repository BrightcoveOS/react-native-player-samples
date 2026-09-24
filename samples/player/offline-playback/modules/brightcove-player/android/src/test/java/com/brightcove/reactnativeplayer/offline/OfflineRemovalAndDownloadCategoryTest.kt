package com.brightcove.reactnativeplayer.offline

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BUG-08 regression: the process-global removal latch must never be poisoned
 * by a module instance that stopped servicing its own removal.
 *
 * OfflinePlaybackActiveSources is process-global, so every test uses its own
 * localId: no test may rely on (or leak into) another test's latch state.
 */
class OfflinePlaybackActiveSourcesTest {
  private class ModuleA
  private class ModuleB

  @Test
  fun beginRemovalBlocksConcurrentBeginAndActiveAcquire() {
    val owner = ModuleA()
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("active-latch-video", owner))
    // A second removal of the same id is rejected while the first is in flight.
    assertFalse(OfflinePlaybackActiveSources.beginRemoval("active-latch-video", ModuleB()))
    // A player cannot acquire a source being removed.
    assertFalse(OfflinePlaybackActiveSources.acquire("active-latch-video"))
  }

  @Test
  fun finishRemovalReleasesTheIdForANewRemoval() {
    val owner = ModuleA()
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("finish-release-video", owner))
    OfflinePlaybackActiveSources.finishRemoval("finish-release-video", owner)
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("finish-release-video", ModuleB()))
  }

  @Test
  fun finishRemovalIsIdempotentAndCannotUnlatchANewRemoval() {
    val owner = ModuleA()
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("idempotent-video", owner))
    OfflinePlaybackActiveSources.finishRemoval("idempotent-video", owner)
    // A new owner took the id; the old owner's late finish must not release it.
    val newOwner = ModuleB()
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("idempotent-video", newOwner))
    OfflinePlaybackActiveSources.finishRemoval("idempotent-video", owner)
    assertFalse(OfflinePlaybackActiveSources.beginRemoval("idempotent-video", owner))
  }

  @Test
  fun invalidateAbandonsOnlyTheInvalidatedModuleRemovals() {
    val ownerA = ModuleA()
    val ownerB = ModuleB()
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("owner-a-video", ownerA))
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("owner-b-video", ownerB))

    OfflinePlaybackActiveSources.abandonRemovalsOwnedBy(ownerA)

    // A's id is free again; B's in-flight removal is untouched.
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("owner-a-video", ownerB))
    assertFalse(OfflinePlaybackActiveSources.beginRemoval("owner-b-video", ownerA))

    // Abandonment is idempotent: re-abandoning ownerA does not touch
    // ownerB's in-flight removals.
    OfflinePlaybackActiveSources.abandonRemovalsOwnedBy(ownerA)
    assertFalse(OfflinePlaybackActiveSources.beginRemoval("owner-b-video", ModuleA()))

    // ownerB finishing releases its id for any future owner.
    OfflinePlaybackActiveSources.finishRemoval("owner-a-video", ownerB)
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("owner-a-video", ModuleA()))
  }

  @Test
  fun beginThenAbandonThenBeginSucceedsForTheSameId() {
    // The poisoning scenario from BUG-08: begin -> abandon/invalidate -> a
    // future module instance must be able to begin again.
    val owner = ModuleA()
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("poison-video", owner))
    OfflinePlaybackActiveSources.abandonRemovalsOwnedBy(owner)
    assertTrue(OfflinePlaybackActiveSources.beginRemoval("poison-video", ModuleA()))
  }
}

/**
 * BUG-23 regression: network-class DownloadStatus reason codes and
 * IOExceptions classify as "network"; storage/unknown reasons and untyped
 * failures stay "unknown", matching iOS's codeForError: categories.
 */
class OfflineDownloadFailureCategoryTest {
  @Test
  fun networkClassReasonCodesAreNetwork() {
    assertTrue(offlineDownloadFailureCategory(null, DOWNLOAD_REASON_PAUSED_WAITING_FOR_NETWORK) == "network")
    assertTrue(offlineDownloadFailureCategory(null, DOWNLOAD_REASON_ERROR_UNHANDLED_HTTP_CODE) == "network")
    assertTrue(offlineDownloadFailureCategory(null, DOWNLOAD_REASON_ERROR_HTTP_DATA_ERROR) == "network")
    assertTrue(offlineDownloadFailureCategory(null, DOWNLOAD_REASON_ERROR_TOO_MANY_REDIRECTS) == "network")
    assertTrue(offlineDownloadFailureCategory(null, DOWNLOAD_REASON_ERROR_CANNOT_RESUME) == "network")
  }

  @Test
  fun storageAndUnknownReasonsStayUnknown() {
    // ERROR_FILE_ERROR / ERROR_INSUFFICIENT_SPACE / ERROR_DEVICE_NOT_FOUND
    // are storage failures, not network failures; reporting them as network
    // would lie to a caller deciding whether a retry can help.
    assertTrue(offlineDownloadFailureCategory(null, 1001) == "unknown")
    assertTrue(offlineDownloadFailureCategory(null, 1006) == "unknown")
    assertTrue(offlineDownloadFailureCategory(null, 1007) == "unknown")
    assertTrue(offlineDownloadFailureCategory(null, 1000) == "unknown")
  }

  @Test
  fun ioExceptionIsNetwork() {
    assertTrue(offlineDownloadFailureCategory(java.io.IOException("offline"), null) == "network")
  }

  @Test
  fun otherThrowablesStayUnknown() {
    assertTrue(offlineDownloadFailureCategory(IllegalStateException("store"), null) == "unknown")
  }

  @Test
  fun noReasonAndNoThrowableIsUnknown() {
    assertTrue(offlineDownloadFailureCategory(null, null) == "unknown")
  }
}
