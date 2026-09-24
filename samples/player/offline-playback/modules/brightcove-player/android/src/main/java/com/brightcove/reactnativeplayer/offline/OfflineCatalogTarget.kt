package com.brightcove.reactnativeplayer.offline

/**
 * Chooses which OfflineCatalog instance services a local-store operation.
 *
 * Android's OfflineStoreManager is one app-scoped store keyed by videoId. Its
 * String-based operations (list/status/pause/resume/cancel/delete) resolve from
 * that store and do not use the catalog's account or policy. Credentials are
 * still useful for downloads created by this bridge (event/analytics context),
 * but they must not be a correctness gate: records from an older build or a
 * restored SDK store can legitimately exist without our SharedPreferences
 * entry. Those records use the private operational catalog instead of becoming
 * invisible and undeletable.
 */
internal sealed interface OfflineCatalogTarget {
  data class Account(
    val accountId: String,
    val policyKey: String,
  ) : OfflineCatalogTarget

  data object Operational : OfflineCatalogTarget
}

internal fun resolveOfflineCatalogTarget(
  localId: String,
  remembered: Map<String, BrightcoveOfflinePlaybackModule.OfflineCredentials>,
): OfflineCatalogTarget = remembered[localId]?.let {
  OfflineCatalogTarget.Account(it.accountId, it.policyKey)
} ?: OfflineCatalogTarget.Operational
