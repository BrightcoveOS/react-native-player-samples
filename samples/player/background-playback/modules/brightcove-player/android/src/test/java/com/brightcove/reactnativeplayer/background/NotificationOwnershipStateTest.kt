package com.brightcove.reactnativeplayer.background

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationOwnershipStateTest {
  @Test
  fun resumedWaiterCanReacquireAfterPromotion() {
    val state = NotificationOwnershipState<String>()
    val eligible: (String) -> Boolean = { true }

    state.acquire("first", eligible)
    state.acquire("second", eligible)
    assertEquals(OwnershipTransition("first", "second"), state.promoteIfOwnerPaused("first", eligible))
    assertEquals(OwnershipTransition("second", "first"), state.acquire("first", eligible))
    assertEquals("first", state.currentOwner())
  }

  @Test
  fun releasePromotesFirstEligibleWaiter() {
    val state = NotificationOwnershipState<String>()
    val eligible: (String) -> Boolean = { it != "paused" }

    state.acquire("first", eligible)
    state.acquire("paused", eligible)
    state.acquire("third", eligible)

    assertEquals(OwnershipTransition("first", "third"), state.release("first", eligible))
    assertNull(state.release("paused", eligible))
  }
}
