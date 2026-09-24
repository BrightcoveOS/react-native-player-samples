package com.brightcove.reactnativeplayer.sidecarcaptions

import android.net.Uri
import android.util.Pair
import com.brightcove.player.captioning.BrightcoveCaptionFormat
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Sidecar subtitles/captions feature: loads and binds externally-hosted WebVTT
 * subtitle tracks before playback by adding caption sources to the resolved
 * Video model.
 */
class SidecarCaptionsFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var sidecarTracks: List<SidecarTrack> = emptyList()
  private var validTracks: List<SidecarTrack> = emptyList()

  private var trackAdded = false
  private var configurationValidated = false
  private var configurationDirty = false

  override val ownedProps = setOf("sidecarTracks")

  override val exportedEvents = mapOf(
    EVENT_SIDECAR_TRACK_STATUS to "onSidecarTrackStatus",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "sidecarTracks" -> {
        @Suppress("UNCHECKED_CAST")
        val rawTracks = value as? List<*>
          ?: error("SidecarCaptionsFeature requires a List for '$name'")
        sidecarTracks = parseSidecarTracks(rawTracks)
        configurationDirty = true
      }

      else -> error("SidecarCaptionsFeature does not own prop '$name'")
    }
  }

  override fun onSourceReset() {
    trackAdded = false
    emitStatus("reset", language = "", label = "")
  }

  override fun onRegisterPlaybackListeners() {
    host.registerListener(EventType.SELECT_CLOSED_CAPTION_TRACK) { event ->
      val format = event.properties[Event.CAPTION_FORMAT] as? BrightcoveCaptionFormat
      val lang = format?.language()?.ifBlank { null }
      if (lang != null && validTracks.any { it.language.equals(lang, ignoreCase = true) }) {
        val track = validTracks.first { it.language.equals(lang, ignoreCase = true) }
        emitStatus("selected", track.language, track.label)
      }
    }

    host.registerListener(EventType.CLOSED_CAPTIONING_ERROR) { event ->
      // CLOSED_CAPTIONING_ERROR is emitted by the SDK's sidecar VTT/TTML
      // loader (LoadCaptionsTask) exclusively; in-manifest caption formats
      // (HLS/DASH) are handled by ExoPlayer's own cue pipeline and never
      // reach this event. The event carries no track/URI identifier, so we
      // can only attribute it to this feature's own tracks by whether we
      // actually added any for the current video — otherwise a caption
      // error unrelated to this sidecar attempt would be misreported.
      if (!trackAdded || validTracks.isEmpty()) return@registerListener
      val track = validTracks.first()
      val errorMsg = event.properties[Event.ERROR_MESSAGE]?.toString()
      emitStatus(
        "failed",
        track.language,
        track.label,
        error = "load",
        nativeCode = errorMsg ?: "sidecar_vtt_load_failed",
      )
    }
  }

  override fun onPropsCommitted() {
    if (!configurationDirty) return
    configurationDirty = false
    configurationValidated = true
    validateSidecarTracks(sidecarTracks).forEach { (track, error) ->
      emitStatus(
        "failed",
        track.language,
        track.label,
        error = "invalid_configuration",
        nativeCode = error.nativeCode,
      )
    }
    validTracks = validSidecarTracks(sidecarTracks)
  }

  override fun willAddVideo(video: com.brightcove.player.model.Video): Boolean {
    if (sidecarTracks.isEmpty()) return false
    if (trackAdded || host.isDisposed) return false
    if (!configurationValidated) onPropsCommitted()
    if (validTracks.isEmpty()) return false

    @Suppress("UNCHECKED_CAST")
    val existing = video.getProperties()[com.brightcove.player.model.Video.Fields.CAPTION_SOURCES]
      as? List<Pair<Uri, BrightcoveCaptionFormat>>
    val sources = existing?.toMutableList() ?: mutableListOf()
    val addedLanguages = mutableSetOf<String>()
    validTracks.forEach { track ->
      if (existing.orEmpty().any { it.second.language().equals(track.language, ignoreCase = true) }) {
        emitStatus(
          "failed",
          track.language,
          track.label,
          error = "invalid_configuration",
          nativeCode = "sidecar_language_collision",
        )
        return@forEach
      }
      if (!addedLanguages.add(track.language.lowercase())) return@forEach
      val format = BrightcoveCaptionFormat.createCaptionFormat("text/vtt", track.language, track.label)
      sources += Pair(Uri.parse(track.url), format)
      emitStatus("configured", track.language, track.label)
    }
    if (sources.isNotEmpty()) {
      video.getProperties()[com.brightcove.player.model.Video.Fields.CAPTION_SOURCES] = sources
    }
    trackAdded = true
    return false
  }

  private fun emitStatus(
    status: String,
    language: String = "",
    label: String = "",
    error: String = "",
    nativeCode: String = "",
  ) {
    if (host.isDisposed) return
    val payload = Arguments.createMap().apply {
      putString("status", status)
      putString("language", language)
      putString("label", label)
      putString("error", error)
      putString("nativeCode", nativeCode)
    }
    host.emitEvent(EVENT_SIDECAR_TRACK_STATUS, payload)
  }

  companion object {
    const val EVENT_SIDECAR_TRACK_STATUS = "topSidecarTrackStatus"
  }
}
