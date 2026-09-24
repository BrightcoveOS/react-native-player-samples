# Captions and Subtitles

## Scope

The captions feature controls in-manifest text tracks: whether captions are on,
and which track is selected.

```ts
captionsEnabled?: boolean; // default false
captionTrackId?: string;   // opaque id from onCaptionsAvailable; unknown id keeps captions off

onCaptionsAvailable?: DirectEventHandler<{
  tracks: { id: string; language: string; label: string }[];
}>;
onCaptionTrackChanged?: DirectEventHandler<{
  id: string;    // '' means captions are off
  language: string;
}>;
```

Captions are a **controlled** surface: the app sets `captionsEnabled` and
`captionTrackId`, and the native selection is authoritative through
`onCaptionTrackChanged` — including a change made from the platform's own caption
menu.

Related features own separate props (in the same bridge family, but not this
feature):

- `sidecarcaptions` — `sidecarTracks`, `onSidecarTrackStatus` (app-supplied VTT
  tracks).
- `captionrendering` — `customCaptionRenderingEnabled`, `onCaptionCueChanged`
  (render captions yourself).

## Track identity

`captionTrackId` is opaque and **source-scoped**; it is never a language code and
must be passed back exactly as received from `onCaptionsAvailable`.

- **Android** selects captions by language, so the id is the language code and
  same-language variants (e.g. "English" and "English SDH", both `en`) collapse
  to the single selectable first-per-language entry. `label` is localized to the
  device locale.
- **iOS** selects per media option, so ids are namespaced by source generation
  (`<generation>:<index>`) and distinct same-language options remain separately
  selectable.
- An unknown or stale `captionTrackId` keeps captions **off** — the bridge never
  substitutes the first track. A stale id from a previous source can never match
  because the id carries the source generation (Android stamps the requested id
  with a selection generation; iOS namespaces the id).

## Selection semantics

- `captionsEnabled` alone (no id) enables the default/first track.
- `captionsEnabled` with a valid id selects that track.
- `captionsEnabled` false, or an unknown id, means captions off.
- On a source change the bridge emits an authoritative empty list and
  `onCaptionTrackChanged` with `''`, so a controlled UI cannot hold a stale
  selection across sources.

## Android

`CaptionsFeature` owns `captionsEnabled` and `captionTrackId`. It reads available
languages from `CAPTIONS_LANGUAGES`, deduplicates to the selectable
first-per-language subset while keeping each kept language's raw pre-dedup index
(the SDK's `selectCaptions(int)` resolves against the raw list), attaches the
caption-rendering overlay when tracks exist, and applies the selection once per
commit (`onPropsCommitted`) to avoid competing selections. `captionTrackId` is
stamped with the current `selectionGeneration` so a request that predates the
source is treated as unresolved (off).

## iOS

`BrightcoveCaptionsFeature` owns the same props, driving a legible
`AVMediaSelectionGroup`. It rebuilds options on `onSessionReady`, filters to
playable options (excluding forced-only subtitles), applies the selection through
`session.selectedLegibleMediaOption`, and treats `onSelectedLegibleMediaOption`
as the authoritative change signal. Pending events flush on
`onEventEmitterReady`. Ids are the generation-namespaced `<generation>:<index>`
form.

## Web

The Web bridge uses the Web SDK's text tracks. It acts only on `kind: 'captions'`
tracks, force-disables duplicate `kind: 'subtitles'` tracks from the VHS
pipeline, keeps captions off for an unknown id, and selects `mode: 'hidden'`
instead of `'showing'` when custom caption rendering is enabled. A selection made
through the SDK's own menu is not reverted. The feature catalog marks captions
Web support as **partial** and contributes the `SubsCapsButton` control-bar
button.

## Sample

`samples/player/closed-captions` plays a DRM-protected video with several caption
tracks and renders one chip per track from `onCaptionsAvailable` (plus an "Off"
chip). It never sends a language as an id, and it follows the native
`onCaptionTrackChanged` so a selection made from the platform menu is reflected
in the UI. Its bridge copy installs `captions`, `fullscreen`, and `drm`.

## Verification

- Captions sample typecheck, ESLint, and Jest: chip per track, distinct ids for
  same-language variants, off state, native-menu sync, source reset, opaque ids,
  and error handling.
- Web bridge coverage: off-to-off emits no spurious event, native subtitle
  tracks are force-disabled, a native-menu choice is not reverted, and custom cue
  rendering.
- Android `SidecarCaptionsFeatureTest` and `CaptionRenderingFeatureTest` (the
  sibling features).
- `scripts/check-bridge-copies.sh`.
- Android release build and iOS Release simulator build.

There is no Android or iOS unit test that drives `CaptionsFeature` directly
(selection/generation logic is exercised through the sample's Jest tests and
manual device runs).
