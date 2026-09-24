# Offline Playback

A standalone bare React Native application for Brightcove native offline
downloads and local playback. It embeds its own copy of the bridge under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

## What it demonstrates

- Requesting one offline download, or a two-item selection, while connected.
- Restoring persisted native download state after the app relaunches.
- Displaying per-item progress and completion.
- Playing a completed item through `offlineSourceId` without the catalog or
  network.
- Removing a download once it is no longer the active player source.

## The video it ships

Configuration is defined in `App.tsx`. The sample uses two offline-enabled
Brightcove Native SDK test assets from a demo account. Replace the account,
policy key, and video ids with your own offline-enabled content.

Downloads are durable native SDK records, so they survive view unmounts and app
process recreation. The native SDK remains the source of truth; JavaScript
restores state with `listDownloads()` and receives updates from one event
stream.

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

- **Android:** supports offline-enabled DASH/Widevine content. Downloads and
  local playback run on an emulator.
- **iOS:** supports HTTPS HLS and FairPlay. Apple does not support offline HLS
  downloads or FairPlay local playback on the Simulator, so the download and
  local-playback paths compile and launch there but must be exercised on a
  physical device.
- There is no web build for this sample.

## Known limitations

- One download per `videoId`, bound to the account/policy that requested it.
  Requesting the same `videoId` under different credentials is rejected instead
  of silently reusing the wrong catalog; remove the download first.
- iOS reports `bytesDownloaded` as 0 (no byte counter in AVFoundation); use
  `progress` (a 0-100 percentage on both platforms) for a progress bar.
- A download that is the player's active `offlineSourceId` cannot be removed;
  switch the player source first.
- Offline DRM (Widevine on Android, FairPlay on iOS) only proves out on a
  physical device, not a simulator/emulator.
- `requestDownloads` asks native code to accept each item serially; it does not
  promise transfer order, atomicity, or force-quit continuation.

## Further reading

- [Offline playback and download contract](../../../docs/offline-playback.md)
