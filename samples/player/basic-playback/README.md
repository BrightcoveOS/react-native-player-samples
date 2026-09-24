# Basic Playback

A standalone bare React Native app that plays a single Brightcove video through
the Fabric component. It embeds its own copy of the bridge under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

## What it demonstrates

- Playing one video by `videoId`.
- Volume and mute driven from React Native (`volume`, `muted`).
- Playback-rate selection (`playbackRate`).
- Audio-track selection (`audioTrackId`, `onAudioTracksAvailable`,
  `onAudioTrackChanged`).
- Fullscreen entry and exit, with the `onFullscreenChanged` state event.
- Ready and error reporting (`onReady`, `onError`).

## The video it ships

Configuration lives in `src/playerConfig.ts`. It points at a DRM-protected
video, so the bridge copy installs the `drm` feature. Because the video is
encrypted, its frames are **black in screenshots and screen recordings** — that
is content protection working, not a fault; watch it on the device.

To use your own content, replace the account ID, policy key, and video ID in
`src/playerConfig.ts`. If your video is not DRM-protected, remove `drm` from
this sample's bridge feature list and re-assemble it (see
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

- Android and iOS play through the Brightcove native player SDKs.
- Web plays through Brightcove's web player and covers basic playback; some
  controls differ from native.

## Known limitations

- iOS DRM playback is device-only: FairPlay cannot decrypt in the Simulator.
- The bundled account is a demonstration account. Replace it before shipping.

## Further reading

- [Audio-tracks feature contract](../../../docs/audio-tracks.md)
