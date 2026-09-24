# Supported samples

This repository ships a validated set of sample applications as
customer-supported. Every sample under `samples/player` is in the supported set
below.

## Support levels

- **Supported** — documented limitations, green CI on every platform it
  claims, and a manual device pass wherever the platform exposes a
  hardware-only path (DRM, Picture-in-Picture, offline DRM). Treated as stable
  for customers to copy.

## Supported set

| Sample | Android | iOS | Web | Feature demonstrated |
| --- | --- | --- | --- | --- |
| `basic-playback` | yes | yes | yes | Single-video playback, playback rate, volume/mute, audio tracks, fullscreen |
| `closed-captions` | yes | yes | yes | Caption track selection and the on/off controlled surface |
| `playlists` | yes | yes | — | Queue playback: auto-advance, next/previous, shuffle, repeat |
| `picture-in-picture` | yes | yes | yes | Picture-in-Picture entry, background entry, state events |
| `fullscreen` | yes | yes | — | Fullscreen transitions and `onFullscreenChanged` |
| `custom-controls` | yes | yes | — | Hiding native controls and driving transport from React Native |
| `drm` | yes | yes | partial | Widevine (Android) and FairPlay (iOS) protected playback |
| `offline-playback` | yes | yes | — | Durable downloads, local playback, removal |
| `ssai` | yes | yes | yes | Server-side ad insertion via `adConfigId` |
| `ads` | yes | yes | partial | Client-side ad insertion (CSAI) via a VMAP `adTagUrl` |
| `playback-state` | yes | yes | yes | Playback lifecycle/progress and live-DVR status, plus `seekToLiveEdge` |
| `background-playback` | yes | yes | — | Background audio with lock-screen/notification controls |

`yes` in a platform column means the sample carries that platform and CI builds
and tests it; where a platform exposes a hardware-only path, the sample's README
records which paths were exercised on a physical device. `partial` means the
platform is present but a capability differs from native (see the sample's
README); DRM on web relies on the web player's own encrypted-media support and
is not feature-tested in this repository.

## Rules for a supported sample

1. It installs `fullscreen` so both platforms behave the same.
2. It carries a README that states what it demonstrates and its known
   limitations.
3. It passes the repository guards (`scripts/check-bridge-copies.sh`,
   `scripts/check-doc-paths.sh`) and its own typecheck, lint, and test suite.
4. It is rebuilt and re-tested on hardware after any bridge change that affects
   it.

## README requirements

Every sample should make the following clear to a customer who opens its
directory without prior repository context:

1. **What it demonstrates:** the props, events, and commands the sample exists
   to show.
2. **The video/configuration it ships:** the exact configuration file, what demo
   content it uses, and what to replace before shipping.
3. **Running:** JavaScript install, iOS Pods, Metro, and the Android/iOS launch
   commands. A web-enabled sample also documents `npm run web` and
   `npm run web:build`.
4. **Platform notes:** meaningful Android, iOS, and web differences. Do not imply
   a platform path has been physically exercised unless it has.
5. **Known limitations:** device-only paths, initialization-only props, format
   or SDK constraints, and what CI does not validate.
6. **Support status:** a link back to this supported-set document.

Write the final state, not internal implementation history. Prefer customer
concepts over native class names unless the class is something the customer's
app must configure directly.

## Adding a sample

To add a sample, validate it on the physical platforms it claims, add its known
limitations to its README, and move its row into the table above. Physical-device-only
paths — DRM (Widevine/FairPlay) and real Picture-in-Picture lifecycle — must be
exercised on hardware; a simulator or emulator is not sufficient evidence.
