# Audio Tracks

## Scope

Audio-track selection is a controlled player surface:

```ts
audioTrackId?: string; // opaque id from onAudioTracksAvailable; '' restores default

onAudioTracksAvailable?: DirectEventHandler<{
  tracks: { id: string; language: string; label: string }[];
}>;
onAudioTrackChanged?: DirectEventHandler<{
  id: string;
  language: string;
}>;
```

The app renders the available tracks, passes one opaque id back as
`audioTrackId`, and follows the authoritative `onAudioTrackChanged` event —
including a selection made through the SDK's own control menu. Empty id restores
the SDK's automatic/default selection.

## Track identity

Ids are **opaque and source-scoped**. They are not language codes and must be
passed back unchanged.

- **Android:** ids are `<generation>:<index>` entries built from the SDK's raw
  selection keys; same-language role variants remain distinct when their raw
  keys differ.
- **iOS:** ids are `<sourceGeneration>:<index>` entries over playable audible
  media-selection options. A stale/wrong-generation id resets to automatic
  selection instead of selecting a coincidentally equal index on the new source.
- **Web:** ids come from the Web SDK's audio-track objects. The bridge captures
  the initially enabled id as the default and restores it when the controlled
  id clears.

On source reset the bridge emits an empty track list and an empty active id, so a
controlled UI cannot retain a stale selection.

## Android

`AudioTracksFeature` owns `audioTrackId`. The SDK's `AUDIO_TRACKS` event replaces
the generation-scoped `AudioTrackIdMap`; `SELECTED_TRACK` establishes the
initial/default id; `SELECT_AUDIO_TRACK` confirms the requested selection. The
selection is posted with generation and sequence guards, so a request racing a
source change cannot select a track on the new source. Clearing the prop removes
Media3 audio overrides. Language is derived from the SDK selection key; the
label remains the SDK key. The host layout is refreshed after a confirmed
selection.

## iOS

`BrightcoveAudioTracksFeature` reads the audible `AVMediaSelectionGroup`, filters
to playable options, and assigns generation-scoped ids. It selects through the
Brightcove playback session (not the raw `AVPlayerItem`), uses the session's
display name for `label`, and derives the BCP-47 language from the media option.
`onSelectedAudibleMediaOption` is the authoritative change callback. Clearing or
passing a stale id calls `selectAudibleMediaOptionAutomatically`.

## Web

The Web bridge mirrors the Web SDK's audio tracks (`id`, `kind`, `language`,
`label`, `enabled`). `audioTrackId` selects a matching track through
`selectAudioTrack`; clearing restores the startup default. Track-list and active
selection events are signature-deduplicated, and a choice made through the Web
SDK's own `AudioTrackButton` menu is not reverted. The feature catalog marks
Audio Tracks Web support as **partial** because browser/media-pipeline audio-track
support varies, and contributes `AudioTrackButton` to the control bar.

## Sample

`samples/player/basic-playback` displays the available audio tracks as buttons,
passes the chosen opaque id back through `audioTrackId`, and shows the active id
from `onAudioTrackChanged`. Audio tracks are one capability of the supported
basic-playback sample; there is no separate audio-tracks sample.

## Verification

- Android `AudioTrackIdMapTest`: source-scoped stale-id rejection,
  same-language role variants, clear/reset, and the select/clear/stale/pending
  state machine.
- Basic-playback Jest: available tracks render, selecting a button updates
  `audioTrackId`, native-menu changes are reflected, source reset clears the
  controlled selection, and stale ids are not reused.
- Web bridge test: an audio track selected through the SDK's own menu is not
  reverted.
- `scripts/check-bridge-copies.sh`.
- Android release build and iOS Release simulator build.
