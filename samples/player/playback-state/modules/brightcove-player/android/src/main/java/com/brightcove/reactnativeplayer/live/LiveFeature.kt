package com.brightcove.reactnativeplayer.live

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

internal data class SeekableRangeWindow(
  val start: Long,
  val end: Long,
  val liveEdge: Long,
) {
  fun isValid(): Boolean = isValidSeekableRange(start, end, liveEdge)
}

/** Typed outcome of the seekToLiveEdge command's guard table. */
internal enum class SeekToLiveEdgeOutcome {
  /** The source is not live, or live without DVR — it can never seek to the edge. */
  NOT_LIVE_DVR,

  /** Live with DVR, but the seekable window is not populated/valid yet. */
  NO_DVR_RANGE_YET,

  /** A valid range and edge exist — the seek proceeds. */
  SOUGHT,
}

internal fun isValidSeekableRange(start: Long, end: Long, liveEdge: Long): Boolean =
  start >= 0L && end > start && liveEdge > 0L && liveEdge >= start

internal fun hasSeekableRangeBounds(event: Event): Boolean =
  event.properties.containsKey(Event.MIN_POSITION_LONG) &&
    event.properties.containsKey(Event.MAX_POSITION_LONG)

internal fun extractSeekableRange(event: Event, rawLiveEdge: Long): SeekableRangeWindow? {
  val start = (event.properties[Event.MIN_POSITION_LONG] as? Number)?.toLong() ?: return null
  val end = (event.properties[Event.MAX_POSITION_LONG] as? Number)?.toLong() ?: return null
  if (!isValidSeekableRange(start, end, rawLiveEdge)) {
    return null
  }
  val clampedLiveEdge = minOf(rawLiveEdge, end)
  return SeekableRangeWindow(start, end, clampedLiveEdge)
}

/**
 * Reports whether the loaded video is a live (or live-DVR) stream so JS can
 * adapt its UI. Emits onLiveStatus once per source, after the SDK has enough of
 * the stream to know its type.
 *
 * For live-DVR streams, seekable range updates are surfaced with the moving
 * window bounds and current live edge. Live-edge seeking is supported via
 * seekToLiveEdge().
 *
 * The feature owns no props (it is event-only).
 */
class LiveFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var classificationReported = false
  private var lastRangeKey: String? = null
  private var currentRange: SeekableRangeWindow? = null

  override val ownedProps = emptySet<String>()
  override val supportedCommands = setOf(COMMAND_SEEK_TO_LIVE_EDGE)

  override val exportedEvents = mapOf(
    EVENT_LIVE_STATUS to "onLiveStatus",
    EVENT_SEEKABLE_RANGES_CHANGED to "onSeekableRangesChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    throw IllegalArgumentException("LiveFeature owns no props; received '$name'")
  }

  override fun onSourceReset() {
    classificationReported = false
    lastRangeKey = EMPTY_RANGE_KEY
    currentRange = null
    emitSeekableRanges(emptyList(), 0L)
  }

  override fun onRegisterPlaybackListeners() {
    host.registerListener(EventType.BUFFERING_COMPLETED) {
      emitLiveStatusIfReady()
    }

    host.registerListener(EventType.VIDEO_DURATION_CHANGED) { event ->
      handleRangeEvent(event, clearWhenBoundsMissing = true)
    }

    host.registerListener(EventType.PROGRESS) { event ->
      handleRangeEvent(event, clearWhenBoundsMissing = false)
    }
  }

  override fun handleCommand(name: String): Boolean {
    if (name == COMMAND_SEEK_TO_LIVE_EDGE) {
      when (seekToLiveEdgeOutcome()) {
        SeekToLiveEdgeOutcome.SOUGHT -> seekToLiveEdge()
        SeekToLiveEdgeOutcome.NOT_LIVE_DVR -> host.emitCommandError(
          command = name,
          code = "invalid_state",
          message = "Cannot seek to the live edge: the source is not a live stream with DVR",
          nativeCode = "not_live_dvr",
        )
        // The stream IS live with DVR but the seekable window has not been
        // reported yet (no range event has arrived, or the edge is not
        // inside it). Distinct from not_live_dvr so a caller can tell "wait
        // for ranges" from "this source can never seek to the edge" — the
        // same split the iOS feature reports.
        SeekToLiveEdgeOutcome.NO_DVR_RANGE_YET -> host.emitCommandError(
          command = name,
          code = "invalid_state",
          message = "Cannot seek to the live edge: the DVR seekable range is not available yet",
          nativeCode = "no_dvr_range_yet",
        )
      }
      return true
    }
    return false
  }

  /**
   * Pure decision for seekToLiveEdge, extracted so both guard branches are
   * unit-testable without an ExoPlayer. The caller performs the seek.
   */
  internal fun seekToLiveEdgeOutcome(
    isLive: Boolean = host.videoView.videoDisplay?.isLive == true,
    hasDvr: Boolean = host.videoView.videoDisplay?.hasDvr() == true,
    hasValidRange: Boolean = hasValidDvrRange(),
  ): SeekToLiveEdgeOutcome {
    if (!isLive || !hasDvr) return SeekToLiveEdgeOutcome.NOT_LIVE_DVR
    if (!hasValidRange) return SeekToLiveEdgeOutcome.NO_DVR_RANGE_YET
    return SeekToLiveEdgeOutcome.SOUGHT
  }

  fun hasValidDvrRange(): Boolean {
    return currentRange?.isValid() == true
  }

  private fun seekToLiveEdge(): Boolean {
    // The outcome was already decided as SOUGHT by the caller; these guards
    // now only protect against a race between the decision and the seek
    // (the range being cleared in the same main-loop turn). A false return
    // would surface as a silent no-op, so the guards collapse to one decision.
    if (seekToLiveEdgeOutcome() != SeekToLiveEdgeOutcome.SOUGHT) return false
    val videoDisplay = host.videoView.videoDisplay ?: return false
    val range = currentRange ?: return false
    val rawLiveEdge = videoDisplay.getLiveEdgeLong()
    if (rawLiveEdge <= 0L || rawLiveEdge < range.start) return false
    val targetPosition = minOf(rawLiveEdge, range.end)
    host.videoView.seekTo(targetPosition)
    return true
  }

  private fun emitLiveStatusIfReady() {
    if (classificationReported) return
    val videoDisplay = host.videoView.videoDisplay ?: return
    classificationReported = true
    emitLiveStatus(videoDisplay.isLive, videoDisplay.hasDvr())
  }

  private fun handleRangeEvent(event: Event, clearWhenBoundsMissing: Boolean) {
    if (!hasSeekableRangeBounds(event)) {
      if (clearWhenBoundsMissing) clearRange()
      return
    }
    val videoDisplay = host.videoView.videoDisplay ?: return
    if (!videoDisplay.isLive || !videoDisplay.hasDvr()) {
      clearRange()
      return
    }
    val rawLiveEdge = videoDisplay.getLiveEdgeLong()
    val range = extractSeekableRange(event, rawLiveEdge)
    if (range == null) {
      clearRange()
      return
    }
    val key = "${range.start}:${range.end}:${range.liveEdge}"
    if (key == lastRangeKey) return
    lastRangeKey = key
    currentRange = range
    emitSeekableRanges(listOf(range.start to range.end), range.liveEdge)
  }

  private fun clearRange() {
    currentRange = null
    if (lastRangeKey == EMPTY_RANGE_KEY) return
    lastRangeKey = EMPTY_RANGE_KEY
    emitSeekableRanges(emptyList(), 0L)
  }

  private fun emitLiveStatus(isLive: Boolean, hasDvr: Boolean) {
    host.emitEvent(
      EVENT_LIVE_STATUS,
      Arguments.createMap().apply {
        putBoolean("isLive", isLive)
        putBoolean("hasDvr", hasDvr)
      },
    )
  }

  private fun emitSeekableRanges(ranges: List<Pair<Long, Long>>, liveEdge: Long) {
    val rangeArray = Arguments.createArray()
    ranges.forEach { (start, end) ->
      rangeArray.pushMap(
        Arguments.createMap().apply {
          putDouble("startTime", start / 1000.0)
          putDouble("endTime", end / 1000.0)
        },
      )
    }
    host.emitEvent(
      EVENT_SEEKABLE_RANGES_CHANGED,
      Arguments.createMap().apply {
        putArray("ranges", rangeArray)
        putDouble("liveEdge", liveEdge / 1000.0)
      },
    )
  }

  companion object {
    private const val COMMAND_SEEK_TO_LIVE_EDGE = "seekToLiveEdge"
    private const val EVENT_LIVE_STATUS = "topLiveStatus"
    private const val EVENT_SEEKABLE_RANGES_CHANGED = "topSeekableRangesChanged"
    private const val EMPTY_RANGE_KEY = "empty"
  }
}
