# Background Playback

## Scope

Background playback keeps audio (or audio-and-video) playing while the app is
backgrounded and exposes native lock-screen / notification controls. The bridge
exposes one opt-in prop:

```ts
backgroundPlaybackEnabled?: boolean; // default false
```

The prop **opts the player into** the native integration. It does not grant
background execution by itself: the app must also provide the platform's host
configuration (manifest, audio capability, and audio session), described below.

There is no background-playback event and no command. Playback state continues to
be observed through the ordinary `onPlay`/`onPause`/`onProgress` events, and
remote controls drive the same playback controller, so no separate JS state
machine is needed.

## Host configuration is required

`backgroundPlaybackEnabled` is a bridge opt-in, not a substitute for the host's
platform setup. Missing host configuration is a hard failure, not a silent
degradation:

- **Android** requires, in the app manifest, `FOREGROUND_SERVICE` and (API 34+)
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, plus the Brightcove playback-notification
  plugin and its `MediaPlaybackService` (the plugin declares the service through
  Android manifest merging). Android 13+ also requires a **runtime**
  `POST_NOTIFICATIONS` grant. The feature validates all of these when the prop is
  set and throws with the missing items rather than starting playback without a
  notification.
- **iOS** requires the `audio` background mode (`UIBackgroundModes`) and an
  `AVAudioSession` in the `.playback` category (the sample's `AppDelegate`
  configures `mode: .moviePlayback`). Without the audio session the app is
  suspended and playback stops; the bridge cannot grant that capability.

Because background playback is process/notification-scoped on Android, active
players are handed notification ownership one at a time; a second playing player
is queued and promoted when the current owner pauses or releases. An app with
several media players should keep one app-level owner rather than competing
handlers — the same guidance applies to iOS `MPRemoteCommandCenter`, which is a
process-wide singleton.

## Android

`BackgroundPlaybackFeature` owns `backgroundPlaybackEnabled` and reports
`keepsPlaybackAliveInBackground = enabled`, which is what makes the core's
Activity `onPause`/`onStop` teardown a no-op while enabled. On `DID_PLAY` it
acquires the process-wide notification ownership; on pause it offers to promote a
queued waiter; on stop/completed/error, and on source reset or dispose, it
releases ownership. Ownership attach/detach run on the main thread.

The notification is the SDK's `BackgroundPlaybackNotification`
(`BackgroundPlaybackNotification.getInstance`), configured for the audio, video,
live, and live-DVR stream types. The player is wired to it through
`ExoMediaPlayback.setPlaybackNotification`, and the notification receives the
playback with `setPlayback` then `show()`.

Disabling the prop mid-background is handled explicitly: the core's lifecycle
pause already ran (and was suppressed) while the feature was enabled, so flipping
the prop off calls `reevaluateBackgroundPolicy` — if the host is not foregrounded
it pauses playback directly, the same outcome the core's own `onPause` would have
produced.

## iOS

`BrightcoveBackgroundPlaybackFeature` owns `backgroundPlaybackEnabled` and
`keepsPlaybackAliveInBackground`. On enable it sets
`BCOVPlaybackController.allowsBackgroundAudioPlayback = YES`; on disable it
clears it and, if the host is not active, pauses directly (mirroring the Android
disable path).

While enabled and actually playing (`player.rate > 0`), the feature takes
process-wide remote-command ownership: it installs `MPRemoteCommandCenter`
handlers for play, pause, and `changePlaybackPosition` (seek), installs a
periodic time observer, and updates `MPNowPlayingInfoCenter` (title from the
video name, artist, duration, elapsed time, and playback rate). Only one feature
owns the shared command center at a time; ownership is requested on play, offered
to a queued player when the owner pauses, and released on end/terminate/error and
teardown.

## Web

Background playback is **not supported on Web** (the browser owns tab/background
media policy). The feature catalog marks it `unsupported`; there is no web build
for the sample.

## Sample

`samples/player/background-playback` plays one public demo video with
`backgroundPlaybackEnabled` gated on the Android 13+ notification permission. It
ships the complete host configuration this feature depends on: the Android
manifest permissions (the plugin contributes the service), and the iOS
`UIBackgroundModes` audio capability plus the `.playback` audio session in
`AppDelegate.swift`. On Android 13+, a denied notification permission disables
the opt-in and surfaces why.

Test flow: start playback, press Home or lock the device, then use the lock-screen
or notification controls; returning to the app should show the same state and
position.

## Verification

- Background-playback sample typecheck, ESLint, and Jest (prop wiring incl. the
  permission-gated value, lifecycle/progress chips, and the denied-permission
  path).
- Android `BackgroundPlaybackConfigurationTest` and `NotificationOwnershipStateTest`
  (manifest-permission rules per API level, and single-owner/waiter transitions).
- `scripts/check-bridge-copies.sh`.
- Android release build and iOS Release simulator build.
- Physical-device runtime: Android 14 (API 34) media notification/lock-screen
  play/pause/scrub while backgrounded, and iOS lock-screen play/pause/scrub with
  playback continuing while the app is backgrounded. Returning to each app kept
  the playback state and position synchronized.

Background audio remains a physical-device path: the simulator/emulator validates
build and wiring only.
