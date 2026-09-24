# Playlists

A standalone bare React Native app that plays a Brightcove queue (playlist). It
embeds its own copy of the bridge under `modules/brightcove-player` and consumes
it through React Native autolinking as `@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

## What it demonstrates

- Loading a queue with `videoIds` instead of a single `videoId`. Each id is
  resolved from the catalog in order and handed to the native SDK's own queue,
  which owns normal end-of-item advancement.
- `repeatMode` (`off` / `one` / `all`) and `shuffle` transport behavior.
- Manual `next` / `previous` skips dispatched imperatively through a ref.
- Per-item resolution failures: a failed item is skipped, not fatal, and is
  marked in the list.
- `onQueueItemChanged`, `onQueueItemFailed`, and `onQueueCompleted`.
- The command-error contract: advancing past the last item with repeat off
  reports a typed `queue_at_end` rejection, shown only while it is true and
  cleared as soon as the queue state changes.
- Fullscreen entry and exit alongside the queue controls.

## The video it ships

Configuration lives in `src/playerConfig.ts` and uses its own queue of demo
assets. Replace the account, policy key, and the `queue` entries with your own
playable videos.

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

- The native SDKs own queue advancement, so queue behavior is the SDK's, not
  the React Native layer's.
- There is no web build for this sample.

## Known limitations

- `next` at the end of the queue with repeat off is a valid, typed rejection
  (`queue_at_end`), not a failure.
- A single-item `videoIds` list behaves like a normal single-video source.

## Further reading

- [Playlists and queue contract](../../../docs/playlists.md)
