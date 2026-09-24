# Fullscreen

A standalone bare React Native app that reports Brightcove fullscreen state. It
embeds its own copy of the bridge under `modules/brightcove-player` and consumes
it through React Native autolinking as `@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

## What it demonstrates

- Entering the native player's fullscreen screen mode and returning to windowed.
- Reporting completed screen-mode transitions through `onFullscreenChanged`.
- Entering and exiting fullscreen imperatively with the `enterFullscreen` and
  `exitFullscreen` commands.

The native Brightcove controls own the transition. React Native reports the
completed screen mode; the host app still owns orientation and navigation
policy. This sample does not change orientation by itself.

On iOS, the fullscreen button is placed at the top-right of the presented
player so it stays reachable while the player covers the screen.

## The video it ships

Configuration is defined in `App.tsx`. It points at a DRM-protected video, so
the bridge copy installs the `drm` feature. Because the video is encrypted, its
frames are **black in screenshots and screen recordings** — watch it on the
device.

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

- Android reparents the player into a fullscreen layout; the bridge performs
  the layout change and keeps playback across the transition.
- iOS uses the SDK's native fullscreen presentation.

## Known limitations

- Orientation is intentionally left to the host app; this sample does not force
  landscape.
- iOS DRM playback is device-only.

## Further reading

- [Fullscreen state and command contract](../../../docs/fullscreen.md)
