# Custom Controls

A standalone bare React Native app that hides the native player controls and
drives playback from React Native. It embeds its own copy of the bridge under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

## What it demonstrates

- Showing or hiding the native controls container with `controlsEnabled`.
- Driving volume and mute from React Native (`volume`, `muted`).
- Entering and exiting fullscreen from React Native.

### Fullscreen with hidden controls

When fullscreen is requested while the native controls are hidden, the sample
first enables them so the presented player contains the SDK's own exit control,
then restores the hidden preference after fullscreen exits. A React Native
button outside the player is not reachable from iOS's fullscreen modal or
Android's Activity-root overlay, so an app that hides the native controls must
provide an equivalent exit path inside its own fullscreen surface.

## The video it ships

Configuration lives in `src/playerConfig.ts`. It points at a DRM-protected
video, so the bridge copy installs the `drm` feature. Because the video is
encrypted, its frames are **black in screenshots and screen recordings** — watch
it on the device.

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

- **Android:** control visibility is managed through the SDK's media controller;
  a request-layout pass is triggered so the change applies under Fabric.
- **iOS:** control visibility is managed through the player view's controls
  container.

## Known limitations

- Hiding the native controls removes the built-in fullscreen exit affordance;
  the sample supplies its own, and so must a customer app.
- iOS DRM playback is device-only.

## Further reading

- [Native-controls feature contract](../../../docs/controls.md)
