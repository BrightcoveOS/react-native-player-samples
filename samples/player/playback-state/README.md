# Playback State

Standalone bare React Native application demonstrating the playback lifecycle,
progress, and live/DVR state surface. It embeds its own copy of the bridge under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

It shows how to observe and drive playback state from React Native, with an
on-screen switch between two sources:

- Playback lifecycle: `onPlay`, `onPause`, `onEnded`.
- Progress: `onProgress` (`currentTime` / `duration`), formatted on screen.
- Live/DVR classification: `onLiveStatus` (`isLive`, `hasDvr`) and the moving
  seekable window from `onSeekableRangesChanged` (`ranges`, `liveEdge`).
- The `seekToLiveEdge` command, exposed as a **Go live** control that is enabled
  only when the stream is live with a valid, non-empty DVR window.

## The videos it ships

Configuration lives in `src/playerConfig.ts` and defines two selectable sources
with an on-screen switch:

- **On-demand** — a public VOD asset, which exercises the lifecycle, progress,
  and on-demand paths and intentionally shows `Seekable window unavailable`.
- **Live / DVR** — a placeholder slot. Live-DVR content is account-specific and
  cannot be shipped as a permanent public fixture, so it ships as
  `YOUR_LIVE_DVR_VIDEO_ID`. Until you replace it, selecting this source shows a
  configuration note instead of loading. Point it at a live-DVR asset id from an
  account that owns one to exercise `onSeekableRangesChanged` and the Go live
  command.

Both sources share the same demo account and policy key; replace them with your
own before shipping.

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

- Android and iOS report playback, progress, and live events through the
  Brightcove native player SDKs.
- The web build uses Brightcove's web player; live event coverage and the
  seekable-window values can differ from native.
- A live-DVR window is only available while the source is actually live with
  DVR; a VOD or plain-live source reports `On-demand`/`Live` and no Go live
  control.

## Known limitations

- The Live / DVR source ships as a placeholder; verifying the live window and
  Go live command requires filling in a real live-DVR asset id.
- `liveEdge` is the greatest usable seek position the platform reports; it can
  briefly lead the seekable-window end due to clock drift, and the bridge clamps
  it to the window end.

## Further reading

- [Live and DVR playback contract](../../../docs/live-dvr.md)
