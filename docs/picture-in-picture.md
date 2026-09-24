# Picture-in-Picture

## Scope

Picture-in-Picture (PiP) lets the player continue in a small floating window when
the app is backgrounded or the user requests it. The feature exposes one prop,
one event, and one command:

```ts
pictureInPictureEnabled?: boolean; // default false

onPictureInPictureModeChanged?: DirectEventHandler<{
  active: boolean;
}>;

PlayerCommands.enterPictureInPicture(viewRef);
```

`pictureInPictureEnabled` enables PiP readiness for a player that is genuinely
playing; it is not a play/pause control. `onPictureInPictureModeChanged` reports
the platform-confirmed state. `enterPictureInPicture` is an imperative one-shot.

## Command contract

`enterPictureInPicture` runs in one:

- Success is reported only through `onPictureInPictureModeChanged`; the command
  emits no success event.
- Rejections are reported through `onPlayerCommandError` with a typed
  `nativeCode`:

  | `nativeCode` | Meaning |
  | --- | --- |
  | `pip_disabled` | `pictureInPictureEnabled` is false. |
  | `unsupported_api_level` / `pip_not_supported` | PiP unavailable on this platform/device. |
  | `no_activity` / `controller_unavailable` / `pip_controller_nil` | No bound Activity or playback controller yet. |
  | `manifest_missing_pip` / `pip_not_registered` | Android Activity missing `supportsPictureInPicture`. |
  | `source_not_ready` | No playable source yet. |
  | `already_in_pip` / `pip_not_possible` | Already in PiP, or the platform refused entry. |
  | `pip_failed` / platform error | Entry failed. |

## Android

`PictureInPictureFeature` owns `pictureInPictureEnabled`, exports
`onPictureInPictureModeChanged`, and supports `enterPictureInPicture`.

- **Initialization-only semantics.** `setProp` records the value; it only
  configures entry before the first source loads. Disabling later disarms
  background entry but does not tear down registration.
- **Host requirements.** The Activity must declare
  `android:supportsPictureInPicture="true"` and forward `onUserLeaveHint` and
  `onPictureInPictureModeChanged` to the SDK. The bridge reads the manifest flag
  and reports `manifest_missing_pip` when it is absent, rather than failing
  silently.
- **Background entry.** Auto-enter is tied to real playback state
  (`DID_PLAY` vs pause/stop/completed/error): on API 31+ via
  `setAutoEnterEnabled`, on older versions via `setOnUserLeaveEnabled`.
- **Singleton ownership.** PiP is process/Activity-scoped. A process-wide
  ownership coordinator lets the first enabled, playing view acquire it; a second
  player is queued and handed ownership when the first releases.
- **Layout.** The player is reparented into the PiP window; PiP params carry an
  aspect-ratio hint clamped to roughly 1:2.39–2.39:1, and immediate sibling
  chrome is hidden while PiP is active and restored on exit.
- **Teardown.** While the system PiP window is open, core disposal is deferred
  (`DeferredDisposeCoordinator`) so the SDK surface is not torn down underneath
  the floating window; finalization runs after the system PiP exit.
- **Fullscreen/PiP interaction.** The fullscreen feature cooperates: it does not
  tear down the fullscreen overlay while PiP owns the window.

## iOS

`BrightcovePictureInPictureFeature` owns the same prop and command, using the
host playback controller's `AVPictureInPictureController`.

- **Initialization-only semantics.** `setProp` records only; the PiP button is
  baked into the control layout at controller creation, and rebuilding the
  controller would restart playback.
- **Host requirements.** The app needs the `audio` background mode and a playback
  audio session (`AVAudioSession` category `.playback`, mode `.moviePlayback`)
  for the PiP window to keep playing when backgrounded.
- **Automatic entry.** `canStartPictureInPictureAutomaticallyFromInline` follows
  real play state (iOS 14.2+).
- **Teardown.** `onPlayerTearDown`/`onInvalidate` force the PiP controller to
  inactive. There is no cross-player ownership coordination on iOS (PiP is
  per-controller); the singleton ownership rule is Android-only.

**Verification ceiling:** PiP does not activate on the Simulator. Verify on a
physical device.

## Web

Web PiP uses the browser API: `video.requestPictureInPicture()`, or Safari's
prefixed `webkitSetPresentationMode('picture-in-picture')`. The bridge reports
`disabled` (`pip_disabled`), `not_ready` (`video_element_unavailable`),
`unavailable` (`pip_unsupported`), or `failed` (`pip_failed`), and tracks entry
and exit from both the standard and prefixed events. The feature catalog marks
PiP Web support as **partial** and contributes the browser `PictureInPictureToggle`
control-bar button.

## Sample

`samples/player/picture-in-picture` demonstrates enabling PiP, entering from the
control or by backgrounding, tracking `onPictureInPictureModeChanged`, and
fullscreen alongside PiP. It deliberately fills the screen with the player: a
full-bleed surface is what lets the PiP window show the video and nothing else.
Its Android manifest declares `supportsPictureInPicture` and forwards the
lifecycle callbacks; its iOS `Info.plist` sets the audio background mode and its
`AppDelegate` configures the playback audio session.

## Verification

- Android `DeferredDisposeCoordinatorTest`: disposal is deferred until after the
  posted SDK finalizer, and finalizes at most once.
- PiP sample typecheck, ESLint, and Jest (prop pass-through, enter/exit state,
  fullscreen alongside PiP).
- `scripts/check-bridge-copies.sh`.
- Android release build and iOS Release simulator build.
- Android manifest and iOS `Info.plist`/audio-session host wiring present in the
  sample.

The interactive PiP lifecycle is a physical-device path on iOS (and the strongest
evidence on Android). This sample is in the supported set but has not completed
that device pass in CI.
