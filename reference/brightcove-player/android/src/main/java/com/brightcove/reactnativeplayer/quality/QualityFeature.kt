package com.brightcove.reactnativeplayer.quality

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import com.brightcove.player.display.ExoPlayerVideoDisplayComponent
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import java.security.MessageDigest
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Relays Brightcove's native rendition observations and applies an adaptive
 * peak-bitrate preference without exposing a Format or any other SDK object to React Native.
 */
class QualityFeature : PlayerFeature {
  private var host: FeatureHost? = null
  private var sourceId = ""
  private var lastEventKey: String? = null
  private var preferredPeakBitrate = 0
  private var sourceFailed = false

  override val ownedProps: Set<String> = setOf("preferredPeakBitrate")

  override val exportedEvents: Map<String, String> = mapOf(
    EVENT_RENDITION_CHANGED to "onRenditionChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
    sourceFailed = false
  }

  override fun setProp(name: String, value: Any?) {
    if (name != "preferredPeakBitrate") {
      error("QualityFeature does not own prop '$name'")
    }

    val requested = (value as? Number)?.toDouble()
      ?: error("QualityFeature requires a number for '$name'")
    require(requested.isFinite() && requested >= 0.0 && requested <= Int.MAX_VALUE) {
      "QualityFeature requires a finite non-negative peak bitrate"
    }
    preferredPeakBitrate = requested.roundToInt()
    applyPreferredPeakBitrate()
  }

  override fun onSourceReset() {
    sourceId = UUID.randomUUID().toString()
    lastEventKey = null
    sourceFailed = false
  }

  override fun onRegisterPlaybackListeners() {
    val host = checkNotNull(host)
    host.registerListener(ExoPlayerVideoDisplayComponent.RENDITION_CHANGED) { event ->
      val format = event.properties[ExoPlayerVideoDisplayComponent.EXOPLAYER_FORMAT] as? Format
        ?: return@registerListener
      val video = event.properties[Event.VIDEO] as? Video ?: return@registerListener
      emitRendition(video, format)
    }

    listOf(EventType.BUFFERING_STARTED, EventType.BUFFERING_COMPLETED).forEach { eventType ->
      host.registerListener(eventType) {
        applyPreferredPeakBitrate()
      }
    }
  }

  override fun onPlaybackError() {
    sourceFailed = true
  }

  override fun onDispose() {
    sourceFailed = true
    host = null
    lastEventKey = null
  }

  private fun applyPreferredPeakBitrate() {
    val host = host ?: return
    if (sourceFailed || host.isDisposed) return
    val display = host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent ?: return
    display.setPeakBitrate(preferredPeakBitrate)
  }

  private fun emitRendition(video: Video, format: Format) {
    val host = host ?: return
    if (sourceFailed || host.isDisposed) return
    if (sourceId.isEmpty()) return

    // Brightcove emits this event for every downstream format, including audio.
    // Use the media-type classifier so a video with unknown dimensions is still
    // observable rather than being mistaken for an audio format.
    if (!MimeTypes.isVideo(format.sampleMimeType)) return
    val width = format.width.takeIf { it > 0 } ?: 0
    val height = format.height.takeIf { it > 0 } ?: 0
    val bitrate = format.bitrate.takeIf { it > 0 } ?: 0
    val renditionKey = listOf(
      sourceId,
      format.id.orEmpty(),
      format.sampleMimeType.orEmpty(),
      bitrate,
      width,
      height,
    ).joinToString("|")
    if (renditionKey == lastEventKey) return
    lastEventKey = renditionKey

    host.emitEvent(
      EVENT_RENDITION_CHANGED,
      Arguments.createMap().apply {
        putString("sourceId", sourceId)
        putString("videoId", video.id)
        putString("renditionId", opaqueId(renditionKey))
        putDouble("bitrate", bitrate.toDouble())
        putDouble("width", width.toDouble())
        putDouble("height", height.toDouble())
      },
    )
  }

  private fun opaqueId(value: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    return buildString(digest.size * 2) {
      digest.forEach { byte ->
        append("%02x".format(byte.toInt() and 0xff))
      }
    }
  }

  companion object {
    const val EVENT_RENDITION_CHANGED = "topRenditionChanged"
  }
}

internal fun knownQualityInt(value: Int): Int =
  if (value == Format.NO_VALUE || value < 0) 0 else value

internal fun knownQualityFrameRate(value: Float): Double =
  if (value == Format.NO_VALUE.toFloat() || value < 0f) 0.0 else value.toDouble()
