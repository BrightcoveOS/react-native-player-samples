# Background Playback

Standalone bare React Native application demonstrating Brightcove playback that
continues as audio when the app is backgrounded and exposes native notification
or lock-screen controls. It embeds its own copy of the bridge under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

It shows how one prop opts a player into the native background integration:

- `backgroundPlaybackEnabled` enables the SDK's background-audio playback, media
  notification (Android), and lock-screen remote controls (iOS).
- Playback state and position continue to be observed through `onPlay` /
  `onPause` / `onProgress`, and the remote controls drive the same controller, so
  no separate JavaScript state machine is needed.
- On Android 13+, the sample requests `POST_NOTIFICATIONS` at runtime and only
  enables the opt-in when it is granted.

## The video it ships

Configuration lives in `src/playerConfig.ts`: a demo account, policy key, and
video id. Replace them with your own before shipping. The bundled account is a
demonstration account.

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

## Host configuration

`backgroundPlaybackEnabled` opts the player into the native integration; it does
not grant background execution by itself. This sample ships the required host
setup so it can be copied as a complete starting point:

- **Android:** `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` in the
  manifest (plus `POST_NOTIFICATIONS`), and the Brightcove playback-notification
  plugin and its `MediaPlaybackService`. The plugin contributes the service via
  Android manifest merging; the permissions are declared in `AndroidManifest.xml`.
- **iOS:** the `audio` background mode (`UIBackgroundModes`) in `Info.plist`, and
  an `AVAudioSession` in the `.playback` category configured in
  `ios/BackgroundPlayback/AppDelegate.swift`.

Production apps must review notification-permission UX, audio interruptions,
route changes, metadata, and their own background-execution policy. If an app has
multiple media players, they should share one app-level remote-command / Now
Playing coordinator rather than installing competing handlers.

## Platform notes

- Android uses the Brightcove playback-notification plugin; ownership of the
  process-wide notification is handed to one active player at a time.
- iOS uses `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`.
- There is no web build: the browser owns tab/background media policy.

## Known limitations

- Background audio is a physical-device path (verified on Android 14 and iOS);
  the simulator/emulator validates build and wiring only.
- A missing host-configuration item (permission, service, or audio session)
  fails loudly rather than starting playback without a notification or with no
  background justification.

## Further reading

- [Background playback contract](../../../docs/background-playback.md)
