package com.brightcove.reactnativeplayer.sidecarcaptions

/**
 * One externally-hosted caption track requested through the sidecarTracks prop.
 */
data class SidecarTrack(
  val url: String,
  val language: String,
  val label: String,
)

internal sealed class SidecarValidationError(val nativeCode: String) {
  data object MissingUrl : SidecarValidationError("missing_url")
  data object MissingLanguage : SidecarValidationError("missing_language_tag")
  data object InsecureUrl : SidecarValidationError("insecure_or_invalid_url")
  data object InvalidLanguage : SidecarValidationError("invalid_language_tag")
  data object DuplicateLanguage : SidecarValidationError("duplicate_language")
}

/**
 * Parses the plain List<Map<String, String>> the ViewManager forwards for the
 * sidecarTracks prop into typed tracks. The manager stays free of feature
 * imports so subset bridge copies that omit this feature still compile.
 */
internal fun parseSidecarTracks(value: List<*>): List<SidecarTrack> =
  value.mapNotNull { raw ->
    val map = raw as? Map<*, *> ?: return@mapNotNull null
    val url = map["url"] as? String
    val language = map["language"] as? String
    if (url.isNullOrBlank() || language.isNullOrBlank()) return@mapNotNull null
    val label = (map["label"] as? String)?.ifBlank { null } ?: language
    SidecarTrack(url, language, label)
  }

internal fun validateSidecarTracks(tracks: List<SidecarTrack>): List<Pair<SidecarTrack, SidecarValidationError>> {
  val failures = mutableListOf<Pair<SidecarTrack, SidecarValidationError>>()
  val seenLanguages = mutableSetOf<String>()
  tracks.forEach { track ->
    when {
      track.url.isBlank() -> failures += track to SidecarValidationError.MissingUrl
      track.language.isBlank() -> failures += track to SidecarValidationError.MissingLanguage
      !isHttpsUrl(track.url) -> failures += track to SidecarValidationError.InsecureUrl
      !isValidBcp47Tag(track.language) -> failures += track to SidecarValidationError.InvalidLanguage
      !seenLanguages.add(track.language.lowercase()) -> failures += track to SidecarValidationError.DuplicateLanguage
    }
  }
  return failures
}

internal fun validSidecarTracks(tracks: List<SidecarTrack>): List<SidecarTrack> =
  validateSidecarTracks(tracks).let { failures ->
    val failed = failures.map { it.first }.toSet()
    tracks.filterNot { failed.contains(it) }
  }

internal fun isHttpsUrl(url: String): Boolean {
  if (!url.startsWith("https://", ignoreCase = true)) return false
  val host = url.drop("https://".length).substringBefore('/').substringBefore(':')
  return host.isNotBlank() && host.contains('.')
}

internal fun isValidBcp47Tag(tag: String): Boolean =
  BCP47_REGEX.matches(tag)

private val BCP47_REGEX = Regex("^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$")
