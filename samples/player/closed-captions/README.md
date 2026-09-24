# Closed Captions

A standalone bare React Native app that controls captions on a Brightcove video.
It embeds its own copy of the bridge under `modules/brightcove-player` and
consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

## What it demonstrates

- Turning captions on and off with `captionsEnabled`.
- Selecting a track by its opaque id with `captionTrackId` (from
  `onCaptionsAvailable`), never by language.
- Tracking the active track with `onCaptionTrackChanged`, including when the
  user changes it through the player's own caption menu, so the React Native
  UI stays in sync.
- Fullscreen entry and exit alongside the caption controls.

## The video it ships

Configuration lives in `src/playerConfig.ts`. It points at a DRM-protected
video that carries several caption tracks, so the bridge copy installs the
`drm` feature. Because the video is encrypted, its frames are **black in
screenshots and screen recordings** — watch captions on the device itself.

Swap in your own account, policy key, and video id in `src/playerConfig.ts`.
Set a friendly **Label** on each text track in Video Cloud if you want readable
names in the UI; otherwise the sample shows the track's language code.

## Running

```sh
# JavaScript dependencies (installs the embedded bridge module too)
npm install

# iOS native dependencies
bundle install
cd ios && bundle exec pod install && cd ..

# Start Metro
npm run start

# Run the app
npm run android
npm run ios
```

## Platform notes

- iOS selects an exact legible media option, so same-language variants
  ("English" and "English SDH") are individually selectable.
- Android selects by language code, so same-language variants collapse to one
  selectable track; its track ids are language codes.
- Android fetches sidecar caption files over cleartext HTTP from Brightcove's
  CDN by default. This sample ships a `network_security_config.xml` that allows
  cleartext only for `brightcovecdn.com`; tighten it for production.
- **Web:** captions run through the web player's text-track list. Track ids come
  from the Playback API and same-language variants are handled differently from
  Android, so select by the ids the web build reports rather than by language.

## Known limitations

- Track ids are opaque. Treat them as tokens and echo them back unchanged.
- iOS DRM playback is device-only: FairPlay cannot decrypt in the Simulator.

## Further reading

- [Captions and subtitles contract](../../../docs/captions.md)
