package com.brightcove.reactnativeplayer.offline

/**
 * Pure classification of an offline-download failure into the shared
 * cross-platform error-category contract (the same categories iOS's
 * codeForError: reports: network / not_found / unknown).
 *
 * Two failure shapes reach JS: a Throwable from a catalog/store operation
 * (IOException names a network transport failure) and a DownloadStatus
 * reason code from the DownloadManager-backed download (network-class
 * DownloadManager reasons: waiting for network, HTTP transport, redirects,
 * resumption).
 */
internal fun offlineDownloadFailureCategory(
  throwable: Throwable?,
  statusReason: Int?,
): String {
  if (throwable is java.io.IOException) return "network"
  if (statusReason == null) return "unknown"
  return when (statusReason) {
    // DownloadManager network-class reason codes, mirrored from
    // com.brightcove.player.network.DownloadStatus.
    DOWNLOAD_REASON_PAUSED_WAITING_FOR_NETWORK,
    DOWNLOAD_REASON_ERROR_UNHANDLED_HTTP_CODE,
    DOWNLOAD_REASON_ERROR_HTTP_DATA_ERROR,
    DOWNLOAD_REASON_ERROR_TOO_MANY_REDIRECTS,
    DOWNLOAD_REASON_ERROR_CANNOT_RESUME,
    -> "network"
    else -> "unknown"
  }
}

// DownloadStatus constant values (com.brightcove.player.network.DownloadStatus
// mirrors android.app.DownloadManager): extracted here so the classification
// is unit-testable without the SDK's Android-bound classes.
internal const val DOWNLOAD_REASON_PAUSED_WAITING_FOR_NETWORK = 2
internal const val DOWNLOAD_REASON_ERROR_UNHANDLED_HTTP_CODE = 1002
internal const val DOWNLOAD_REASON_ERROR_HTTP_DATA_ERROR = 1004
internal const val DOWNLOAD_REASON_ERROR_TOO_MANY_REDIRECTS = 1005
internal const val DOWNLOAD_REASON_ERROR_CANNOT_RESUME = 1008
