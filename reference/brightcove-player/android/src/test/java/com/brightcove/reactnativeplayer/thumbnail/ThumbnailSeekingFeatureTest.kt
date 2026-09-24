package com.brightcove.reactnativeplayer.thumbnail

import org.junit.Assert.assertEquals
import org.junit.Test

class ThumbnailSeekingFeatureTest {
  @Test
  fun ownedPropsAreCorrect() {
    val feature = ThumbnailSeekingFeature()
    assertEquals(setOf("thumbnailSeekingEnabled"), feature.ownedProps)
  }

  @Test
  fun rewritesHttpThumbnailUrlToHttps() {
    assertEquals("https://cdn.example.com/t.vtt", secureThumbnailUrl("http://cdn.example.com/t.vtt"))
  }

  @Test
  fun rewritesUppercaseHttpSchemeToo() {
    assertEquals("https://cdn.example.com/t.vtt", secureThumbnailUrl("HTTP://cdn.example.com/t.vtt"))
  }

  @Test
  fun leavesAnAlreadySecureUrlUnchanged() {
    assertEquals("https://cdn.example.com/t.vtt", secureThumbnailUrl("https://cdn.example.com/t.vtt"))
  }

  @Test
  fun leavesANonHttpSchemeUnchanged() {
    assertEquals("file:///local/t.vtt", secureThumbnailUrl("file:///local/t.vtt"))
  }

  @Test
  fun preservesQueryStringAndPathWhenUpgradingScheme() {
    assertEquals(
      "https://cdn.example.com/path/t.vtt?token=abc",
      secureThumbnailUrl("http://cdn.example.com/path/t.vtt?token=abc"),
    )
  }
}
