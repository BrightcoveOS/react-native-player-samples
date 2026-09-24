package com.brightcove.reactnativeplayer.sidecarcaptions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SidecarCaptionsFeatureTest {

  private fun track(
    url: String = "https://example.com/en.vtt",
    language: String = "en",
    label: String? = null,
  ) = SidecarTrack(url, language, label ?: language)

  @Test
  fun httpsUrlValidation() {
    assertTrue(isHttpsUrl("https://example.com/en.vtt"))
    assertTrue(isHttpsUrl("HTTPS://example.com/en.vtt"))
    assertFalse(isHttpsUrl("http://example.com/en.vtt"))
    assertFalse(isHttpsUrl("https:///no-host.vtt"))
    assertFalse(isHttpsUrl("ftp://example.com/en.vtt"))
    assertFalse(isHttpsUrl(""))
  }

  @Test
  fun bcp47Validation() {
    assertTrue(isValidBcp47Tag("en"))
    assertTrue(isValidBcp47Tag("zh-Hant-TW"))
    assertTrue(isValidBcp47Tag("es-419"))
    assertTrue(isValidBcp47Tag("qaa-Qaaa-QM"))
    assertFalse(isValidBcp47Tag("en-"))
    assertFalse(isValidBcp47Tag("toolongsubtagtoolongsubtag"))
    assertFalse(isValidBcp47Tag("e"))
    assertFalse(isValidBcp47Tag(""))
  }

  @Test
  fun rejectsInvalidTracksIndividually() {
    val failures = validateSidecarTracks(
      listOf(
        track(url = "http://insecure.example/en.vtt"),
        track(language = "en-"),
        track(url = "", language = "es"),
        track(language = "", url = "https://example.com/es.vtt"),
      ),
    )
    assertEquals(
      listOf("insecure_or_invalid_url", "invalid_language_tag", "missing_url", "missing_language_tag"),
      failures.map { it.second.nativeCode },
    )
  }

  @Test
  fun rejectsDuplicateLanguagesCaseInsensitively() {
    val failures = validateSidecarTracks(
      listOf(
        track(language = "en"),
        track(language = "EN"),
        track(language = "es"),
      ),
    )
    assertEquals(listOf("duplicate_language"), failures.map { it.second.nativeCode })
    assertEquals(2, validSidecarTracks(listOf(track(language = "en"), track(language = "EN"), track(language = "es"))).size)
  }

  @Test
  fun validTracksPassThroughUnchanged() {
    val tracks = listOf(
      track(language = "en", label = "English"),
      track(url = "https://example.com/es.vtt", language = "es-419", label = "Spanish"),
    )
    assertTrue(validateSidecarTracks(tracks).isEmpty())
    assertEquals(tracks, validSidecarTracks(tracks))
  }

  @Test
  fun labelDefaultsToLanguage() {
    val tracks = validSidecarTracks(listOf(track(label = null)))
    assertEquals("en", tracks.single().label)
  }
}
