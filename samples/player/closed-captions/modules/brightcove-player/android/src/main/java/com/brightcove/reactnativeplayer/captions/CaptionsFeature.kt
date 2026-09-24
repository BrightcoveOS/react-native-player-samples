package com.brightcove.reactnativeplayer.captions

import com.brightcove.player.captioning.BrightcoveCaptionFormat
import com.brightcove.player.event.Event
import com.brightcove.player.event.EventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature
import com.facebook.react.bridge.Arguments
import java.util.Locale

/**
 * Closed captions: drives the SDK's caption state from the
 * captionsEnabled/captionTrackId props and reports the available tracks and the
 * active track to JS.
 *
 * Track identity: the Brightcove Android caption API selects by language code
 * (selectCaptions -> setLocaleCode -> the first track for that language), so a
 * track's cross-platform id here IS its language code, and the reported list
 * has one entry per language. Same-language variants (e.g. "English" and
 * "English SDH", both "en") are therefore not individually addressable on
 * Android — selecting that id yields the SDK's first track for the language.
 * (iOS, which has per-option selection, gives each variant a distinct id.)
 */
class CaptionsFeature : PlayerFeature {
  private lateinit var host: FeatureHost

  private var captionsEnabled = false
  // The requested track id (a language code on Android) or null for "no
  // specific track". Set in setProp, applied once per commit in onPropsCommitted.
  private var captionTrackId: String? = null
  // The source generation captionTrackId was set for (see setProp), or -1 once
  // invalidated by a source change. See captionTrackIdGeneration's use in
  // applyCaptionSelection.
  private var captionTrackIdGeneration = -1

  // Track ids available on the current video (language codes), from
  // CAPTIONS_LANGUAGES. Repopulated on every source change.
  private val trackIds = mutableListOf<String>()
  // trackIds is deduplicated (see below), but the SDK's own
  // selectCaptions(int) resolves its index against the RAW, non-deduplicated
  // per-track list (BrightcoveClosedCaptioningController.availableLanguages,
  // built by getLanguageTags() from the same underlying caption-source
  // enumeration CAPTIONS_LANGUAGES reports — same order, one entry per raw
  // track, no dedup). Selecting by trackIds.indexOf(target) would resolve
  // against the wrong (deduplicated) index space and silently select a
  // different track than the one just advertised to JS, for any id after the
  // first duplicate-language track. Keep the raw index of the FIRST
  // occurrence of each addressable language so selection targets the same
  // track getLanguageTags() would report as index 0 for that language.
  private val rawIndexByTrackId = mutableMapOf<String, Int>()
  private var captionsReady = false
  private var activeTrackId: String? = null
  // The selection that was actually applied last, so a no-op commit does not
  // re-post a redundant selection.
  private var appliedSelectionKey: String? = null
  // Bumped on every source reset. applyCaptionSelection posts to the view
  // handler; capturing the revision at post time and re-checking it inside the
  // runnable drops a selection computed for the previous video after a fast
  // source swap.
  private var selectionGeneration = 0

  override val ownedProps = setOf("captionsEnabled", "captionTrackId")

  override val exportedEvents = mapOf(
    EVENT_CAPTIONS_AVAILABLE to "onCaptionsAvailable",
    EVENT_CAPTION_TRACK_CHANGED to "onCaptionTrackChanged",
  )

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  // Stash prop values only; do NOT act per-prop. captionsEnabled and
  // captionTrackId together form one selection, so applying on each setter
  // would fire two competing selections (enabled=true selects the first track,
  // then trackId selects another) that race on Android's threaded sidecar
  // loads. onPropsCommitted applies the coalesced result once per transaction.
  override fun setProp(name: String, value: Any?) {
    when (name) {
      "captionsEnabled" -> captionsEnabled = requireNotNull(value as? Boolean) {
        "CaptionsFeature requires a Boolean for '$name'"
      }
      "captionTrackId" -> {
        captionTrackId = requireNotNull(value as? String) {
          "CaptionsFeature requires a String for '$name'"
        }.ifBlank { null }
        // Stamp which source this request belongs to. videoId/accountId/
        // policyKey are declared before captionTrackId in the ViewManager, so
        // for a commit that changes both the source and this prop together,
        // onSourceReset (via markSourceDirty) has already run and
        // selectionGeneration already reflects the NEW source by the time this
        // runs — the request is correctly stamped for the video it was set
        // alongside, not the one it is replacing.
        captionTrackIdGeneration = selectionGeneration
      }
      else -> error("CaptionsFeature does not own prop '$name'")
    }
  }

