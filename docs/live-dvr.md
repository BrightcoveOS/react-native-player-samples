# Live and DVR playback

## Scope

The live feature exposes stream classification, moving seekable-window updates,
and a command that seeks to the current live edge.

The public JavaScript surface is:

```ts
onLiveStatus?: DirectEventHandler<{
  isLive: boolean;
  hasDvr: boolean;
}>;

onSeekableRangesChanged?: DirectEventHandler<{
  ranges: {
    startTime: number;
    endTime: number;
  }[];
  liveEdge: number;
}>;

PlayerCommands.seekToLiveEdge(viewRef);
```

All range values are seconds on the player timeline. `ranges` is an array
because AVPlayer can expose more than one seekable range. Android currently
emits the SDK's single live window as one range. `liveEdge` is the greatest
usable seek position reported by the platform.

`onLiveStatus` classification is emitted once per source, on the prepared source
(`BUFFERING_COMPLETED` on Android; after session/video-type determination on
iOS), so it never precedes the core's `onReady`. On native, a source reset emits
only an empty `onSeekableRangesChanged` (so a controlled JavaScript UI cannot
retain the previous video's live or DVR state); the `onLiveStatus` reset
(`{isLive: false, hasDvr: false}`) is emitted on Web only. On native the previous
classification therefore remains until the new source classifies — key the UI on
the reset range update, not on a status reset.

`seekToLiveEdge` is a one-shot command. The caller should enable it after
receiving `onLiveStatus` with `hasDvr: true` and a valid non-empty range update
(`endTime > startTime >= 0`, `liveEdge > 0`). Every classified rejection is
reported through `onPlayerCommandError` with `invalid_state` and a typed
`nativeCode` distinguishing the failure classes: `not_live_dvr` for a source
that is not live-with-DVR (VOD or plain live), `no_dvr_range_yet` for a live-DVR
source whose seekable window has not been populated yet, and `not_ready` (iOS
and Web) for an unprepared/unclassified source. A caller can therefore tell
"wait for ranges" from "this source can never seek to the edge". A torn-down
or invalidated view swallows the command without an error event.

## Android implementation

`LiveFeature` listens to Brightcove's `BUFFERING_COMPLETED`,
`VIDEO_DURATION_CHANGED`, and `PROGRESS` events:

- Stream classification (`onLiveStatus`) is emitted once the media item is
  prepared (`BUFFERING_COMPLETED`), ensuring `onReady` arrives before
  `onLiveStatus` across platforms.
- Seekable range updates are extracted from `VIDEO_DURATION_CHANGED` and
  `PROGRESS` using:

  - `MIN_POSITION_LONG` for the beginning of the seekable window;
  - `MAX_POSITION_LONG` for the end of the seekable window;
  - `videoDisplay.getLiveEdgeLong()` for the current usable live edge.

The feature converts milliseconds to JavaScript seconds, validates range bounds
(`end > start >= 0` and `liveEdge >= start` with `liveEdge > 0`), clamps a
live-edge value slightly exceeding the window end to the window end, and
deduplicates identical window updates. Both `PROGRESS` (active playback) and
`VIDEO_DURATION_CHANGED` (prepared timeline while paused or when `autoPlay` is
false) are consumed without artificial polling timers. A `PROGRESS` event
without both range bounds leaves the last valid range unchanged;
`VIDEO_DURATION_CHANGED` is the event that invalidates a missing or invalid
range.

Playback listeners registered through `host.registerListener` are scoped to the
current source generation, so late callbacks from the outgoing source are
ignored; the core ready path additionally validates event video identity. The
source reset clears classification/deduplication state and emits an empty range
before the next ready-time classification. The command re-reads the native live
edge, applies the same range predicate to the stored window and fresh edge, and
seeks the validated edge directly (`minOf(liveEdge, end)`); an out-of-window
fresh edge is a no-op.

The command is routed through the Codegen-generated view-manager interface to
`BrightcovePlayerView.seekToLiveEdge()`. A copy without `LiveFeature` emits
`onPlayerCommandError` with `feature_not_installed`; it does not throw. A copy
with `LiveFeature` delegates readiness and live/DVR classification to the
feature. `LiveFeature` reports VOD/plain-live as `not_live_dvr` and a
not-yet-populated or invalid window as `no_dvr_range_yet`, seeking only a
validated edge through `BrightcoveExoPlayerVideoView.seekTo(targetPosition)`.

## iOS implementation

The core forwards
`playbackController:playbackSession:didChangeSeekableRanges:` to registered
features after validating the request-generation tag on the playback session.
Generation — not video ID — is the source identity, so two requests for the same
video cannot let an outgoing session update the current JavaScript view.

`BrightcoveLiveFeature` consumes `CMTimeRange` values from the current
`BCOVPlaybackSession`, validates range numeric bounds (`end > start >= 0`,
`liveEdge > 0`), and emits their start/end values plus the greatest range end as
`liveEdge`.

Seekable-range callbacks can arrive before video-type determination or while the
Fabric event emitter is unavailable. The feature retains the current-session
ranges and flushes them after session readiness (`onSessionReady:`), video type
determination (`onDeterminedVideoType:`), or emitter readiness
(`onEventEmitterReady:`). `onLiveStatus` emission is gated on `_sessionReady` so
it is never emitted before the core's `onReady` event. Source reset clears the
classification and range state before the next source. The live-edge command
requires `_sessionReady`, `_videoTypeDetermined`, a current session, `_hasDvr`,
and a valid non-zero seekable range end. Core ready/error events and live-feature
events retain undelivered payloads until the native view has an event dispatcher.

Deterministic teardown is implemented via `onPlayerTearDown` and `onInvalidate`,
which clear session references, readiness state, classification state, and
pending ranges to prevent stale state across remounts or source transitions.

The command is an optional feature hook. A copy without the feature emits the
same `feature_not_installed` command error as Android. A copy with the feature
delegates all live-specific readiness and classification to
`BrightcoveLiveFeature`; the feature keeps the current session weakly, validates
the seekable range predicate, and calls the public
`BCOVPlaybackController seekToTime:completionHandler:` method.

## Web implementation

The Web bridge classifies a stream as live when the HTML video element reports
an infinite duration. It serializes every browser `TimeRanges` entry from
`video.seekable`, uses the final range end as `liveEdge`, and reports DVR only
when the live window has positive width. Range and status updates are deduplicated
and refreshed from native video-element events. Unlike Android/iOS, a Web source
reset explicitly emits an empty live status (`isLive: false`, `hasDvr: false`);
seekable ranges are recomputed from the new video element on its next media
event.

Web `seekToLiveEdge` seeks to the final browser seekable-range end. Its error
codes follow the browser state rather than the native two-class table:
`source_not_ready`, `video_element_unavailable`, `not_live`, and
`seek_to_live_edge_failed`. The feature catalog marks live Web support as
**partial**, and `samples/player/playback-state` carries the Web build.

## Platform seek-edge semantics

- **Android**: `videoDisplay.getLiveEdgeLong()` reports the SDK's calculated
  target live edge (which may slightly lead the timeline max position due to
  clock drift; clamped to `MAX_POSITION_LONG`). Seeking targets
  `minOf(liveEdge, end)`.
- **iOS**: `AVPlayerItem.seekableTimeRanges` upper bound
  (`CMTimeRangeGetEnd`) is the seekable end. Seeking targets the seekable end
  via `seekToTime:`.
- **Web**: the final `HTMLMediaElement.seekable` range end is the live edge.
  Seeking targets that value through the Web SDK player.

## Bridge composition

The feature catalog includes the new event type. The bridge assembler generates:

- the live event handler in the selected sample's TypeScript surface;
- the `seekToLiveEdge` member of `PlayerCommands` only in bridge copies that
  install `live`;
- the matching Android and iOS feature registries through the existing copy
  model.

The reference bridge remains the canonical superset. Sample bridge copies are
generated with `scripts/assemble-bridge.sh` and checked with
`scripts/check-bridge-copies.sh`.

## Sample

`samples/player/playback-state` displays:

- playback lifecycle and progress;
- on-demand/live/live-DVR classification;
- the current seekable range and live edge;
- a `Go live` control when DVR is available.

The public demo asset in the sample is VOD. It validates the on-demand path and
intentionally displays `Seekable window unavailable`. A real moving live-DVR
stream is account-specific and cannot be shipped as a permanent public fixture;
live-specific runtime verification requires a Video Cloud account with a
currently active live-DVR asset.

## Verification

The following checks pass:

- TypeScript typecheck and ESLint across samples.
- Playback-state Jest tests covering seekable-range rendering,
  reset/classification ordering, invalid-range gating, Go live command dispatch,
  and VOD/plain-live gating.
- Android `LiveFeatureTest` unit tests covering timeline window extraction,
  liveEdge clamping past the window end, invalid-window rejection, the fresh-edge
  predicate, progress events without bounds, command ownership, and typed
  command outcomes.
- Web Jest coverage for live status/ranges and live-edge command dispatch, plus
  the production Webpack build for `playback-state`.
- `scripts/check-bridge-copies.sh` verifying all embedded bridge copies match
  reference.
- Android release builds and iOS Release simulator builds.
