# Picture-in-Picture

A standalone bare React Native app that keeps a Brightcove video playing in a
floating window. It embeds its own copy of the bridge under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

## What it demonstrates

- Enabling Picture-in-Picture with `pictureInPictureEnabled`.
- Entering PiP from the player control or by sending the app to the background.
- Tracking PiP state with `onPictureInPictureModeChanged`.
- Fullscreen entry and exit alongside the PiP control.

The player fills the screen and the sample's text sits in a translucent overlay
above it. A full-bleed player is what lets the PiP window show the video and
nothing else.

## The video it ships

Configuration lives in `src/playerConfig.ts`. It points at a DRM-protected
video, so the bridge copy installs the `drm` feature. Because the video is
encrypted, its frames are **black in screenshots and screen recordings** — that
is content protection working, not a fault.

Replace the account, policy key, and video id with your own content. If your
video is not DRM-protected, remove `drm` from this sample's bridge feature list
and re-assemble it (see
[`docs/running-samples.md`](../../../docs/running-samples.md)).

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

- **Android:** PiP works on the emulator. The host Activity must declare
  `android:supportsPictureInPicture="true"` and forward `onUserLeaveHint` and
  `onPictureInPictureModeChanged` to the SDK; this sample's `MainActivity` does
  both.
- **iOS:** PiP does not activate on the Simulator. Verify it on a physical
  device. The app needs the audio background mode and a playback audio session
  for the PiP window to keep playing when backgrounded.
- **Web:** PiP uses the browser's native Picture-in-Picture API, including
  Safari's prefixed presentation-mode path, rather than the native SDKs.

## Known limitations

- Picture-in-Picture is a device feature; a simulator or emulator does not prove
  the iOS path.
- DRM frames are black under capture by design.

## Further reading

- [Picture-in-Picture feature contract](../../../docs/picture-in-picture.md)
