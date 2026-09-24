package com.brightcove.reactnativeplayer.playlists

import androidx.media3.common.Player
import com.brightcove.player.display.ExoPlayerVideoDisplayComponent
import com.brightcove.player.edge.Catalog
import com.brightcove.player.edge.CatalogError
import com.brightcove.player.edge.VideoListener
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerErrorClassifier
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Loads a Video Cloud queue from the `videoIds` prop instead of a single
 * video. Each ID is resolved from the catalog in order and, once resolved,
 * added to the native SDK's own queue (BrightcoveExoPlayerVideoView.add),
 * which owns normal end-of-item advancement — this feature does not build a
 * playback state machine of its own beyond repeat/shuffle mode, which the
 * native ExoPlayer instance already supports directly.
 *
 * An ID that fails catalog resolution is skipped (never reaches the native
 * queue) and reported through onQueueItemFailed; resolution continues with
 * the next ID. If every ID fails, the queue reports the normalized onError
 * contract like a single-video source would. A failure once an item has
 * already started playing (not a resolution failure) is not handled here —
 * it surfaces through the core's existing onError and is terminal for the
 * queue, matching single-video behavior.
 *
 * `videoIds` itself is core-routed like `offlineSourceId` (see
 * BrightcovePlayerViewManager.setVideoIds): a non-empty array both selects
 * this feature as the current source's loader (claimsSourceLoading) and
 * supplies the queue contents (setProp("videoIds", ...)). repeatMode and
 * shuffle are ordinary feature-owned props.
 */
class PlaylistsFeature : PlayerFeature {
  private var host: FeatureHost? = null

  private data class ResolvedItem(
    val video: Video,
    val originalIndex: Int,
  )

  private var videoIds: List<String> = emptyList()
  private var repeatMode = "off"
  private var shuffle = false

  // Guards against a resolution callback for a superseded configuration
  // (also checked via host.isCurrentRequest, but this additionally guards
  // against a callback arriving after this feature's own onSourceReset for
  // the SAME generation, which cannot happen today but is cheap to assert).
  private var activeRequestGeneration = -1

  private val resolvedItems = mutableListOf<ResolvedItem>()
  private val failedItemCodes = mutableListOf<String>()
  private var currentResolvedIndex = -1
  private var resolutionInProgress = false
  private var pendingAdvance = false
  private val completionState = QueueCompletionState()

  override val ownedProps = setOf("videoIds", "repeatMode", "shuffle")
  override val supportedCommands = setOf("next", "previous")

