package com.brightcove.reactnativeplayer.ads

import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.player.model.Video
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the ad-event identity rule: a current-generation tag is authoritative
 * (the preloaded next-up item has a different id but carries the active
 * generation, and a feature-owned source has no videoId at all), a stale tag
 * is rejected, an untagged video falls back to the legacy source-id checks,
 * and nothing is current while no source is active.
 */
class AdEventIdentityTest {
  private fun eventWith(video: Video): Event =
    Event(EventType.AD_STARTED).apply { properties[Event.VIDEO] = video }

  @Test
  fun currentGenerationTagAcceptsADifferentVideoId() {
    // The preloaded next-up item: resolved under the active request, tagged
    // at insert, but its id differs from the sourceVideoId prop.
    val preloaded = Video(mapOf("id" to "next-video", AD_EVENT_REQUEST_GENERATION_KEY to 7))
    assertTrue(
      isCurrentAdEvent(
        event = eventWith(preloaded),
        sourceActive = true,
        sourceVideoId = "current-video",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun staleGenerationTagIsRejectedEvenWhenIdsMatch() {
    val stale = Video(
      mapOf(
        "id" to "current-video",
        AD_EVENT_REQUEST_GENERATION_KEY to 6,
      ),
    )
    assertFalse(
      isCurrentAdEvent(
        event = eventWith(stale),
        sourceActive = true,
        sourceVideoId = "current-video",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun untaggedVideoFallsBackToSourceIdMatch() {
    val sameId = Video(mapOf("id" to "current-video"))
    assertTrue(
      isCurrentAdEvent(
        event = eventWith(sameId),
        sourceActive = true,
        sourceVideoId = "current-video",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun untaggedEventWithoutSourceVideoPropertyIsRejected() {
    assertFalse(
      isCurrentAdEvent(
        event = Event(EventType.AD_STARTED),
        sourceActive = true,
        sourceVideoId = "current-video",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun noActiveSourceRejectsEverything() {
    // Reset or disposed: even a current-generation tag is not attributable.
    val tagged = Video(mapOf("id" to "current-video", AD_EVENT_REQUEST_GENERATION_KEY to 7))
    assertFalse(
      isCurrentAdEvent(
        event = eventWith(tagged),
        sourceActive = false,
        sourceVideoId = "current-video",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun currentTagIsAcceptedForAFeatureOwnedSourceWithoutAVideoId() {
    // A videoIds queue item, a source-loading-mode video or an offline
    // download: the source is active but has no videoId, and the loader's
    // tag is what names it.
    val queueItem = Video(mapOf("id" to "queue-item-2", AD_EVENT_REQUEST_GENERATION_KEY to 7))
    assertTrue(
      isCurrentAdEvent(
        event = eventWith(queueItem),
        sourceActive = true,
        sourceVideoId = "",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun staleTagIsRejectedForAFeatureOwnedSourceWithoutAVideoId() {
    val staleQueueItem = Video(mapOf("id" to "queue-item-2", AD_EVENT_REQUEST_GENERATION_KEY to 6))
    assertFalse(
      isCurrentAdEvent(
        event = eventWith(staleQueueItem),
        sourceActive = true,
        sourceVideoId = "",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun untaggedVideoWithoutASourceVideoIdIsRejected() {
    val untagged = Video(mapOf("id" to "some-video"))
    assertFalse(
      isCurrentAdEvent(
        event = eventWith(untagged),
        sourceActive = true,
        sourceVideoId = "",
        sourceVideo = null,
        currentRequestGeneration = 7,
      ),
    )
  }

  @Test
  fun sourceIdentityFallbackStillMatches() {
    val sourceVideo = Video(mapOf("id" to "current-video"))
    val sameInstance = Video(mapOf("id" to "current-video"))
    // No tag, different id than the prop: the identity/id fallback via
    // sourceVideo still accepts the SDK's own instance.
    assertTrue(
      isCurrentAdEvent(
        event = eventWith(sourceVideo),
        sourceActive = true,
        sourceVideoId = "some-other-video",
        sourceVideo = sameInstance,
        currentRequestGeneration = 7,
      ),
    )
  }
}
