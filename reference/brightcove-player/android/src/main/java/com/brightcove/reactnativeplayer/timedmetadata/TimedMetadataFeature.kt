package com.brightcove.reactnativeplayer.timedmetadata

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.metadata.TextInformationFrameListener
import com.brightcove.player.model.CuePoint
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Emits the two time-aligned data shapes Brightcove exposes consistently across
 * Android and iOS: textual ID3 frames and finite catalog cue points. It never
 * forwards SDK metadata/cue objects or arbitrary cue properties to JS.
 */
class TimedMetadataFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  override val ownedProps = emptySet<String>()
  override val exportedEvents = mapOf(EVENT_TIMED_METADATA to "onTimedMetadata")

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    error("TimedMetadataFeature owns no props; received '$name'")
  }

  override fun onSourceReset() {
    host.videoView.videoDisplay.setTextInformationFrameListener(TextInformationFrameListener.DISABLED)
  }

  override fun onRegisterPlaybackListeners() {
    val generation = host.currentRequestGeneration
    host.videoView.videoDisplay.setTextInformationFrameListener(
      TextInformationFrameListener { frame, playheadPositionMs ->
        // Metadata delivery is asynchronous relative to source replacement.
        // This closure keeps the generation it was installed for, so a queued
        // old ID3 frame cannot update a newer React source.
        if (!host.isCurrentRequest(generation)) return@TextInformationFrameListener
        emit(
          timeSeconds = playheadPositionMs / 1_000.0,
          type = TYPE_ID3_TEXT,
          key = frame.id,
          value = frame.value,
        )
      },
    )
    host.registerListener(EventType.CUE_POINT) { event ->
      val cuePoints = event.properties[Event.CUE_POINTS] as? List<*> ?: return@registerListener
      cuePoints.filterIsInstance<CuePoint>().forEach { cuePoint ->
        if (cuePoint.positionType != CuePoint.PositionType.POINT_IN_TIME) return@forEach
        if (cuePoint.positionLong <= 0L) return@forEach
        emit(
          timeSeconds = cuePoint.positionLong / 1_000.0,
          type = TYPE_CUE_POINT,
          key = "type",
          value = cuePoint.cuePointType.toString(),
        )
      }
    }
  }

  override fun onDispose() {
    host.videoView.videoDisplay.setTextInformationFrameListener(TextInformationFrameListener.DISABLED)
  }

  private fun emit(timeSeconds: Double, type: String, key: String, value: String) {
    host.emitEvent(
      EVENT_TIMED_METADATA,
      Arguments.createMap().apply {
        putDouble("time", timeSeconds)
        putString("type", type)
        putMap("data", Arguments.createMap().apply {
          putString("key", key)
          putString("value", value)
        })
      },
    )
  }

  private companion object {
    const val EVENT_TIMED_METADATA = "topTimedMetadata"
    const val TYPE_ID3_TEXT = "id3-text"
    const val TYPE_CUE_POINT = "cue-point"
  }
}
