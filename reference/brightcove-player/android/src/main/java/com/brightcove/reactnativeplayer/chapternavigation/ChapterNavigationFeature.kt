package com.brightcove.reactnativeplayer.chapternavigation

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import kotlin.math.roundToLong

/**
 * Navigates to caller-owned chapter times through Brightcove's validated seek
 * API. The native bridge does not discover chapter titles or ranges.
 */
class ChapterNavigationFeature : PlayerFeature {
  private var host: FeatureHost? = null
  private var chapterSeekTime = -1.0
  private var chapterSeekRequestId = 0
  private var lastHandledRequestId = 0
  private var pendingRequest: PendingSeek? = null
  private var prepared = false
  private var sourceFailed = false
  private var postSequence = 0

  override val ownedProps: Set<String> = setOf("chapterSeekTime", "chapterSeekRequestId")

  override val exportedEvents: Map<String, String> = mapOf(
    EVENT_CHAPTER_SEEK_COMPLETED to "onChapterSeekCompleted",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
    sourceFailed = false
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "chapterSeekTime" -> {
        val requested = (value as? Number)?.toDouble()
          ?: error("ChapterNavigationFeature requires a number for '$name'")
        require(requested == -1.0 || chapterSeekPositionMillis(requested) != null) {
          "ChapterNavigationFeature requires -1 or a finite seekable time"
        }
        chapterSeekTime = requested
        scheduleSeek()
      }
      "chapterSeekRequestId" -> {
        val requestId = (value as? Number)?.toInt()
          ?: error("ChapterNavigationFeature requires an integer for '$name'")
        require(requestId >= 0) {
          "ChapterNavigationFeature requires a non-negative request id"
        }
        chapterSeekRequestId = requestId
        scheduleSeek()
      }
      else -> error("ChapterNavigationFeature does not own prop '$name'")
    }
  }

  override fun onSourceReset() {
    postSequence += 1
    pendingRequest = null
    prepared = false
    sourceFailed = false
    lastHandledRequestId = chapterSeekRequestId
  }

  override fun onRegisterPlaybackListeners() {
    val host = checkNotNull(host)
    host.registerListener(EventType.BUFFERING_COMPLETED) {
      prepared = true
      scheduleSeek()
    }
    host.registerListener(EventType.DID_SEEK_TO) { event ->
      val pending = pendingRequest ?: return@registerListener
      val actualTime = eventPositionSeconds(event) ?: return@registerListener
      if (kotlin.math.abs(actualTime - pending.targetTime) > SEEK_CONFIRMATION_TOLERANCE_SECONDS) {
        return@registerListener
      }
      pendingRequest = null
      emitSeekResult(pending.requestId, actualTime, completed = true)
      scheduleSeek()
    }
    host.registerListener(EventType.SEEK_TO_INCORRECT_TARGET_VALUE) {
      val pending = pendingRequest ?: return@registerListener
      pendingRequest = null
      emitSeekResult(pending.requestId, pending.targetTime, completed = false)
      scheduleSeek()
    }
  }

  override fun onPlaybackError() {
    sourceFailed = true
    pendingRequest = null
  }

  override fun onDispose() {
    sourceFailed = true
    pendingRequest = null
    postSequence += 1
    host = null
  }

  private fun scheduleSeek() {
    val host = host ?: return
    if (host.isDisposed || sourceFailed) return
    val sequence = ++postSequence
    host.hostView.post {
      if (sequence != postSequence || host.isDisposed || sourceFailed) return@post
      performPendingSeek()
    }
  }

  private fun performPendingSeek() {
    val host = host ?: return
    if (!prepared || pendingRequest != null || chapterSeekTime < 0.0) return
    if (chapterSeekRequestId == 0 || chapterSeekRequestId == lastHandledRequestId) return

    val requestId = chapterSeekRequestId
    val targetTime = chapterSeekTime
    val positionMs = chapterSeekPositionMillis(targetTime) ?: return
    // A target beyond the video's duration is clamped by ExoPlayer to the end
    // of the media, so the confirming DID_SEEK_TO reports the clamped
    // position, the ±1s tolerance check rejects it, and pendingRequest would
    // never clear — wedging every later chapter seek for the whole source
    // (nothing in the SDK emits SEEK_TO_INCORRECT_TARGET_VALUE for this case).
    // iOS and web pre-validate the same way (duration + 0.5s) and report
    // completed=false instead of seeking.
    val durationMs = host.videoView.duration
    if (chapterSeekTargetIsOutOfRange(targetTime, if (durationMs > 0) durationMs.toDouble() else null)) {
      lastHandledRequestId = requestId
      emitSeekResult(requestId, targetTime, completed = false)
      return
    }
    lastHandledRequestId = requestId
    pendingRequest = PendingSeek(requestId, targetTime)
    host.videoView.seekTo(positionMs)
  }

  private fun eventPositionSeconds(event: Event): Double? {
    val positionMs = (event.properties[Event.PLAYHEAD_POSITION_LONG] as? Number)?.toLong()
      ?: return null
    return positionMs / 1000.0
  }

  private fun emitSeekResult(requestId: Int, positionSeconds: Double, completed: Boolean) {
    val host = host ?: return
    if (host.isDisposed) return
    host.emitEvent(
      EVENT_CHAPTER_SEEK_COMPLETED,
      Arguments.createMap().apply {
        putInt("requestId", requestId)
        putDouble("positionSeconds", positionSeconds)
        putBoolean("completed", completed)
      },
    )
  }

  companion object {
    const val EVENT_CHAPTER_SEEK_COMPLETED = "topChapterSeekCompleted"
    private const val SEEK_CONFIRMATION_TOLERANCE_SECONDS = 1.0
  }
}

private data class PendingSeek(
  val requestId: Int,
  val targetTime: Double,
)

internal fun chapterSeekPositionMillis(seconds: Double): Long? {
  if (!seconds.isFinite() || seconds < 0.0 ||
      seconds > Long.MAX_VALUE.toDouble() / 1000.0) {
    return null
  }
  return (seconds * 1000.0).roundToLong()
}

// Out-of-range decision for a chapter seek target. A null duration (unknown,
// non-positive, or not yet reported by the SDK) skips validation, matching
// iOS's non-numeric-duration case; the 0.5s grace mirrors iOS/web so a
// boundary-exact target still seeks.
internal fun chapterSeekTargetIsOutOfRange(targetSeconds: Double, durationSeconds: Double?): Boolean {
  if (durationSeconds == null || !durationSeconds.isFinite() || durationSeconds <= 0.0) return false
  return targetSeconds > durationSeconds + 0.5
}