  override fun onPropsCommitted() {
    applyCaptionSelection()
  }

  override fun onSourceReset() {
    trackIds.clear()
    rawIndexByTrackId.clear()
    captionsReady = false
    appliedSelectionKey = null
    selectionGeneration += 1
    // A captionTrackId set for the outgoing source must not be reinterpreted
    // against the new source's track list. iOS enforces this by namespacing ids
    // with a source generation ("<gen>:<index>"), so a stale id can never match
    // (optionForId returns nil -> captions stay off, not a fallback to the
    // default track). Android's ids are bare language codes, so record which
    // source generation the currently-requested id belongs to and require a
    // match in applyCaptionSelection; a request that predates the current
    // source is treated as unresolved (off) exactly like an unknown id,
    // regardless of whether the new source happens to carry the same language.
    // Clear the raw value too (not just the generation stamp): a customer that
    // changes videoId without also changing captionTrackId in the same render
    // leaves this field holding the previous source's id until JS reacts to
    // the authoritative reset below and re-renders — clearing it here means
    // applyCaptionSelection (which onPropsCommitted can invoke before that JS
    // round-trip completes) has nothing stale to even attempt to resolve.
    captionTrackId = null
    captionTrackIdGeneration = -1
    // Emit an authoritative reset before the next source's tracks arrive: the
    // previous source's tracks no longer exist, so tell JS the list is empty
    // and nothing is active. Otherwise a surviving controlled captionTrackId
    // prop would leave JS believing a track is still selected across the source
    // change. setActiveTrackId emits only on change, so force it by clearing to
    // a sentinel first.
    emitCaptionsAvailable()
    if (activeTrackId != null) {
      activeTrackId = null
      emitCaptionTrackChanged("")
    }
  }

  override fun onRegisterPlaybackListeners() {
    // The SDK enumerates caption tracks once per video and announces the
    // available BCP-47 languages via CAPTIONS_LANGUAGES. Cache them (as track
    // ids), tell JS what is available, then apply any pending selection
    // (selection cannot happen before this event arrives).
    host.registerListener(EventType.CAPTIONS_LANGUAGES) { event ->
      trackIds.clear()
      rawIndexByTrackId.clear()
      val rawLanguages = (event.properties[Event.LANGUAGES] as? List<*>)
        ?.filterIsInstance<String>()
        ?.filter { it.isNotBlank() }
        .orEmpty()
      // The SDK selects captions by language code (selectCaptions ->
      // setLocaleCode -> the SDK's first track for that language), so a
      // language is the only addressable unit on Android. CAPTIONS_LANGUAGES
      // can list the same code twice (e.g. "English" and "English SDH", both
      // "en"); keeping both would advertise two tracks with the same id/React
      // key when only the first is selectable. Deduplicate to the selectable
      // first-per-language subset so every id reported to JS actually
      // resolves to a track. (iOS, which selects per option, exposes the
      // variants individually.) Record each kept language's RAW (pre-dedup)
      // index alongside it: the SDK's own selectCaptions(int) resolves its
      // index against this same raw, non-deduplicated list (rebuilt
      // internally by getLanguageTags() from the identical caption-source
      // enumeration), so selecting by a deduplicated index would target the
      // wrong track for any language after the first duplicate.
      rawLanguages.forEachIndexed { rawIndex, language ->
        if (language !in rawIndexByTrackId) {
          rawIndexByTrackId[language] = rawIndex
          trackIds.add(language)
        }
      }
      captionsReady = true
      // Create and attach the SDK's caption-rendering overlay. Without a media
      // controller the view does not set this up on its own, so selected
      // captions would load but never draw on screen.
      if (trackIds.isNotEmpty()) {
        host.videoView.setupClosedCaptioningRendering()
      }
      emitCaptionsAvailable()
      applyCaptionSelection()
    }
    // The user changed the active track through the SDK's own caption UI; mirror
    // the resulting track id (language) back to JS so onCaptionTrackChanged is
    // truthful regardless of who initiated the change. Only report an id that is
    // actually in the advertised list (trackIds is deduplicated, and the SDK's
    // reported language could in principle differ from an advertised code): JS
    // must never receive an active id it never saw in onCaptionsAvailable, so an
    // unrecognized language reports null (off) rather than a phantom id.
    host.registerListener(EventType.SELECT_CLOSED_CAPTION_TRACK) { event ->
      val format = event.properties[Event.CAPTION_FORMAT] as? BrightcoveCaptionFormat
      val language = format?.language()?.ifBlank { null }
      setActiveTrackId(language?.takeIf { it in trackIds })
    }
    host.registerListener(EventType.TOGGLE_CLOSED_CAPTIONS) { event ->
      val on = event.properties[Event.BOOLEAN] as? Boolean ?: return@registerListener
      if (!on) setActiveTrackId(null)
    }
  }

