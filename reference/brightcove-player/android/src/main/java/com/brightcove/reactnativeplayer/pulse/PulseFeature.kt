package com.brightcove.reactnativeplayer.pulse

import android.content.Intent
import android.net.Uri
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.pulse.PulseComponent
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.ooyala.pulse.ContentMetadata
import com.ooyala.pulse.Pulse
import com.ooyala.pulse.PulseSession
import com.ooyala.pulse.PulseVideoAd
import com.ooyala.pulse.RequestSettings
import com.facebook.react.bridge.Arguments

/**
 * INVIDI Pulse ad insertion. Pulse exposes ad-break callbacks through the
 * Brightcove event bus; it does not expose the same per-ad lifecycle on both
 * native SDKs, so this feature deliberately exports only break boundaries.
 */
class PulseFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var pulseComponent: PulseComponent? = null
  private var sourceGeneration = 0

  private var pulseHost: String? = null
  private var pulseCategory: String? = null
  private var pulseTags: String? = null
  private var pulseContentMetadataTitle: String? = null
  private var pulseMidrollPositions: String? = null

  override val ownedProps = setOf(
    "pulseHost",
    "pulseCategory",
    "pulseTags",
    "pulseContentMetadataTitle",
    "pulseMidrollPositions",
  )

  override val exportedEvents = mapOf(
    EVENT_AD_BREAK_STARTED to "onAdBreakStarted",
    EVENT_AD_BREAK_ENDED to "onAdBreakEnded",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "pulseHost" -> pulseHost = (value as? String)?.ifBlank { null }
      "pulseCategory" -> pulseCategory = (value as? String)?.ifBlank { null }
      "pulseTags" -> pulseTags = (value as? String)?.ifBlank { null }
      "pulseContentMetadataTitle" -> pulseContentMetadataTitle = (value as? String)?.ifBlank { null }
      "pulseMidrollPositions" -> pulseMidrollPositions = (value as? String)?.ifBlank { null }
      else -> error("PulseFeature owns no prop '$name'")
    }
  }

  private fun ensurePulseComponent() {
    if (pulseComponent != null || host.isDisposed) return
    val hostUrl = pulseHost ?: return

    val component = PulseComponent(hostUrl, host.eventEmitter, host.videoView)
    component.setListener(object : PulseComponent.Listener {
      override fun onCreatePulseSession(
        pulseHostUrl: String,
        video: Video,
        contentMetadata: ContentMetadata,
        requestSettings: RequestSettings,
      ): PulseSession {
        if (host.isDisposed || sourceGeneration == 0) {
          throw IllegalStateException("Pulse session requested on disposed or reset player")
        }
        Pulse.setPulseHost(pulseHostUrl, null, null)
        pulseCategory?.let(contentMetadata::setCategory)
        pulseTags?.let { tags ->
          contentMetadata.setTags(tags.split(',').map(String::trim).filter(String::isNotEmpty))
        }
        contentMetadata.setIdentifier(pulseContentMetadataTitle ?: video.id ?: "demo")
        pulseMidrollPositions?.let { positions ->
          requestSettings.setLinearPlaybackPositions(parsePulseMidrollPositions(positions))
        }
        return Pulse.createSession(contentMetadata, requestSettings)
      }

      override fun onOpenClickthrough(pulseVideoAd: PulseVideoAd) {
        if (host.isDisposed || sourceGeneration == 0) return
        val url = pulseVideoAd.getClickthroughURL()?.toString()
          ?: error("Pulse returned a clickthrough callback without a URL")
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        checkNotNull(intent.resolveActivity(host.hostView.context.packageManager)) {
          "No activity can open Pulse clickthrough URL"
        }
        host.hostView.context.startActivity(intent)
        pulseVideoAd.adClickThroughTriggered()
      }
    })

    pulseComponent = component
  }

  override fun onRegisterPlaybackListeners() {
    sourceGeneration += 1
    host.registerListener(EventType.AD_BREAK_STARTED) {
      host.emitEvent(
        EVENT_AD_BREAK_STARTED,
        Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
      )
    }
    host.registerListener(EventType.AD_BREAK_COMPLETED) {
      host.emitEvent(
        EVENT_AD_BREAK_ENDED,
        Arguments.createMap().apply { putInt("index", UNKNOWN_AD_BREAK_INDEX) },
      )
    }
    ensurePulseComponent()
  }

  override fun onSourceReset() {
    sourceGeneration += 1
  }

  override fun onDispose() {
    sourceGeneration += 1
    pulseComponent?.removeListeners()
    pulseComponent?.release()
    pulseComponent = null
  }

  companion object {
    private const val UNKNOWN_AD_BREAK_INDEX = -1
    private const val EVENT_AD_BREAK_STARTED = "topAdBreakStarted"
    private const val EVENT_AD_BREAK_ENDED = "topAdBreakEnded"
  }
}

internal fun parsePulseMidrollPositions(value: String): List<Float> =
  value.split(',').map(String::trim).map { rawPosition ->
    require(rawPosition.isNotEmpty()) {
      "pulseMidrollPositions must contain non-negative finite seconds"
    }
    val seconds = rawPosition.toFloat()
    require(seconds.isFinite() && seconds >= 0f) {
      "pulseMidrollPositions must contain non-negative finite seconds"
    }
    seconds
  }
