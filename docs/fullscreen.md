# Fullscreen State

## Scope

The fullscreen feature reports the Brightcove player's native screen-mode state
to React Native and exposes imperative enter/exit commands:

```ts
onFullscreenChanged?: DirectEventHandler<{
  active: boolean;
}>;

PlayerCommands.enterFullscreen(viewRef);
PlayerCommands.exitFullscreen(viewRef);
```

`active: true` means the native player reported fullscreen screen mode.
`active: false` means it reported normal screen mode. The callback is the
player's state signal; it is not a guarantee about the outer React Native
layout or host orientation.

This is player screen mode, not device orientation, host navigation chrome,
status-bar state, or an Activity-wide fullscreen state. The bridge does not
change orientation; host orientation and navigation policy remain the host
app's responsibility.

On Android and iOS the fullscreen feature is installed by every sample (the
supported set requires it so both native platforms behave the same). On Web,
fullscreen is the browser Fullscreen API on the player element.

## Command contract

Both commands are imperative one-shots. Commands are available on all three
platforms; the outcomes differ slightly by platform because the underlying
APIs do.

- **Android / iOS:** the command is rejected with `onPlayerCommandError`
  (`code: "invalid_state"`) using a typed `nativeCode` when it cannot run:
  `already_fullscreen` (enter while fullscreen), `not_fullscreen` (exit while
  windowed), or `transition_in_flight` (a transition is already pending). A
  command issued before the native view is ready reports `not_ready` /
  `player_view_not_available`. Native rejections never emit a fabricated
  `onFullscreenChanged`.
- **Web:** `enterFullscreen`/`exitFullscreen` call the browser Fullscreen API on
  the player element. There is no typed three-state rejection table on Web
  (the browser exposes no equivalent); an unsupported environment reports
  `unavailable` / `fullscreen_unsupported`, and a rejected request reports
  `failed`.

The completed transition is reported only through `onFullscreenChanged` after
the platform confirms it — the command itself reports no success event.

## Web implementation

`BrightcovePlayerView.web.tsx` requests fullscreen on the player's own element
(the `.video-js` root), not the wrapper container. The in-player
`FullscreenToggle` fullscreens that same element, so the two stay in sync: the
toggle's label reflects the real state and can both enter and exit. The bridge
listens for both the standard `fullscreenchange` and Safari's prefixed
`webkitfullscreenchange`, and treats the video.js child element as a contained
fullscreen target while ignoring unrelated document-level fullscreen elements.
Fullscreen-change events are deduplicated so a browser delivering both the
standard and prefixed event reports one change.

## Android implementation

`FullscreenFeature` registers persistent, view-scoped listeners for Brightcove's
public `DID_ENTER_FULL_SCREEN` and `DID_EXIT_FULL_SCREEN` events. Those events
are emitted after the native `FullScreenController` has processed a request from
the Brightcove media-controller fullscreen button or from the bridge. The feature
emits `active` only from those SDK state events; it does not treat
`ENTER_FULL_SCREEN` or `EXIT_FULL_SCREEN` request events as completed state.

The Android SDK does not expose an imperative `enterFullScreen` method. The
bridge forwards `enterFullscreen` and `exitFullscreen` by emitting the SDK's
public request events, which the native `FullScreenController` consumes. The
three-state transition state machine (`none` / enter pending / exit pending) is
extracted and unit-tested so the pending flag cannot outlive the transition it
named.

On `DID_ENTER_FULL_SCREEN` the feature reparents the player view into an
Activity-root fullscreen overlay. If that overlay cannot be created, it restores
the SDK state, requests the exit, and reports `not_ready` /
`fullscreen_layout_unavailable` rather than telling JavaScript that visual
fullscreen is active.

Fullscreen is view/Activity-local. The SDK's normal fullscreen controller does
not force landscape orientation. Host Activities that want orientation changes
must own and explicitly configure that policy themselves.

The feature cooperates with Picture-in-Picture: while PiP owns the window it
does not tear down the fullscreen overlay, and it releases the overlay after PiP
exits.

Source reset and view disposal send the SDK's real Android exit request
synchronously (`emitNow`, not the asynchronous `emit`) before listeners/render
teardown, so the Activity's fullscreen window flags are restored while the exit
listener is still attached. The bridge does not synthesize an event if the SDK
refuses or cannot complete that request. On iOS, the core detaches the
player-view delegate before teardown so an interrupted transition cannot notify
React Native after the player is replaced.

## iOS implementation

`BrightcoveFullscreenFeature` receives `BCOVPUIPlayerViewDelegate`'s completed
`playerView:didTransitionToScreenMode:` callback from the core. It maps
`BCOVPUIScreenModeFull` to `active: true` and `BCOVPUIScreenModeNormal` to
`active: false`.

The iOS callback is emitted from the SDK's `didTransitionToScreenMode:` path,
including native fullscreen-button and externally dismissed transitions. The
bridge does not use the `willTransitionToScreenMode:` callback because that is
transition intent. An interrupted native animation may still produce the SDK's
did callback, so the bridge describes this as SDK-reported state rather than a
guarantee that every visual transition completed.

The public iOS SDK has no generic fullscreen-orientation callback. Its screen
mode enum is intentionally kept separate from `UIInterfaceOrientation`; host
orientation and navigation policy remain the host app's responsibility.

Tear-down waits for the SDK's normal-mode callback so the core can finish
cleanly. If that callback does not arrive within a one-second guard window, the
bridge logs the condition, reports `active: false`, and completes native
teardown rather than hanging. Source reset and invalidation do not otherwise
fabricate an `active: false` event; the host app should treat the state as
belonging to the mounted player instance.

## Sample

`samples/player/fullscreen` displays:

- the native Brightcove player controls, including fullscreen;
- a `Windowed`/`Fullscreen` layout driven only by native completion events;
- an `Enter fullscreen` / `Exit fullscreen` control that dispatches the
  imperative commands;
- an explicit note that the bridge does not change orientation.

The sample applies the host-layout coordination described above: it removes the
surrounding UI and changes the React Native player host to a full-viewport layer
when the native event reports `active: true`. Consumers embedded in their own
navigation, scrolling, or card layouts must apply an equivalent host-level
layout strategy if they want a visual fullscreen presentation.

## Verification

- Fullscreen sample typecheck, ESLint, and Jest: 5 passed (Android
  `FullscreenFeatureTest` additionally covers the transition state machine,
  command ownership, and rejection codes).
- Basic-playback typecheck, ESLint, and Jest: 77 passed, including web coverage
  for the video.js fullscreen target, the prefixed/standard change listeners,
  contained fullscreen elements, and the prefixed request fallback.
- `scripts/check-bridge-copies.sh`.
- Android debug/release build for fullscreen.
- iOS simulator debug build for fullscreen.
- Android runtime: the native fullscreen control produced `Windowed ->
  Fullscreen -> Windowed` state updates with no orientation change and no crash.
- Web runtime: verified in a browser that the player enters fullscreen and
  exits via both the sample's control and the in-player toggle, with the toggle
  label staying in sync.
- iOS simulator build and launch verify the online-player regression and the
  fullscreen wiring. The interactive iOS screen-mode transition has not been
  exercised on a physical device; treat that as the remaining manual
  follow-up.