  // Drives the SDK's caption state from captionsEnabled/captionTrackId. Safe to
  // call before CAPTIONS_LANGUAGES arrives — it no-ops until the track list is
  // known, then runs again from the listener above.
  //
  // Selection goes through the closed-captioning controller's selectCaptions
  // (index 0 = off, index i+1 = the i-th RAW track — see rawIndexByTrackId),
  // not the view's setSubtitleLocale: the controller is the component
  // registered to emit SELECT_CLOSED_CAPTION_TRACK, so routing through it
  // avoids the SDK's "not permitted to emit" guard. The call is posted so it
  // runs on the view's handler rather than inside the Fabric prop-update
  // transaction.
  private fun applyCaptionSelection() {
    if (host.isDisposed || !captionsReady) return

    // Resolve the track to select:
    //  - a specific captionTrackId is honored only if it was set for the
    //    CURRENT source and the video has it; a request left over from a
    //    previous source (captionTrackIdGeneration mismatch, cleared by
    //    onSourceReset) leaves captions off rather than being reinterpreted
    //    against the new source's track list — see onSourceReset for why this
    //    matters even when the id happens to also exist on the new source.
    //    An id that simply is not on the current source likewise leaves
    //    captions off rather than substituting another track.
    //  - with captionsEnabled and no specific (current-source) id, use the
    //    first available track.
    val requested = captionTrackId?.takeIf { captionTrackIdGeneration == selectionGeneration }
    val target = if (captionsEnabled) {
      if (requested != null) requested.takeIf { it in trackIds } else trackIds.firstOrNull()
    } else {
      null
    }

    // Skip if this exact selection was already applied — avoids re-posting a
    // redundant (and race-prone) selection on an unrelated prop commit.
    val selectionKey = target ?: OFF_KEY
    if (selectionKey == appliedSelectionKey) return
    appliedSelectionKey = selectionKey

    // Use the RAW index (rawIndexByTrackId), not trackIds.indexOf: trackIds is
    // deduplicated but selectCaptions(int) resolves against the SDK's own
    // non-deduplicated per-track list, so indexing by the deduplicated
    // position would select the wrong track whenever a duplicate-language
    // track precedes the target.
    val trackIndex = target?.let { rawIndexByTrackId[it]?.plus(1) } ?: 0
    val generation = selectionGeneration

    host.hostView.post {
      if (host.isDisposed || !captionsReady || generation != selectionGeneration) {
        return@post
      }
      host.videoView.closedCaptioningController?.selectCaptions(trackIndex)
      host.requestHostLayout()
    }
  }

  private fun setActiveTrackId(trackId: String?) {
    if (activeTrackId == trackId) return
    activeTrackId = trackId
    emitCaptionTrackChanged(trackId.orEmpty())
  }

  // Human-readable name for a BCP-47 code, localized to the DEVICE locale (e.g.
  // "es" -> "Spanish" on an English device, not "español"); falls back to the
  // raw code. iOS labels come from the SDK localized to the device, so using
  // the device locale here keeps labels consistent across platforms.
  private fun displayLabelFor(languageTag: String): String {
    val locale = Locale.forLanguageTag(languageTag)
    return locale.getDisplayName(Locale.getDefault()).ifBlank { languageTag }
  }

  private fun emitCaptionsAvailable() {
    val tracks = Arguments.createArray()
    trackIds.forEach { id ->
      tracks.pushMap(
        Arguments.createMap().apply {
          // On Android the id is the language code (the SDK's selection key).
          putString("id", id)
          putString("language", id)
          putString("label", displayLabelFor(id))
        },
      )
    }
    host.emitEvent(
      EVENT_CAPTIONS_AVAILABLE,
      Arguments.createMap().apply { putArray("tracks", tracks) },
    )
  }

  private fun emitCaptionTrackChanged(trackId: String) {
    host.emitEvent(
      EVENT_CAPTION_TRACK_CHANGED,
      Arguments.createMap().apply {
        putString("id", trackId)
        // language mirrors the id on Android (metadata).
        putString("language", trackId)
      },
    )
  }

  companion object {
    private const val OFF_KEY = "\u0000off"
    const val EVENT_CAPTIONS_AVAILABLE = "topCaptionsAvailable"
    const val EVENT_CAPTION_TRACK_CHANGED = "topCaptionTrackChanged"
  }
}
