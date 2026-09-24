package com.brightcove.reactnativeplayer.sourceloadingmodes

/**
 * The four mutually exclusive source-loading mode props, kept in one place so
 * mutual exclusivity is a pure, unit-testable rule rather than inline setProp
 * logic.
 *
 * React Native only delivers props that changed. A caller switching from
 * videoReferenceId to playlistId therefore sends the new mode but not the old
 * one being cleared, and Fabric may apply any changed props in either order.
 * Selecting a non-empty mode clears the others; clearing a mode touches only
 * its own field, so a late old-mode="" cannot erase a newly-selected mode.
 */
internal data class SourceLoadingModeSelection(
  val videoReferenceId: String = "",
  val playlistId: String = "",
  val playlistReferenceId: String = "",
  val sourceUrl: String = "",
) {
  fun currentValue(prop: String): String = when (prop) {
    "videoReferenceId" -> videoReferenceId
    "playlistId" -> playlistId
    "playlistReferenceId" -> playlistReferenceId
    "sourceUrl" -> sourceUrl
    else -> error("SourceLoadingModesFeature does not own prop '$prop'")
  }

  fun apply(prop: String, value: String): SourceLoadingModeSelection {
    // Validate before the non-empty constructor branch: comparing prop names in
    // each field expression alone would silently turn an unknown prop into an
    // all-empty selection.
    currentValue(prop)
    if (value.isNotEmpty()) {
      return SourceLoadingModeSelection(
        videoReferenceId = if (prop == "videoReferenceId") value else "",
        playlistId = if (prop == "playlistId") value else "",
        playlistReferenceId = if (prop == "playlistReferenceId") value else "",
        sourceUrl = if (prop == "sourceUrl") value else "",
      )
    }
    return when (prop) {
      "videoReferenceId" -> copy(videoReferenceId = "")
      "playlistId" -> copy(playlistId = "")
      "playlistReferenceId" -> copy(playlistReferenceId = "")
      "sourceUrl" -> copy(sourceUrl = "")
      else -> error("SourceLoadingModesFeature does not own prop '$prop'")
    }
  }

  fun activeModeCount(): Int =
    listOf(videoReferenceId, playlistId, playlistReferenceId, sourceUrl).count { it.isNotEmpty() }

  /**
   * Whether the selected mode resolves through the Playback API and therefore
   * requires accountId + policyKey. A direct URL is self-contained; the
   * reference and playlist modes are not.
   */
  fun requiresCredentials(): Boolean =
    playlistId.isNotEmpty() || playlistReferenceId.isNotEmpty() || videoReferenceId.isNotEmpty()
}
