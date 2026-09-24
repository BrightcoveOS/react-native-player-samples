package com.brightcove.reactnativeplayer.sourceloadingmodes

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SourceLoadingModesFeatureTest {
  @Test
  fun ownedPropsAreCorrect() {
    val feature = SourceLoadingModesFeature()
    assertEquals(
      setOf("videoReferenceId", "playlistId", "playlistReferenceId", "sourceUrl"),
      feature.ownedProps,
    )
  }

  @Test
  fun acceptsAValidHlsUrl() {
    assertTrue(
      SourceLoadingModesFeature.isValidHttpsStreamUrl(
        "https://d2zihajmogu5jn.cloudfront.net/bipbop-advanced/bipbop_16x9_variant.m3u8",
      ),
    )
  }

  @Test
  fun acceptsAValidMp4Url() {
    assertTrue(SourceLoadingModesFeature.isValidHttpsStreamUrl("https://cdn.example.com/video.mp4"))
  }

  @Test
  fun acceptsAnUppercaseHttpsScheme() {
    assertTrue(SourceLoadingModesFeature.isValidHttpsStreamUrl("HTTPS://cdn.example.com/video.mp4"))
  }

  @Test
  fun rejectsAnHttpUrl() {
    assertFalse(SourceLoadingModesFeature.isValidHttpsStreamUrl("http://cdn.example.com/video.mp4"))
  }

  @Test
  fun rejectsAnUnsupportedExtension() {
    assertFalse(SourceLoadingModesFeature.isValidHttpsStreamUrl("https://cdn.example.com/video.mkv"))
  }

  @Test
  fun rejectsAMalformedUrl() {
    assertFalse(SourceLoadingModesFeature.isValidHttpsStreamUrl("not a url"))
  }

  @Test
  fun rejectsAUrlWithNoHost() {
    assertFalse(SourceLoadingModesFeature.isValidHttpsStreamUrl("https:///video.mp4"))
  }

  @Test
  fun rejectsAnEmptyString() {
    assertFalse(SourceLoadingModesFeature.isValidHttpsStreamUrl(""))
  }
}
