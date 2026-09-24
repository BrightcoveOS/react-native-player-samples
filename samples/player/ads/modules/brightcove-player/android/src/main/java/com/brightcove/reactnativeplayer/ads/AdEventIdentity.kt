package com.brightcove.reactnativeplayer.ads

import com.brightcove.player.event.Event
import com.brightcove.player.model.Video

/**
 * Video property key every in-repo loader stamps with the request generation
 * the video was resolved under — the core's catalog path and every feature
 * that adds a video (playlists, preloading, offline, DAI, source-loading
 * modes). Ad events carry the same Video the loader added, so the tag
 * identifies which request's content an ad event belongs to — see
 * BrightcovePlayerView's REQUEST_GENERATION_KEY.
 */
internal const val AD_EVENT_REQUEST_GENERATION_KEY = "com.brightcove.reactnativeplayer.requestGeneration"

/**
 * Pure decision for whether an IMA ad event belongs to the current source.
 *
 * The generation tag is authoritative: every loader this repository ships
 * stamps it, so a current-generation tag names content the active request
 * produced — including a video whose id differs from the videoId prop (the
 * preloaded next-up item) or that has no videoId at all (a source a feature
 * owns: a videoIds queue, a source-loading mode, an offline download) — while
 * a stale tag names a superseded request and is rejected. The core bumps the
 * generation before it resets or disposes features, so no tagged video from a
 * torn-down source can pass. An untagged video keeps the legacy id checks so
 * ordinary SDK-delivered events still match; with no source active, nothing
 * does.
 */
internal fun isCurrentAdEvent(
  event: Event,
  sourceActive: Boolean,
  sourceVideoId: String,
  sourceVideo: Video?,
  currentRequestGeneration: Int,
): Boolean {
  if (!sourceActive) return false
  val eventVideo = event.properties[Event.VIDEO] as? Video ?: return false
  val eventGeneration = eventVideo.properties[AD_EVENT_REQUEST_GENERATION_KEY] as? Int
  if (eventGeneration != null) {
    return eventGeneration == currentRequestGeneration
  }
  if (sourceVideoId.isEmpty()) return false
  if (eventVideo.id == sourceVideoId) return true
  return sourceVideo?.let { eventVideo === it || eventVideo.id == it.id } == true
}
