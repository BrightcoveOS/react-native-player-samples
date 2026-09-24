package com.brightcove.reactnativeplayer.offline

/**
 * App-scoped coordination for the SDK's persistent download store. Deleting a
 * file while a player still owns its local manifest/segments can tear the
 * native player down underneath ExoPlayer, so the module rejects that operation
 * instead of offering a destructive race to JavaScript.
 *
 * Removals are owned by the module instance that began them: when that module
 * is invalidated mid-removal, only its own removals are abandoned — the
 * process-global latch never stays poisoned for a live module's future
 * beginRemoval (the pre-ownership bug: one invalidated module permanently
 * blocked the id for every later instance).
 */
internal object OfflinePlaybackActiveSources {
  private val ownerCounts = mutableMapOf<String, Int>()

  // The module instance that began each removal, so invalidation abandons
  // only its own in-flight removals.
  private val removalOwners = mutableMapOf<String, Any>()

  @Synchronized
  fun acquire(localId: String): Boolean {
    if (localId in removalOwners) return false
    ownerCounts[localId] = (ownerCounts[localId] ?: 0) + 1
    return true
  }

  @Synchronized
  fun remove(localId: String) {
    val remaining = (ownerCounts[localId] ?: return) - 1
    if (remaining == 0) {
      ownerCounts.remove(localId)
    } else {
      ownerCounts[localId] = remaining
    }
  }

  @Synchronized
  fun beginRemoval(localId: String, owner: Any): Boolean {
    if (localId in ownerCounts || localId in removalOwners) return false
    removalOwners[localId] = owner
    return true
  }

  /**
   * End a removal begun by [owner]. Idempotent: a removal already ended (or
   * abandoned by [abandonRemovalsOwnedBy]) is a no-op, so a late callback
   * after cleanup cannot un-latch an id a new removal has since taken.
   */
  @Synchronized
  fun finishRemoval(localId: String, owner: Any) {
    if (removalOwners[localId] === owner) {
      removalOwners.remove(localId)
    }
  }

  /**
   * Invalidate-time cleanup: every removal this owner began is released, so a
   * module invalidated mid-removal never leaves its ids latched. Safe for a
   * repeated call and for a live module's unrelated removals.
   */
  @Synchronized
  fun abandonRemovalsOwnedBy(owner: Any) {
    removalOwners.entries.removeAll { it.value === owner }
  }
}
