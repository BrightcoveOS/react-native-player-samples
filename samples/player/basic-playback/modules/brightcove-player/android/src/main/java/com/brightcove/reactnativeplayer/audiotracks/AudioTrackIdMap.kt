package com.brightcove.reactnativeplayer.audiotracks

internal data class AudioTrackEntry(
  val id: String,
  val selectionKey: String,
)

internal sealed class AudioTrackSelectionAction {
  data class Select(val entry: AudioTrackEntry) : AudioTrackSelectionAction()
  data object Clear : AudioTrackSelectionAction()
  data object None : AudioTrackSelectionAction()
}

internal class AudioTrackIdMap {
  private var generation = 0
  private var entries: List<AudioTrackEntry> = emptyList()

  val currentGeneration: Int
    get() = generation

  fun reset() {
    generation += 1
    entries = emptyList()
  }

  fun replace(selectionKeys: List<String>) {
    entries = selectionKeys.mapIndexed { index, selectionKey ->
      AudioTrackEntry("$generation:$index", selectionKey)
    }
  }

  fun all(): List<AudioTrackEntry> = entries

  fun entryForId(id: String): AudioTrackEntry? = entries.firstOrNull { it.id == id }

  fun entryForSelectionKey(selectionKey: String): AudioTrackEntry? =
    entries.firstOrNull { it.selectionKey == selectionKey }

  fun selectionAction(
    requestedId: String?,
    appliedId: String?,
    appliedSelectionKey: String?,
  ): AudioTrackSelectionAction {
    if (requestedId.isNullOrEmpty()) {
      return if (appliedSelectionKey == null) {
        AudioTrackSelectionAction.None
      } else {
        AudioTrackSelectionAction.Clear
      }
    }

    val entry = entryForId(requestedId) ?: return AudioTrackSelectionAction.Clear
    return if (entry.id == appliedId && entry.selectionKey == appliedSelectionKey) {
      AudioTrackSelectionAction.None
    } else {
      AudioTrackSelectionAction.Select(entry)
    }
  }
}
