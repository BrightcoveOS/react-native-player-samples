package com.brightcove.reactnativeplayer.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers the two-phase source-reset contract enforced by commitConfiguration.
 *
 * The regression this guards: a feature-owned source prop (offlineSourceId
 * A -> B) arms the reset while feature props are applied, after the pre-apply
 * take already ran. Without a post-apply take the debt survived the commit and
 * fired against the next, already-playing source on an unrelated prop update:
 * the outgoing offline download's refcount leaked (its removal was rejected as
 * active_offline_source) and the incoming, playing source's refcount was
 * dropped mid-playback.
 */
class SourceResetSchedulerTest {
  @Test
  fun isIdleAtRest() {
    val scheduler = SourceResetScheduler()
    assertFalse(scheduler.takePending()) // before feature props
    assertFalse(scheduler.takePending()) // after feature props
  }

  @Test
  fun initialSourceIsPendingOnConstruction() {
    val scheduler = SourceResetScheduler(initiallyPending = true)
    assertTrue(scheduler.takePending())
    assertFalse(scheduler.takePending())
  }

  @Test
  fun coreSourcePropFiresBeforeFeatureProps() {
    val scheduler = SourceResetScheduler()
    scheduler.markPending()
    assertTrue(scheduler.takePending())
    assertFalse(scheduler.takePending())
  }

  @Test
  fun featureSourcePropFiresAfterFeaturePropsInTheSameTransaction() {
    val scheduler = SourceResetScheduler()
    assertFalse(scheduler.takePending()) // nothing armed at setter time
    scheduler.markPending() // offlineSourceId setProp -> requestSourceReload
    assertTrue(scheduler.takePending()) // must flush in THIS transaction
    assertFalse(scheduler.takePending())
  }

  @Test
  fun bothSourcePathsFireOnceEach() {
    val scheduler = SourceResetScheduler()
    scheduler.markPending() // accountId core prop
    assertTrue(scheduler.takePending())
    scheduler.markPending() // offlineSourceId feature prop
    assertTrue(scheduler.takePending())
    assertFalse(scheduler.takePending())
  }

  @Test
  fun aSecondMarkWhileAlreadyPendingDoesNotDoubleFire() {
    // Mirrors markSourceDirty's early return when the source is already dirty.
    val scheduler = SourceResetScheduler()
    scheduler.markPending()
    scheduler.markPending()
    assertTrue(scheduler.takePending())
    assertFalse(scheduler.takePending())
  }

  @Test
  fun doesNotLeakAResetIntoTheNextTransaction() {
    val scheduler = SourceResetScheduler()
    scheduler.markPending()
    assertTrue(scheduler.takePending())
    scheduler.markPending()
    assertTrue(scheduler.takePending()) // the offlining commit flushes it
    assertFalse(scheduler.takePending()) // next commit starts clean
  }
}
