package com.brightcove.reactnativeplayer.background

internal data class OwnershipTransition<T>(
  val previous: T?,
  val next: T?,
)

internal class NotificationOwnershipState<T> {
  private var owner: T? = null
  private val waiters = LinkedHashSet<T>()
  // Features displaced by promoteIfOwnerPaused: they held the notification
  // legitimately and lost it only because they paused, so a resumed displaced
  // owner re-acquires over the promoted owner. A fresh acquirer waits behind
  // a current eligible owner either way.
  private val resumable = LinkedHashSet<T>()

  fun acquire(feature: T, isEligible: (T) -> Boolean): OwnershipTransition<T>? {
    waiters.remove(feature)
    if (owner === feature) return null
    val displaces = feature in resumable || owner == null || !isEligible(owner as T)
    if (isEligible(feature) && displaces) {
      resumable.remove(feature)
      val previous = owner
      owner = feature
      return OwnershipTransition(previous, feature)
    }
    waiters += feature
    return null
  }

  fun release(feature: T, isEligible: (T) -> Boolean): OwnershipTransition<T>? {
    waiters.remove(feature)
    resumable.remove(feature)
    if (owner !== feature) return null
    owner = null
    val next = waiters.firstOrNull(isEligible)
    if (next != null) waiters.remove(next)
    owner = next
    return OwnershipTransition(feature, next)
  }

  fun promoteIfOwnerPaused(feature: T, isEligible: (T) -> Boolean): OwnershipTransition<T>? {
    if (owner !== feature) return null
    val next = waiters.firstOrNull(isEligible) ?: return null
    waiters.remove(next)
    owner = next
    resumable += feature
    return OwnershipTransition(feature, next)
  }

  fun currentOwner(): T? = owner
}
