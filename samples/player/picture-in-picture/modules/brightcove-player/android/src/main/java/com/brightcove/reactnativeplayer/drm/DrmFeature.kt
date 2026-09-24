package com.brightcove.reactnativeplayer.drm

import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature

/**
 * Widevine DRM.
 *
 * On Android there is intentionally almost nothing to do: the Brightcove
 * ExoPlayer integration (the exoplayer2 dependency this bridge already pulls
 * in) detects a Widevine-packaged DASH source from the Playback API response
 * and negotiates the licence with Brightcove's licence server automatically —
 * verified by playing a Widevine-protected video through the unmodified core.
 * Licence/DRM failures already surface through the core's normalized
 * PlaybackException.errorCode mapping as `code: "drm"`.
 *
 * This feature therefore owns no props and registers no listeners. It exists
 * so a bridge copy can declare DRM support symmetrically with iOS (where
 * FairPlay does require wiring) and so the sample's registry, the guard, and
 * the feature catalog treat DRM as one cross-platform feature. It is the
 * documented seam for any Android-side DRM work that does become necessary
 * (e.g. custom licence headers or offline licences).
 */
class DrmFeature : PlayerFeature {
  override val ownedProps: Set<String> = emptySet()
  override val exportedEvents: Map<String, String> = emptyMap()

  override fun attach(host: FeatureHost) {
    // No-op: Widevine is auto-negotiated by the SDK. See the class comment.
  }

  override fun setProp(name: String, value: Any?) {
    error("DrmFeature owns no props; received '$name'")
  }
}
