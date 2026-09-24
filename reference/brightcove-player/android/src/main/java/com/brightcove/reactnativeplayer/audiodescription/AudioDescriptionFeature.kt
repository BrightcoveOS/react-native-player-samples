package com.brightcove.reactnativeplayer.audiodescription

import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import com.brightcove.player.display.ExoPlayerVideoDisplayComponent
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments

/**
 * Selects and observes audio tracks explicitly marked as describing video.
 * Labels are never used as a substitute for the Media3 role flag.
 */
class AudioDescriptionFeature : PlayerFeature {
  private var host: FeatureHost? = null
  private var attachedPlayer: Player? = null
  private var playerListener: Player.Listener? = null
  private var previousAudioParameters: TrackSelectionParameters? = null
  private var sourceVideoId = ""
  private var requestedEnabled = false
  private var prepared = false
  private var lastAvailabilityKey: String? = null
  private var selectionRequestApplied = false
  private var explicitAudioOverride = false
  private var lastStateKey: String? = null
  private var sourceFailed = false

  override val ownedProps: Set<String> = setOf("audioDescriptionEnabled")

  override val exportedEvents: Map<String, String> = mapOf(
    EVENT_AUDIO_DESCRIPTION_AVAILABLE to "onAudioDescriptionAvailable",
    EVENT_AUDIO_DESCRIPTION_CHANGED to "onAudioDescriptionChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
    sourceFailed = false
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "audioDescriptionEnabled" -> {
        val requested = value as? Boolean
          ?: error("AudioDescriptionFeature requires a Boolean for '$name'")
        if (requestedEnabled != requested) {
          requestedEnabled = requested
          selectionRequestApplied = false
        }
        if (prepared) {
          attachPlayerListener()
          attachedPlayer?.let { publishCurrentState(it.currentTracks) }
        }
      }
      else -> error("AudioDescriptionFeature does not own prop '$name'")
    }
  }

  override fun onSourceReset() {
    val shouldEmitReset = lastAvailabilityKey != null || lastStateKey != null
    sourceFailed = false
    val playerBeforeReset = attachedPlayer
    detachPlayerListener()
    if (explicitAudioOverride && playerBeforeReset != null) {
      restorePreviousAudioSelection(playerBeforeReset)
    }
    previousAudioParameters = null
    sourceVideoId = ""
    prepared = false
    lastAvailabilityKey = null
    selectionRequestApplied = false
    explicitAudioOverride = false
    lastStateKey = null
    if (shouldEmitReset) {
      emitReset()
    }
  }

  override fun onRegisterPlaybackListeners() {
    val host = checkNotNull(host)

    listOf(EventType.BUFFERING_STARTED, EventType.DID_PLAY).forEach { eventType ->
      host.registerListener(eventType) { event ->
        updateSourceVideoId(event)
        attachPlayerListener()
      }
    }

    host.registerListener(EventType.BUFFERING_COMPLETED) { event ->
      updateSourceVideoId(event)
      attachPlayerListener()
      prepared = true
      attachedPlayer?.let { publishCurrentState(it.currentTracks) }
    }
  }

  override fun onPlaybackError() {
    sourceFailed = true
    val playerBeforeError = attachedPlayer
    detachPlayerListener()
    if (explicitAudioOverride && playerBeforeError != null) {
      restorePreviousAudioSelection(playerBeforeError)
      explicitAudioOverride = false
    }
  }

  override fun onDispose() {
    sourceFailed = true
    detachPlayerListener()
    previousAudioParameters = null
    host = null
  }

  private fun updateSourceVideoId(event: Event) {
    val videoId = (event.properties[Event.VIDEO] as? Video)?.id
    if (!videoId.isNullOrBlank()) {
      sourceVideoId = videoId
    }
  }

  private fun attachPlayerListener() {
    val host = host ?: return
    if (sourceFailed || host.isDisposed) return

    val display = host.videoView.videoDisplay as? ExoPlayerVideoDisplayComponent ?: return
    val player = display.getExoPlayer() ?: return
    if (attachedPlayer === player) return

    detachPlayerListener()
    val observedPlayer = player
    val listener = object : Player.Listener {
      override fun onTracksChanged(tracks: Tracks) {
        if (sourceFailed || attachedPlayer !== observedPlayer) return
        publishCurrentState(tracks)
      }
    }
    attachedPlayer = observedPlayer
    playerListener = listener
    sourceVideoId = sourceVideoId.ifBlank { player.currentMediaItem?.mediaId.orEmpty() }
    observedPlayer.addListener(listener)
  }

  private fun detachPlayerListener() {
    val player = attachedPlayer
    val listener = playerListener
    if (player != null && listener != null) {
      player.removeListener(listener)
    }
    attachedPlayer = null
    playerListener = null
  }

  private fun publishCurrentState(tracks: Tracks) {
    val host = host ?: return
    if (sourceFailed || !prepared || host.isDisposed) return

    val state = audioDescriptionState(tracks)
    if (lastAvailabilityKey != state.availabilityKey) {
      lastAvailabilityKey = state.availabilityKey
      host.emitEvent(
        EVENT_AUDIO_DESCRIPTION_AVAILABLE,
        Arguments.createMap().apply {
          putString("videoId", sourceVideoId)
          putBoolean("available", state.available)
        },
      )
    }

    val selectionApplied = if (!selectionRequestApplied) {
      applyRequestedSelection(attachedPlayer ?: return, state)
    } else {
      false
    }
    if (!selectionApplied) {
      emitChanged(state)
    }
  }

  private fun applyRequestedSelection(player: Player, state: AudioDescriptionState): Boolean {
    selectionRequestApplied = true
    if (requestedEnabled) {
      val choice = state.descriptiveChoice
      if (choice == null) {
        if (explicitAudioOverride) {
          val restored = restorePreviousAudioSelection(player)
          explicitAudioOverride = false
          return restored
        }
        selectionRequestApplied = false
        return false
      }
      if (state.enabled) {
        return false
      }
      if (!explicitAudioOverride) {
        previousAudioParameters = player.trackSelectionParameters
        val changed = setAudioOverride(player, choice)
        explicitAudioOverride = true
        return changed
      }
      return false
    }

    if (!explicitAudioOverride) return false

    val restored = restorePreviousAudioSelection(player)
    explicitAudioOverride = false
    return restored
  }

  private fun setAudioOverride(player: Player, choice: AudioChoice): Boolean {
    val current = player.trackSelectionParameters
    val next = current
      .buildUpon()
      .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
      .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
      .setOverrideForType(
        TrackSelectionOverride(choice.group.mediaTrackGroup, choice.trackIndices),
      )
      .build()
    if (current == next) return false
    player.trackSelectionParameters = next
    return true
  }

  private fun restorePreviousAudioSelection(player: Player): Boolean {
    val current = player.trackSelectionParameters
    val previous = previousAudioParameters
    val next = previous ?: current.buildUpon()
      .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
      .build()
    previousAudioParameters = null
    if (current == next) return false
    player.trackSelectionParameters = next
    return true
  }

  private fun emitChanged(state: AudioDescriptionState) {
    val host = host ?: return
    val stateKey = "$sourceVideoId|${state.enabled}|${state.available}"
    if (lastStateKey == stateKey) return
    lastStateKey = stateKey
    host.emitEvent(
      EVENT_AUDIO_DESCRIPTION_CHANGED,
      Arguments.createMap().apply {
        putString("videoId", sourceVideoId)
        putBoolean("enabled", state.enabled)
        putBoolean("available", state.available)
      },
    )
  }

  private fun emitReset() {
    val host = host ?: return
    host.emitEvent(
      EVENT_AUDIO_DESCRIPTION_AVAILABLE,
      Arguments.createMap().apply {
        putString("videoId", "")
        putBoolean("available", false)
      },
    )
    host.emitEvent(
      EVENT_AUDIO_DESCRIPTION_CHANGED,
      Arguments.createMap().apply {
        putString("videoId", "")
        putBoolean("enabled", false)
        putBoolean("available", false)
      },
    )
  }

  companion object {
    const val EVENT_AUDIO_DESCRIPTION_AVAILABLE = "topAudioDescriptionAvailable"
    const val EVENT_AUDIO_DESCRIPTION_CHANGED = "topAudioDescriptionChanged"
  }
}

