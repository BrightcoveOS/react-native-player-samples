# Playlists and Queues

## Scope

The playlists feature plays an ordered queue of Video Cloud videos. The native
SDK owns the queue and end-of-item advancement; the bridge adds React Native
control and observability on top.

```ts
videoIds?: string[];            // the queue; mutually exclusive with videoId

repeatMode?: 'off' | 'one' | 'all'; // default 'off'
shuffle?: boolean;                  // default false

onQueueItemChanged?: DirectEventHandler<{ videoId: string; index: number }>;
onQueueItemFailed?: DirectEventHandler<{
  videoId: string; index: number; code: string; message: string; nativeCode: string;
}>;
onQueueCompleted?: DirectEventHandler<null>;

PlayerCommands.next(viewRef);
PlayerCommands.previous(viewRef);
```

`videoIds` is a feature-owned source: it is mutually exclusive with `videoId` and
`offlineSourceId`. Setting it claims source loading and the queue is resolved in
order through the Playback API.

## Events

- `onQueueItemChanged` fires when the active item changes (initial load and each
  advance), with the item's `videoId` and queue `index`.
- `onQueueItemFailed` fires for an item that fails to resolve; the bridge skips
  it and continues to the next id. If every item fails, the source fails with
  `playlist_empty_after_resolution`.
- `onQueueCompleted` fires **only on natural completion** of the last item:
  once per queue, and never when a repeat mode wraps or a preload handoff takes
  over. A manual `next` at the last item is a typed rejection, not a completion.

## Command contract

`next` and `previous` are imperative one-shots; the native SDK's queue remains
the single source of truth for whether advancing is possible.

- `next` at the last item with repeat off → `onPlayerCommandError`
  (`invalid_state`, `nativeCode: queue_at_end`).
- `next`/`previous` with no loaded queue → `invalid_state`,
  `nativeCode: queue_not_loaded`.
- `previous` at the first item is a valid position: it restarts the current item
  rather than failing.
- With `repeatMode: 'all'`, `next` at the last item wraps to the first; with
  `repeatMode: 'one'`, the current item loops (the element's `loop` is set) and
  the queue never completes.

The rejection messages are shared verbatim across platforms via the native
`QueueCommandOutcome` tables, so a caller sees the same contract on Android, iOS,
and Web.

## Android

`PlaylistsFeature` owns `videoIds`, `repeatMode`, and `shuffle` and supports
`next`/`previous`. Source loading resolves each id via `Catalog.findVideoByID`,
in order, and adds the resolved queue to the view. Repeat/shuffle map to the
ExoPlayer repeat mode (`off`/`one`/`all`) and `shuffleModeEnabled`. Every callback is
guarded by the request generation, so a late resolution from an outgoing source
cannot affect the current one. The next/previous decision tables
(`QueueCommandOutcome`) and the completion latch (`QueueCompletionState`) are
extracted and unit-tested.

## iOS

`BrightcovePlaylistsFeature` uses the SDK's native queue (`setVideos:`) for
auto-advance and layers repeat/shuffle on top. It resolves ids through the
Playback API, builds a randomized playback order for shuffle (keeping the
current item first), and manages completion and repeat-one ahead of the SDK's own
auto-advance. The iOS `BCOVQueueCommandOutcome` mirrors Android's decision
tables and messages.

## Web

The Web bridge resolves `videoIds` one item at a time (each item is its own
Playback API fetch), tracks item changes, and reports item failures per item,
advancing to the next. `next`/`previous` implement the same advance/wrap/restart
and the same `queue_at_end`/`queue_not_loaded` rejections. `repeatMode: 'one'`
loops the element; the once-per-queue completion latch is reset on a source
change or preload handoff. The feature catalog marks playlists Web support as
**partial**.

## Sample

`samples/player/playlists` plays a three-item demo queue and exposes
`Next`/`Previous`, shuffle, and repeat controls. It shows `onQueueItemChanged`,
`onQueueItemFailed`, and `onQueueCompleted`, and displays the `queue_at_end`
rejection only while the player is genuinely at the last item with repeat off,
clearing it on queue movement, repeat/shuffle change, and completion.

## Verification

- Android `PlaylistsFeatureTest` (props/events/validation, identity-not-id
  matching), `QueueCommandOutcomeTest` (the full next/previous decision table),
  and `QueueCompletionStateTest` (wait/advance/no-double-advance/once, repeat
  modes, reset).
- iOS `BCOVQueueCommandOutcomeTests` (decision table incl. the verbatim
  messages).
- Web bridge queue coverage (e.g. not re-initializing on a same-content
  `videoIds` array).
- Playlists sample typecheck, ESLint, and Jest (queue hand-off, item
  changed/failed/completed, the truthful `queue_at_end` handling, repeat cycle,
  shuffle, next/previous dispatch).
- `scripts/check-bridge-copies.sh`.
- Android release build and iOS Release simulator build.
