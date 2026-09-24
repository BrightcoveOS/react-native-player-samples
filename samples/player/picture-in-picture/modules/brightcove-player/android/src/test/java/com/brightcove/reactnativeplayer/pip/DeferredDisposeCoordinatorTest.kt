package com.brightcove.reactnativeplayer.pip

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeferredDisposeCoordinatorTest {
  @Test
  fun `defers core disposal until after the posted SDK finalizer`() {
    val coordinator = DeferredDisposeCoordinator()
    val posted = mutableListOf<() -> Unit>()
    val callbacks = mutableListOf<String>()

    assertTrue(coordinator.defer())
    coordinator.completeAfterSystemExit(
      postToMain = { posted.add(it) },
      finalizeSdkRegistration = { callbacks.add("sdk") },
      completeCoreDispose = { callbacks.add("core") },
    )

    assertEquals(emptyList<String>(), callbacks)
    assertEquals(1, posted.size)

    posted.single().invoke()

    assertEquals(listOf("sdk", "core"), callbacks)
  }

  @Test
  fun `finalizes a deferred dispose at most once`() {
    val coordinator = DeferredDisposeCoordinator()
    val posted = mutableListOf<() -> Unit>()

    assertTrue(coordinator.defer())
    assertFalse(coordinator.defer())

    repeat(2) {
      coordinator.completeAfterSystemExit(
        postToMain = { posted.add(it) },
        finalizeSdkRegistration = {},
        completeCoreDispose = {},
      )
    }

    assertEquals(1, posted.size)
  }
}