  override val exportedEvents = mapOf(
    EVENT_QUEUE_ITEM_CHANGED to "onQueueItemChanged",
    EVENT_QUEUE_ITEM_FAILED to "onQueueItemFailed",
    EVENT_QUEUE_COMPLETED to "onQueueCompleted",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "videoIds" -> {
        // Reject a wrong-typed queue loudly rather than coercing to an empty
        // list: emptyList() is indistinguishable from a legitimately empty
        // queue, so the source would silently reload onto the single-video path
        // with no onError / onQueueItemFailed reaching JS. repeatMode and
        // shuffle below use the same fail-loud pattern.
        val raw = value as? List<*>
          ?: error("PlaylistsFeature requires a List for '$name'")
        val ids = raw.map { element ->
          element as? String
            ?: error("PlaylistsFeature requires every '$name' element to be a String, got ${element?.let { it::class.simpleName }}")
        }
        if (videoIds != ids) {
          videoIds = ids
          host?.requestSourceReload()
        }
      }
      "repeatMode" -> {
        val mode = value as? String
          ?: error("PlaylistsFeature requires a String for '$name'")
        require(mode in setOf("off", "one", "all")) {
          "Invalid repeatMode '$mode', expected 'off', 'one', or 'all'"
        }
        repeatMode = mode
        applyRepeatModeToNative()
      }
      "shuffle" -> {
        shuffle = value as? Boolean
          ?: error("PlaylistsFeature requires a Boolean for '$name'")
        applyShuffleToNative()
      }
      else -> error("PlaylistsFeature does not own prop '$name'")
    }
  }

  override fun handleCommand(name: String): Boolean {
    val host = host ?: return false
    return when (name) {
      "next" -> {
        // The command contract is truthful per outcome: a pending advance is
        // a handled request (retried as items resolve), at-end with repeat
        // off is a typed rejection, and a queue that is not loaded for the
        // current request is the typed no-queue rejection.
        when (nextQueueCommandOutcome(
          queueLoaded = hasCurrentQueue(),
          hasNextMediaItem = nativeHasNextMediaItem(),
          resolutionInProgress = resolutionInProgress,
          resolvedCount = resolvedItems.size,
          repeatMode = repeatMode,
        )) {
          QueueCommandOutcome.ADVANCED, QueueCommandOutcome.PENDING -> advanceQueue()
          QueueCommandOutcome.QUEUE_AT_END -> {
            host.emitCommandError(
              command = name,
              code = "invalid_state",
              message = "Cannot advance the queue: the last item is already playing and the repeat mode does not wrap the queue",
              nativeCode = "queue_at_end",
            )
            true
          }
          QueueCommandOutcome.QUEUE_NOT_LOADED -> {
            host.emitCommandError(
              command = name,
              code = "invalid_state",
              message = "Cannot advance the queue: no queue is loaded in this player",
              nativeCode = "queue_not_loaded",
            )
            true
          }
        }
      }
      "previous" -> {
        // Same truthful-contract structure as "next": no loaded queue is the
        // typed no-queue rejection; every queue-loaded case is handled (an
        // at-first previous restarts the current item rather than failing —
        // "at first" is a valid position, unlike next-at-end).
        if (!hasCurrentQueue()) {
          host.emitCommandError(
            command = name,
            code = "invalid_state",
            message = "Cannot go to the previous queue item: no queue is loaded in this player",
            nativeCode = "queue_not_loaded",
          )
          true
        } else {
          previousQueueItem()
        }
      }
      else -> false
    }
  }

  override fun onSourceReset() {
    activeRequestGeneration = -1
    resolvedItems.clear()
    failedItemCodes.clear()
    currentResolvedIndex = -1
    resolutionInProgress = false
    pendingAdvance = false
    completionState.reset()
  }

  override fun onDispose() {
    onSourceReset()
  }

  override fun claimsSourceLoading(): Boolean = videoIds.isNotEmpty()

  override fun loadSource(requestGeneration: Int, accountId: String, policyKey: String) {
    val host = host ?: return
    val ids = videoIds
    if (ids.isEmpty()) {
      host.emitSourceLoadError(
        requestGeneration,
        code = "invalid_configuration",
        nativeCode = "playlist_video_ids_missing",
        message = "videoIds must be non-empty when loading queue playback",
      )
      return
    }

    activeRequestGeneration = requestGeneration
    resolvedItems.clear()
    failedItemCodes.clear()
    currentResolvedIndex = -1
    resolutionInProgress = true
    pendingAdvance = false
    completionState.reset()
    applyRepeatModeToNative()
    applyShuffleToNative()
    val catalog = Catalog.Builder(host.eventEmitter, accountId)
      .setPolicy(policyKey)
      .build()
    resolveNext(catalog, requestGeneration, ids, index = 0)
  }

  override fun advanceQueue(): Boolean {
    val host = host ?: return false
    if (!host.isCurrentRequest(activeRequestGeneration)) return false
    when (
      nextQueueCommandOutcome(
        queueLoaded = true,
        hasNextMediaItem = nativeHasNextMediaItem(),
        resolutionInProgress = resolutionInProgress,
        resolvedCount = resolvedItems.size,
        repeatMode = repeatMode,
      )
    ) {
      QueueCommandOutcome.ADVANCED -> {
        pendingAdvance = false
        val exoPlayer = (host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent)?.exoPlayer
          ?: return false
        if (exoPlayer.hasNextMediaItem()) {
          exoPlayer.seekToNextMediaItem()
        } else {
          val timeline = exoPlayer.currentTimeline
          val firstWindowIndex = if (!timeline.isEmpty) timeline.getFirstWindowIndex(shuffle) else 0
          exoPlayer.seekTo(firstWindowIndex, 0)
        }
        host.videoView.start()
        return true
      }
      // Nothing (yet) to advance to: remember the request; onVideo/resolveNext
      // retry it as soon as another item is queued (see the pendingAdvance
      // call sites), and it is dropped if resolution ends with nothing
      // further resolved. The command contract reports at-end with a typed
      // error only through the imperative `next` command path
      // (handleCommand), never here: this path is also the internal retry
      // for a user request made earlier, which must stay silent.
      QueueCommandOutcome.PENDING -> {
        pendingAdvance = true
        return true
      }
      QueueCommandOutcome.QUEUE_AT_END -> return true
      QueueCommandOutcome.QUEUE_NOT_LOADED -> return false
    }
  }

  override fun previousQueueItem(): Boolean {
    val host = host ?: return false
    if (!host.isCurrentRequest(activeRequestGeneration)) return false

    // Resolution does not gate "previous": a previous item can only exist
    // among items already resolved (the current position is always at or
    // behind the last item ever queued), so the native-queue checks below
    // decide — matching iOS, which services previous from already-applied
    // state during resolution.
    val exoPlayer = (host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent)?.exoPlayer
      ?: return false
    when (
      previousQueueCommandOutcome(
        hasPreviousMediaItem = exoPlayer.hasPreviousMediaItem(),
        repeatMode = repeatMode,
        resolvedCount = resolvedItems.size,
      )
    ) {
      PreviousQueueCommandOutcome.PREVIOUS -> {
        exoPlayer.seekToPreviousMediaItem()
        host.videoView.start()
        return true
      }
      PreviousQueueCommandOutcome.WRAP_TO_LAST -> {
        val timeline = exoPlayer.currentTimeline
        val lastWindowIndex = if (!timeline.isEmpty) {
          timeline.getLastWindowIndex(shuffle)
        } else {
          resolvedItems.size - 1
        }
        exoPlayer.seekTo(lastWindowIndex, 0)
        host.videoView.start()
        return true
      }
      // At the first item without repeat: restart the current item, matching
      // the documented previous-at-first behavior.
      PreviousQueueCommandOutcome.RESTART_CURRENT -> {
        exoPlayer.seekTo(0)
        host.videoView.start()
        return true
      }
    }
  }

  private fun nativeHasNextMediaItem(): Boolean {
    val host = host ?: return false
    val exoPlayer = (host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent)?.exoPlayer
      ?: return false
    return exoPlayer.hasNextMediaItem()
  }

  private fun hasCurrentQueue(): Boolean {
    val host = host ?: return false
    return videoIds.isNotEmpty() && activeRequestGeneration >= 0 && host.isCurrentRequest(activeRequestGeneration)
  }

  override fun onRegisterPlaybackListeners() {
    val host = host ?: return
    host.registerListener(EventType.WILL_CHANGE_VIDEO) { event ->
      val nextVideo = event.properties[Event.NEXT_VIDEO] as? Video ?: return@registerListener
      val currentVideo = event.properties[Event.CURRENT_VIDEO] as? Video
      if (currentVideo == null && currentResolvedIndex == 0) {
        return@registerListener
      }
      val exoPlayer = (host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent)?.exoPlayer
      val targetIndex = willChangeVideoTargetIndex(
        nextVideo = nextVideo,
        currentMediaItemIndex = exoPlayer?.currentMediaItemIndex,
      )
      if (targetIndex in resolvedItems.indices) {
        currentResolvedIndex = targetIndex
        val item = resolvedItems[targetIndex]
        completionState.onTransition(targetIndex)
        emitQueueItemChanged(item.video, item.originalIndex)
      }
    }
    host.registerListener(EventType.COMPLETED) { event ->
      if (!host.isCurrentRequest(activeRequestGeneration) || completionState.completionEmitted) return@registerListener
      val completedVideo = event.properties[Event.VIDEO] as? Video
      completionState.observeTerminal(resolvedIndexOf(completedVideo).takeIf { it >= 0 } ?: currentResolvedIndex)
      reconcileTerminalCompletion()
    }
  }

  /**
   * WILL_CHANGE_VIDEO fires before ExoPlayer commits the next item, so its
   * current index still identifies the old item. Resolve by Video identity
   * first; use the native index only for an SDK copy the feature did not add.
   */
  internal fun willChangeVideoTargetIndex(
    nextVideo: Video,
    currentMediaItemIndex: Int?,
  ): Int {
    val identityIndex = resolvedIndexOf(nextVideo)
    if (identityIndex >= 0) return identityIndex
    if (currentMediaItemIndex != null && currentMediaItemIndex in resolvedItems.indices) {
      return currentMediaItemIndex
    }
    return -1
  }

  private fun reconcileTerminalCompletion() {
    val host = host ?: return
    if (!host.isCurrentRequest(activeRequestGeneration)) return
    val playback = host.videoView.playback
    when (
      completionState.reconcile(
        resolvedCount = resolvedItems.size,
        resolutionInProgress = resolutionInProgress,
        nativeQueueSize = playback.getPlaylist().size,
        nativeCurrentIndex = playback.getCurrentIndex(),
        repeatMode = repeatMode,
      )
    ) {
      QueueCompletionAction.ADVANCE -> {
        val nextIndex = completionState.terminalIndex + 1
        playback.setCurrentIndex(nextIndex)
        host.videoView.start()
      }
      QueueCompletionAction.COMPLETE -> host.emitEvent(EVENT_QUEUE_COMPLETED, Arguments.createMap())
      QueueCompletionAction.WAIT -> Unit
    }
  }

  private fun resolveNext(
    catalog: Catalog,
    requestGeneration: Int,
    ids: List<String>,
    index: Int,
  ) {
    val host = host ?: return
    if (!host.isCurrentRequest(requestGeneration) || requestGeneration != activeRequestGeneration) return

    if (index >= ids.size) {
      resolutionInProgress = false
      if (resolvedItems.isEmpty()) {
        val aggregateCode = PlayerErrorClassifier.aggregateQueueErrorCategory(failedItemCodes)
        host.emitSourceLoadError(
          requestGeneration,
          code = aggregateCode,
          nativeCode = "playlist_empty_after_resolution",
          message = "None of the videos in videoIds could be resolved",
        )
      } else {
        // videoLoaded was already marked when the first item resolved; only a
        // pending manual advance still needs servicing here.
        if (pendingAdvance) {
          advanceQueue()
        }
      }
      reconcileTerminalCompletion()
      return
    }

    val videoId = ids[index]
    catalog.findVideoByID(
      videoId,
      object : VideoListener() {
        override fun onVideo(video: Video) {
          val currentHost = this@PlaylistsFeature.host ?: return
          if (!currentHost.isCurrentRequest(requestGeneration) || requestGeneration != activeRequestGeneration) return
          val isFirstResolved = resolvedItems.isEmpty()
          resolvedItems.add(ResolvedItem(video, originalIndex = index))
          currentHost.videoView.add(currentHost.tagVideoForCurrentRequest(currentHost.onVideoLoaded(video)))
          if (isFirstResolved) {
            currentResolvedIndex = 0
            // The core gates startPendingPlayback/onReady on videoLoaded;
            // marking on the FIRST resolution lets playback and autoPlay run
            // while the rest of the queue is still resolving instead of
            // waiting for every id to finish.
            currentHost.setReadyVideoId(requestGeneration, video.id)
            currentHost.markVideoLoaded(requestGeneration, video.id)
            emitQueueItemChanged(video, index)
          }
          applyRepeatModeToNative()
          applyShuffleToNative()
          if (pendingAdvance && resolvedItems.size > 1) {
            advanceQueue()
          }
          resolveNext(catalog, requestGeneration, ids, index + 1)
          reconcileTerminalCompletion()
        }

        override fun onError(errors: List<CatalogError>) {
          val currentHost = this@PlaylistsFeature.host ?: return
          if (!currentHost.isCurrentRequest(requestGeneration) || requestGeneration != activeRequestGeneration) return
          val firstError = errors.firstOrNull()
          val (code, nativeCode) = PlayerErrorClassifier.classifyCatalogError(
            firstError?.catalogErrorCode,
            firstError?.throwable,
          )
          failedItemCodes.add(code)
          emitQueueItemFailed(videoId, index, firstError, code, nativeCode)
          resolveNext(catalog, requestGeneration, ids, index + 1)
          reconcileTerminalCompletion()
        }
      },
    )
  }

  /**
   * Resolves an SDK-supplied Video back to its position in resolvedItems.
   * Identity match only. A videoIds queue may legitimately contain the same
   * catalog id twice (e.g. a bumper repeated between items); falling back to
   * an id-equality match would return the *first* occurrence for either
   * duplicate, silently reporting the wrong index — feeding a stale index
   * into completionState.onTransition could even suppress a still-pending
   * onQueueCompleted or fire it early. A missing match (no event / falling
   * back to currentResolvedIndex at the call site) is a visible gap; a wrong
   * index is a silent lie about queue state, which is worse.
   *
   * internal (not private) so PlaylistsFeatureTest can exercise the
   * duplicate-id ambiguity directly without mocking the async catalog flow.
   */
  internal fun resolvedIndexOf(video: Video?): Int {
    if (video == null) return -1
    return resolvedItems.indexOfFirst { it.video === video }
  }

  // internal (not private) so PlaylistsFeatureTest can seed resolvedItems
  // without driving the full async catalog-resolution flow.
  internal fun addResolvedItemForTest(video: Video, originalIndex: Int) {
    resolvedItems.add(ResolvedItem(video, originalIndex))
  }

  private fun applyRepeatModeToNative() {
    val host = host ?: return
    val exoPlayer = (host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent)?.exoPlayer ?: return
    exoPlayer.repeatMode = when (repeatMode) {
      "off" -> Player.REPEAT_MODE_OFF
      "one" -> Player.REPEAT_MODE_ONE
      "all" -> Player.REPEAT_MODE_ALL
      else -> Player.REPEAT_MODE_OFF
    }
  }

  private fun applyShuffleToNative() {
    val host = host ?: return
    val exoPlayer = (host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent)?.exoPlayer ?: return
    exoPlayer.shuffleModeEnabled = shuffle
  }

  private fun emitQueueItemChanged(video: Video, index: Int) {
    val host = host ?: return
    host.emitEvent(
      EVENT_QUEUE_ITEM_CHANGED,
      Arguments.createMap().apply {
        putString("videoId", video.id)
        putInt("index", index)
      },
    )
  }

  private fun emitQueueItemFailed(
    videoId: String,
    index: Int,
    error: CatalogError?,
    code: String,
    nativeCode: String,
  ) {
    val host = host ?: return
    val throwable = error?.throwable
    val (code, nativeCode) = PlayerErrorClassifier.classifyCatalogError(
      error?.catalogErrorCode,
      throwable,
    )
    host.emitEvent(
      EVENT_QUEUE_ITEM_FAILED,
      Arguments.createMap().apply {
        putString("videoId", videoId)
        putInt("index", index)
        putString("code", code)
        putString("nativeCode", nativeCode)
        putString(
          "message",
          throwable?.localizedMessage
            ?: error?.message?.ifBlank { null }
            ?: "Unable to retrieve the Brightcove video",
        )
      },
    )
  }

  companion object {
    private const val EVENT_QUEUE_ITEM_CHANGED = "topQueueItemChanged"
    private const val EVENT_QUEUE_ITEM_FAILED = "topQueueItemFailed"
    private const val EVENT_QUEUE_COMPLETED = "topQueueCompleted"
  }
}