internal data class AudioDescriptionState(
  val availabilityKey: String,
  val available: Boolean,
  val enabled: Boolean,
  val descriptiveChoice: AudioChoice?,
  val normalChoice: AudioChoice?,
)

internal data class AudioChoice(
  val group: Tracks.Group,
  val trackIndices: List<Int>,
)

internal fun audioDescriptionState(tracks: Tracks): AudioDescriptionState {
  val availabilityKey = tracks.groups
    .asSequence()
    .filter { it.type == C.TRACK_TYPE_AUDIO }
    .flatMap { group ->
      (0 until group.length).asSequence().map { index ->
        val format = group.getTrackFormat(index)
        listOf(
          format.id.orEmpty(),
          format.language.orEmpty(),
          format.label.orEmpty(),
          format.roleFlags.toString(),
          group.isTrackSupported(index).toString(),
        ).joinToString(":")
      }
    }
    .joinToString("|")

  val choices = tracks.groups
    .asSequence()
    .filter { it.type == C.TRACK_TYPE_AUDIO }
    .mapNotNull { group ->
      val supportedIndices = (0 until group.length).filter(group::isTrackSupported)
      if (supportedIndices.isEmpty()) return@mapNotNull null

      val descriptiveIndices = supportedIndices.filter { index ->
        hasAudioDescriptionRole(group.getTrackFormat(index).roleFlags)
      }
      val normalIndices = supportedIndices.filterNot { index ->
        hasAudioDescriptionRole(group.getTrackFormat(index).roleFlags)
      }
      AudioGroupChoices(
        descriptive = descriptiveIndices.takeIf { it.isNotEmpty() }?.let {
          AudioChoice(group, it)
        },
        normal = normalIndices.takeIf { it.isNotEmpty() }?.let {
          AudioChoice(group, it)
        },
        selectedDescription = descriptiveIndices.any(group::isTrackSelected),
      )
    }
    .toList()

  return AudioDescriptionState(
    availabilityKey = availabilityKey,
    available = choices.any { it.descriptive != null },
    enabled = choices.any { it.selectedDescription },
    descriptiveChoice = choices.firstNotNullOfOrNull { it.descriptive },
    normalChoice = choices.firstNotNullOfOrNull { it.normal },
  )
}

internal fun hasAudioDescriptionRole(roleFlags: Int): Boolean =
  roleFlags and C.ROLE_FLAG_DESCRIBES_VIDEO != 0

private data class AudioGroupChoices(
  val descriptive: AudioChoice?,
  val normal: AudioChoice?,
  val selectedDescription: Boolean,
)
