package com.brightcove.reactnativeplayer.offline

import com.brightcove.player.edge.Catalog
import com.brightcove.player.edge.CatalogError
import com.brightcove.player.edge.OfflineCallback
import com.brightcove.player.edge.OfflineCatalog
import com.brightcove.player.event.EventEmitterImpl
import com.brightcove.player.model.Video
import com.brightcove.player.network.DownloadStatus
import com.brightcove.player.offline.MediaDownloadable
import com.brightcove.reactnativeplayer.NativeBrightcoveOfflinePlaybackSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.module.annotations.ReactModule
import java.time.Instant

/**
 * App-scoped TurboModule around Brightcove's persistent OfflineCatalog store.
 * It intentionally owns download state instead of any player view: downloads
 * survive view unmounts and the SDK restores persisted records when this
 * module is recreated after an app process restart.
 */
@ReactModule(name = BrightcoveOfflinePlaybackModule.NAME)
class BrightcoveOfflinePlaybackModule(
  reactContext: ReactApplicationContext,
) : NativeBrightcoveOfflinePlaybackSpec(reactContext), MediaDownloadable.DownloadEventListener {
  private val appContext = reactContext.applicationContext
  private val preferences = appContext.getSharedPreferences(PREFERENCES_NAME, 0)
  private val catalogs = mutableMapOf<OfflineCredentials, OfflineCatalog>()
  private val downloadCredentials = loadDownloadCredentials()
  private var operationalCatalog: OfflineCatalog? = null

  @Synchronized
  private fun catalogFor(accountId: String, policyKey: String): OfflineCatalog {
    val credentials = OfflineCredentials(accountId, policyKey)
    return catalogs.getOrPut(credentials) { createCatalog(accountId, policyKey) }
  }

  @Synchronized
  private fun operationalCatalog(): OfflineCatalog = operationalCatalog
    ?: createCatalog(OPERATIONAL_ACCOUNT_ID, OPERATIONAL_POLICY_KEY)
      .also { operationalCatalog = it }

  @Synchronized
  private fun catalogForDownload(localId: String): OfflineCatalog =
    when (val target = resolveOfflineCatalogTarget(localId, downloadCredentials)) {
      is OfflineCatalogTarget.Account -> catalogFor(target.accountId, target.policyKey)
      OfflineCatalogTarget.Operational -> operationalCatalog()
    }

  override fun requestDownload(
    accountId: String,
    policyKey: String,
    videoId: String,
    promise: Promise,
  ) {
    if (accountId.isBlank() || policyKey.isBlank() || videoId.isBlank()) {
      promise.reject(
        "invalid_configuration",
        "accountId, policyKey, and videoId are required to request an offline download",
      )
      return
    }
    if (!accountId.all(Char::isDigit) || !videoId.all(Char::isDigit)) {
      promise.reject(
        "invalid_configuration",
        "accountId and videoId must contain only digits",
      )
      return
    }

    // Resolve with the regular Catalog — the same public Playback API path the
    // player view uses and the SDK supports for account/policy lookup. The
    // OfflineCatalog owns persisted request/store operations below; using it to
    // resolve an online asset returns its internal "No JSON" failure for this
    // SDK version despite a valid Playback API response.
    val catalog = Catalog.Builder(EventEmitterImpl(), accountId)
      .setPolicy(policyKey)
      .build()
    val offlineCatalog = catalogFor(accountId, policyKey)
    catalog.findVideoByID(videoId, object : com.brightcove.player.edge.VideoListener() {
      override fun onVideo(video: Video) {
        if (!video.isOfflinePlaybackAllowed) {
          promise.reject(
            "not_playable",
            "This video is not eligible for Android offline playback (it requires an offline-enabled DASH source)",
          )
          return
        }
        if (!rememberDownloadCredentials(video.id, accountId, policyKey)) {
          promise.reject(
            "invalid_configuration",
            "videoId '${video.id}' is already downloaded under a different account or policy; remove it before downloading it again",
          )
          return
        }
        offlineCatalog.downloadVideo(video, object : OfflineCallback<DownloadStatus?> {
          override fun onSuccess(status: DownloadStatus?) {
            if (status?.code == DownloadStatus.STATUS_NOT_QUEUED &&
              status.reason != DownloadStatus.ERROR_NONE) {
              promise.reject(
                "unknown",
                "The SDK could not queue the offline download (download_status:${status.code}:${status.reason})",
              )
              return
            }
            promise.resolve(downloadMap(video, status))
          }

          override fun onFailure(throwable: Throwable) {
            promise.reject(
              operationErrorCategory(throwable),
              throwable.localizedMessage ?: "Unable to queue the offline download",
              throwable,
            )
          }
        })
      }

      override fun onError(errors: List<CatalogError>) {
        val error = errors.firstOrNull()
        promise.reject(
          catalogErrorCategory(error),
          error?.message?.ifBlank { null } ?: "Unable to retrieve the video for offline download",
          error?.throwable,
        )
      }
    })
  }

  override fun listDownloads(promise: Promise) {
    // OfflineStoreManager is one app-scoped store keyed by videoId;
    // findAllQueuedVideoDownload() is store-global and does not use the
    // catalog's account/policy. Enumerate through the private operational
    // catalog so the SDK store — not our credentials preferences — remains the
    // source of truth. This keeps older/restored downloads visible even when
    // no SharedPreferences routing hint exists for them.
    val catalog = operationalCatalog()
    catalog.findAllQueuedVideoDownload(object : OfflineCallback<List<Video>> {
      override fun onSuccess(videos: List<Video>) {
        if (videos.isEmpty()) {
          promise.resolve(Arguments.createArray())
          return
        }

        val lock = Any()
        val result = Arguments.createArray()
        var remainingVideos = videos.size
        videos.forEach { video ->
          catalog.getVideoDownloadStatus(video.id, object : OfflineCallback<DownloadStatus?> {
            fun append(map: WritableMap) {
              val shouldResolve = synchronized(lock) {
                result.pushMap(map)
                remainingVideos -= 1
                remainingVideos == 0
              }
              if (shouldResolve) promise.resolve(result)
            }

            override fun onSuccess(status: DownloadStatus?) {
              append(downloadMap(video, status))
            }

            override fun onFailure(throwable: Throwable) {
              // One corrupted/stale record must not hide every other persisted
              // download. Surface an honest failed row and let the caller
              // remove/retry it rather than rejecting the whole list.
              append(downloadMap(video, status = null, throwable = throwable))
            }
          })
        }
      }

      override fun onFailure(throwable: Throwable) {
        promise.reject(
          operationErrorCategory(throwable),
          throwable.localizedMessage ?: "Unable to list persisted downloads",
          throwable,
        )
      }
    })
  }

  override fun pauseDownload(localId: String, promise: Promise) {
    catalogForDownload(localId).pauseVideoDownload(localId, completion(promise))
  }

  override fun resumeDownload(localId: String, promise: Promise) {
    catalogForDownload(localId).resumeVideoDownload(localId, completion(promise))
  }

  override fun cancelDownload(localId: String, promise: Promise) {
    catalogForDownload(localId).cancelVideoDownload(localId, booleanCompletion(promise))
  }

  override fun removeDownload(localId: String, promise: Promise) {
    if (!OfflinePlaybackActiveSources.beginRemoval(localId, this)) {
      promise.reject(
        "active_offline_source",
        "Switch the player to another source before removing its active offline download",
      )
      return
    }
    val catalog = catalogForDownload(localId)
    try {
      catalog.deleteVideo(localId, object : OfflineCallback<Boolean> {
        override fun onSuccess(result: Boolean) {
          OfflinePlaybackActiveSources.finishRemoval(localId, this@BrightcoveOfflinePlaybackModule)
          if (!result) {
            promise.reject("not_found", "No persisted download exists for localId '$localId'")
            return
          }
          // The download is gone, so its remembered credentials serve no
          // further routing/analytics purpose. Prune them now; the SDK store
          // remains the source of truth for listing and existence.
          forgetDownloadCredentials(localId)
          promise.resolve(null)
        }

        override fun onFailure(throwable: Throwable) {
          OfflinePlaybackActiveSources.finishRemoval(localId, this@BrightcoveOfflinePlaybackModule)
          promise.reject(
            operationErrorCategory(throwable),
            throwable.localizedMessage ?: "Unable to remove the persisted download",
            throwable,
          )
        }
      })
    } catch (throwable: Throwable) {
      // deleteVideo threw synchronously (invalid localId shape, store not
      // ready): the callback never runs, so release the latch here or the id
      // stays permanently blocked for every future removal.
      OfflinePlaybackActiveSources.finishRemoval(localId, this)
      promise.reject(
        operationErrorCategory(throwable),
        throwable.localizedMessage ?: "Unable to remove the persisted download",
        throwable,
      )
    }
  }

  override fun onDownloadRequested(video: Video) {
    emitOnOfflineDownloadChanged(downloadMap(video, status = null, state = "queued"))
  }

  @Synchronized
  private fun rememberDownloadCredentials(videoId: String, accountId: String, policyKey: String): Boolean {
    val credentials = OfflineCredentials(accountId, policyKey)
    val existing = downloadCredentials[videoId]
    // The store is keyed by videoId, so two accounts cannot each own a
    // download of the same id in one app: the second would silently inherit
    // the first's catalog for pause/resume/remove (last writer wins). Refuse
    // the conflicting request loudly rather than routing operations to the
    // wrong account's catalog.
    if (existing != null && existing != credentials) {
      return false
    }
    downloadCredentials[videoId] = credentials
    preferences.edit().putString(CREDENTIAL_KEY_PREFIX + videoId, OfflineCredentialPersistence.encode(credentials)).apply()
    return true
  }

  @Synchronized
  private fun forgetDownloadCredentials(videoId: String) {
    downloadCredentials.remove(videoId)
    preferences.edit().remove(CREDENTIAL_KEY_PREFIX + videoId).apply()
  }

  private fun loadDownloadCredentials(): MutableMap<String, OfflineCredentials> {
    val result = mutableMapOf<String, OfflineCredentials>()
    preferences.all.forEach { (key, value) ->
      if (!key.startsWith(CREDENTIAL_KEY_PREFIX) || value !is String) return@forEach
      OfflineCredentialPersistence.decode(value)?.let {
        result[key.removePrefix(CREDENTIAL_KEY_PREFIX)] = it
      }
    }
    return result
  }

  override fun onDownloadStarted(
    video: Video,
    estimatedSize: Long,
    mediaProperties: Map<String, java.io.Serializable>,
  ) {
    emitOnOfflineDownloadChanged(
      downloadMap(video, status = null, state = "downloading", totalBytes = estimatedSize),
    )
  }

  override fun onDownloadProgress(video: Video, status: DownloadStatus) {
    emitOnOfflineDownloadChanged(downloadMap(video, status))
  }

  override fun onDownloadPaused(video: Video, status: DownloadStatus) {
    emitOnOfflineDownloadChanged(downloadMap(video, status))
  }

  override fun onDownloadCompleted(video: Video, status: DownloadStatus) {
    emitOnOfflineDownloadChanged(downloadMap(video, status))
  }

  override fun onDownloadCanceled(video: Video) {
    emitOnOfflineDownloadChanged(downloadMap(video, status = null, state = "cancelled"))
  }

  override fun onDownloadDeleted(video: Video) {
    // The SDK's deletion is authoritative and covers every path: our own
    // removeDownload (whose callback prunes too, idempotently), a license
    // expiry, or an external delete. Prune here as well or a deleted video
    // keeps its credentials forever, which wrongly blocks a later download of
    // the same id under a different account and keeps knownCatalogs() querying
    // an account with nothing left to download.
    forgetDownloadCredentials(video.id)
    emitOnOfflineDownloadChanged(removedDownloadMap(video.id))
  }

  override fun onDownloadFailed(video: Video, status: DownloadStatus) {
    emitOnOfflineDownloadChanged(downloadMap(video, status, state = "failed"))
  }

  override fun invalidate() {
    // Release this module's in-flight removals before tearing down its
    // catalogs: without the abandonment, an id whose delete callback never
    // arrived stays latched forever for every future module instance.
    OfflinePlaybackActiveSources.abandonRemovalsOwnedBy(this)
    val owned = synchronized(this) {
      val all = catalogs.values.toMutableList()
      operationalCatalog?.let(all::add)
      all
    }
    owned.forEach {
      it.removeDownloadEventListener(this)
      it.terminate()
    }
    synchronized(this) {
      catalogs.clear()
      operationalCatalog = null
      downloadCredentials.clear()
    }
    super.invalidate()
  }

  private fun createCatalog(accountId: String, policyKey: String): OfflineCatalog =
    OfflineCatalog.Builder(appContext, EventEmitterImpl(), accountId)
      .setPolicy(policyKey)
      .build()
      .also { catalog -> catalog.addDownloadEventListener(this) }

  private fun completion(promise: Promise): OfflineCallback<Int> = object : OfflineCallback<Int> {
    override fun onSuccess(result: Int) {
      if (result == DownloadStatus.STATUS_NOT_QUEUED) {
        promise.reject("not_found", "No persisted download exists for this localId")
      } else {
        promise.resolve(null)
      }
    }

    override fun onFailure(throwable: Throwable) {
      promise.reject(
        operationErrorCategory(throwable),
        throwable.localizedMessage ?: "Unable to update the persisted download",
        throwable,
      )
    }
  }

  private fun booleanCompletion(promise: Promise): OfflineCallback<Boolean> = object : OfflineCallback<Boolean> {
    override fun onSuccess(result: Boolean) {
      if (!result) {
        promise.reject("not_found", "No persisted download exists for this localId")
      } else {
        promise.resolve(null)
      }
    }

    override fun onFailure(throwable: Throwable) {
      promise.reject(
        operationErrorCategory(throwable),
        throwable.localizedMessage ?: "Unable to update the persisted download",
        throwable,
      )
    }
  }

  private fun downloadMap(
    video: Video,
    status: DownloadStatus?,
    state: String? = null,
    totalBytes: Long? = null,
    throwable: Throwable? = null,
  ): WritableMap = Arguments.createMap().apply {
    // A status lookup that failed (throwable, status == null) is not "queued":
    // the download's real state is unknown, and reporting queued makes a broken
    // download look healthy to a caller keying on `state`. Report the honest
    // failed state so `code`/`message` and `state` agree.
    val resolvedState = state ?: status?.let(::stateFor) ?: if (throwable != null) "failed" else "queued"
    val progress = status?.progress ?: Double.NaN
    val resolvedTotal = totalBytes ?: status?.maxSize ?: 0L
    putString("localId", video.id)
    putString("videoId", video.id)
    putString("state", resolvedState)
    putDouble("progress", if (progress.isFinite()) progress else -1.0)
    putDouble("bytesDownloaded", (status?.bytesDownloaded ?: 0L).toDouble())
    putDouble("totalBytes", if (resolvedTotal > 0L) resolvedTotal.toDouble() else -1.0)
    putString("licenseExpiresAt", video.licenseExpiryDate?.let { Instant.ofEpochMilli(it.time).toString() } ?: "")
    if (throwable != null || resolvedState == "failed") {
      putString("code", offlineDownloadFailureCategory(throwable, status?.reason))
      putString("message", throwable?.localizedMessage ?: "The offline download failed")
      putString(
        "nativeCode",
        throwable?.javaClass?.simpleName ?: "download_status:${status?.code}:${status?.reason}",
      )
    } else {
      putString("code", "")
      putString("message", "")
      putString("nativeCode", "")
    }
  }

  private fun removedDownloadMap(localId: String): WritableMap = Arguments.createMap().apply {
    putString("localId", localId)
    putString("videoId", localId)
    putString("state", "removed")
    putDouble("progress", -1.0)
    putDouble("bytesDownloaded", 0.0)
    putDouble("totalBytes", -1.0)
    putString("licenseExpiresAt", "")
    putString("code", "")
    putString("message", "")
    putString("nativeCode", "")
  }

  private fun stateFor(status: DownloadStatus): String = when (status.code) {
    DownloadStatus.STATUS_QUEUEING,
    DownloadStatus.STATUS_PENDING,
    DownloadStatus.STATUS_RETRY,
    DownloadStatus.STATUS_NOT_QUEUED -> "queued"
    DownloadStatus.STATUS_DOWNLOADING -> "downloading"
    DownloadStatus.STATUS_PAUSED -> "paused"
    DownloadStatus.STATUS_COMPLETE -> "completed"
    DownloadStatus.STATUS_FAILED -> "failed"
    DownloadStatus.STATUS_CANCELLING -> "cancelling"
    DownloadStatus.STATUS_DELETING -> "deleting"
    else -> "failed"
  }

  private fun catalogErrorCategory(error: CatalogError?): String {
    val catalogCode = error?.catalogErrorCode?.ifBlank { null }
    return when {
      catalogCode?.contains("NOT_FOUND", ignoreCase = true) == true -> "not_found"
      catalogCode?.contains("NOT_PLAYABLE", ignoreCase = true) == true -> "not_playable"
      catalogCode?.contains("NETWORK", ignoreCase = true) == true ||
        catalogCode?.contains("TIMEOUT", ignoreCase = true) == true -> "network"
      error?.throwable is java.io.IOException -> "network"
      else -> "unknown"
    }
  }

  private fun operationErrorCategory(throwable: Throwable): String =
    if (throwable is java.io.IOException) "network" else "unknown"

  internal data class OfflineCredentials(
    val accountId: String,
    val policyKey: String,
  )

  companion object {
    const val NAME = "BrightcoveOfflinePlayback"
    private const val PREFERENCES_NAME = "brightcove_offline_credentials"
    private const val CREDENTIAL_KEY_PREFIX = "download:"
    // This catalog is private to local OfflineStoreManager operations. The SDK
    // constructors require non-null account/policy strings, but the string-
    // keyed local operations never consult them (they resolve by videoId in the
    // app-scoped store). Never use this catalog for Playback API or license
    // requests.
    private const val OPERATIONAL_ACCOUNT_ID = ""
    private const val OPERATIONAL_POLICY_KEY = ""
  }
}

internal object OfflineCredentialPersistence {
  private const val SEPARATOR = "\u001f"

  fun encode(credentials: BrightcoveOfflinePlaybackModule.OfflineCredentials): String {
    return credentials.accountId + SEPARATOR + credentials.policyKey
  }

  fun decode(value: String): BrightcoveOfflinePlaybackModule.OfflineCredentials? {
    val parts = value.split(SEPARATOR, limit = 2)
    if (parts.size != 2 || parts[0].isBlank() || parts[1].isBlank()) return null
    return BrightcoveOfflinePlaybackModule.OfflineCredentials(parts[0], parts[1])
  }
}
