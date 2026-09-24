package com.brightcove.reactnativeplayer.audiotracks

import androidx.media3.common.C
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import java.util.Locale

class AudioTracksFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var audioTrackId: String? = null

  private val trackIdMap = AudioTrackIdMap()
  private var audioTracksReady = false
  private var activeTrackId: String? = null
  private var appliedSelectionKey: String? = null
  private var appliedSelectionId: String? = null
  private var pendingSelectionKey: String? = null
  private var pendingSelectionId: String? = null
  private var pendingSelectionGeneration: Int? = null
  private var pendingSelectionSequence: Int? = null
  private val ignoredSelectionIds = mutableSetOf<String>()
  private var clearedRequestId: String? = null
  private var clearedRequestGeneration: Int? = null
  private var selectionClearPending = false
  private var postedSelectionSequence = 0

  override val ownedProps = setOf("audioTrackId")

  override val exportedEvents = mapOf(
    EVENT_AUDIO_TRACKS_AVAILABLE to "onAudioTracksAvailable",
    EVENT_AUDIO_TRACK_CHANGED to "onAudioTrackChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "audioTrackId" -> {
        val requested = (value as? String)?.ifBlank { null }
        if (audioTrackId != requested) {
          audioTrackId = requested
          clearedRequestId = null
          clearedRequestGeneration = null
        }
      }
      else -> error("AudioTracksFeature does not own prop '$name'")
    }
  }

  override fun onPropsCommitted() {
    applyAudioTrackSelection()
  }

  override fun onSourceReset() {
    resetSelectionState()
    emitAudioTracksAvailable()
    emitAudioTrackChanged("", "")
  }

  override fun onRegisterPlaybackListeners() {
    host.registerListener(EventType.AUDIO_TRACKS) { event ->
      val rawTracks = (event.properties[Event.TRACKS] as? List<*>)
        ?.filterIsInstance<String>()
        ?.filter { it.isNotBlank() }
        .orEmpty()
      trackIdMap.replace(rawTracks)
      audioTracksReady = true

      val selected = event.properties[Event.SELECTED_TRACK] as? String
      val initialTrackId = selected?.let { trackIdMap.entryForSelectionKey(it)?.id }

      emitAudioTracksAvailable()
      if (initialTrackId != null && !selectionClearPending) {
        setActiveTrackId(initialTrackId)
      }
      applyAudioTrackSelection()
    }

    host.registerListener(EventType.SELECT_AUDIO_TRACK) { event ->
      val selected = event.properties[Event.SELECTED_TRACK] as? String
      val confirmed = selected?.let { trackIdMap.entryForSelectionKey(it) }
      if (confirmed == null) return@registerListener
      if (ignoredSelectionIds.remove(confirmed.id)) return@registerListener

      val pendingId = pendingSelectionId
      if (pendingId != null) {
        val isExpected = pendingId == confirmed.id &&
          pendingSelectionKey == confirmed.selectionKey &&
          pendingSelectionGeneration == trackIdMap.currentGeneration &&
          pendingSelectionSequence == postedSelectionSequence &&
          audioTrackId == pendingId
        if (!isExpected) {
          invalidatePendingSelection()
          return@registerListener
        }
        pendingSelectionKey = null
        pendingSelectionId = null
        pendingSelectionGeneration = null
        pendingSelectionSequence = null
        appliedSelectionKey = confirmed.selectionKey
        appliedSelectionId = confirmed.id
        clearedRequestId = null
        clearedRequestGeneration = null
        selectionClearPending = false
        setActiveTrackId(confirmed.id)
        host.requestHostLayout()
        return@registerListener
      }

      appliedSelectionKey = confirmed.selectionKey
      appliedSelectionId = confirmed.id
      selectionClearPending = false
      setActiveTrackId(confirmed.id)
      host.requestHostLayout()
    }
  }

  private fun applyAudioTrackSelection() {
    if (host.isDisposed || !audioTracksReady) return

    val action = if (audioTrackId != null &&
      audioTrackId == clearedRequestId &&
      trackIdMap.currentGeneration == clearedRequestGeneration
    ) {
      AudioTrackSelectionAction.None
    } else {
      trackIdMap.selectionAction(audioTrackId, appliedSelectionId, appliedSelectionKey)
    }
    when (action) {
      is AudioTrackSelectionAction.Select -> {
        selectionClearPending = false
        val requestedId = action.entry.id
        val requestedKey = action.entry.selectionKey
        if (requestedKey != pendingSelectionKey || requestedId != pendingSelectionId) {
          invalidatePendingSelection()
          pendingSelectionKey = requestedKey
          pendingSelectionId = requestedId
          val generation = trackIdMap.currentGeneration
          val sequence = ++postedSelectionSequence
          pendingSelectionGeneration = generation
          pendingSelectionSequence = sequence
          val targetTrack = requestedKey
          val targetId = requestedId
          host.hostView.post {
            if (host.isDisposed ||
              !audioTracksReady ||
              generation != trackIdMap.currentGeneration ||
              sequence != postedSelectionSequence ||
              audioTrackId != targetId ||
              pendingSelectionId != targetId ||
              pendingSelectionKey != targetTrack ||
              pendingSelectionGeneration != generation ||
              pendingSelectionSequence != sequence ||
              trackIdMap.entryForId(targetId)?.selectionKey != targetTrack
            ) {
              return@post
            }
            val properties = HashMap<String, Any>()
            properties[Event.SELECTED_TRACK] = targetTrack
            host.videoView.eventEmitter.emit(EventType.SELECT_AUDIO_TRACK, properties)
          }
        }
      }
      AudioTrackSelectionAction.Clear -> {
        invalidatePendingSelection()
        clearAudioSelectionOverride()
        appliedSelectionKey = null
        appliedSelectionId = null
        clearedRequestId = audioTrackId
        clearedRequestGeneration = if (audioTrackId == null) null else trackIdMap.currentGeneration
        selectionClearPending = true
        setActiveTrackId(null)
      }
      AudioTrackSelectionAction.None -> Unit
    }
  }

  private fun setActiveTrackId(trackId: String?) {
    if (activeTrackId == trackId) return
    activeTrackId = trackId
    val label = trackId?.let { trackIdMap.entryForId(it)?.selectionKey }
    emitAudioTrackChanged(trackId.orEmpty(), label?.let { deriveLanguage(it) }.orEmpty())
  }

  private fun clearAudioSelectionOverride() {
    host.videoView.playback?.player?.let { player ->
      player.trackSelectionParameters = player.trackSelectionParameters
        .buildUpon()
        .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
        .build()
    }
  }

  private fun invalidatePendingSelection() {
    pendingSelectionId?.let { ignoredSelectionIds.add(it) }
    pendingSelectionKey = null
    pendingSelectionId = null
    pendingSelectionGeneration = null
    pendingSelectionSequence = null
    postedSelectionSequence += 1
  }

  private fun deriveLanguage(label: String): String {
    val candidate = label.substringBefore('(').trim()
    if (candidate.isEmpty()) return ""

    // Short form: a real ISO 639 code, optionally with a region/variant
    // subtag (e.g. "en", "es-MX"). This is what TrackSelectorHelper.
    // getAudioString reports for DASH delivery, which appends format.language
    // (a bare code) directly.
    if (candidate.matches(Regex("^[a-zA-Z]{2,3}(-[a-zA-Z0-9]+)*$"))) {
      val baseLang = candidate.substringBefore('-').lowercase(Locale.ROOT)
      if (baseLang in Locale.getISOLanguages()) {
        return candidate
      }
    }

    // Long form: a human-readable language name (e.g. "English", "Français").
    // Confirmed against the vendored exoplayer2-10.4.25 sources:
    // TrackSelectorHelper.getAudioString appends format.label directly for
    // HLS delivery — the manifest's human-readable NAME attribute, not a
    // code — so the short-code path above never matches typical HLS content,
    // which would otherwise leave `language` blank for most real streams.
    // Resolve by comparing against every known ISO language's own display
    // name, in English (labels are conventionally English regardless of
    // device locale) and in the device's default locale (in case the
    // manifest already names tracks in the viewer's language).
    for (isoLanguage in Locale.getISOLanguages()) {
      val locale = Locale.forLanguageTag(isoLanguage)
      if (locale.getDisplayLanguage(Locale.ENGLISH).equals(candidate, ignoreCase = true) ||
        locale.getDisplayLanguage(Locale.getDefault()).equals(candidate, ignoreCase = true)
      ) {
        return isoLanguage
      }
    }

    return ""
  }

  private fun emitAudioTracksAvailable() {
    val tracks = Arguments.createArray()
    trackIdMap.all().forEach { entry ->
      tracks.pushMap(
        Arguments.createMap().apply {
          putString("id", entry.id)
          putString("language", deriveLanguage(entry.selectionKey))
          putString("label", entry.selectionKey)
        },
      )
    }
    host.emitEvent(
      EVENT_AUDIO_TRACKS_AVAILABLE,
      Arguments.createMap().apply { putArray("tracks", tracks) },
    )
  }

  private fun emitAudioTrackChanged(id: String, language: String) {
    host.emitEvent(
      EVENT_AUDIO_TRACK_CHANGED,
      Arguments.createMap().apply {
        putString("id", id)
        putString("language", language)
      },
    )
  }

  override fun onDispose() {
    resetSelectionState()
  }

  private fun resetSelectionState() {
    trackIdMap.reset()
    audioTracksReady = false
    appliedSelectionKey = null
    appliedSelectionId = null
    pendingSelectionKey = null
    pendingSelectionId = null
    pendingSelectionGeneration = null
    pendingSelectionSequence = null
    ignoredSelectionIds.clear()
    clearedRequestId = null
    clearedRequestGeneration = null
    selectionClearPending = false
    activeTrackId = null
    postedSelectionSequence += 1
  }

  companion object {
    const val EVENT_AUDIO_TRACKS_AVAILABLE = "topAudioTracksAvailable"
    const val EVENT_AUDIO_TRACK_CHANGED = "topAudioTrackChanged"
  }
}
