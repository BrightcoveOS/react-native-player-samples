# Native Controls

## Scope

The controls feature toggles the Brightcove player's built-in control bar so an
app can hide it and drive transport from React Native.

```ts
controlsEnabled?: boolean; // default true
```

When `false`, the native controls are hidden and the bridge performs a host
layout pass so the change is painted. `controlsEnabled` is a **live** prop: it
applies to the current player immediately and reapplies when a source is
prepared.

There is no controls command and no controls event. Playback transport for a
hidden control bar is driven through the existing commands (`play`, `pause`,
`seekTo`, `reload`) and presentation commands (fullscreen/PiP).

Related but distinct: `custom-controls` (this sample) hides the native bar;
`captionrendering` controls whether the player draws captions itself. They are
separate features.

## Android

`ControlsFeature` owns `controlsEnabled`. It creates the SDK's
`BrightcoveMediaController` when needed, applies
`setShowControllerEnable(controlsEnabled)`, calls `show()`/`hide()`, and requests
a host layout pass so Fabric repaints the change. It applies on prop commit (and
reapplies on playback-listener registration for the new source).

## iOS

`BrightcoveControlsFeature` owns `controlsEnabled` (default `true`). It applies
the value to the player view's `controlsContainerView` — `alpha`,
`userInteractionEnabled`, and `hidden` — on prop commit and on session ready.

## Web

The Web bridge's `controlsEnabled` shows or hides the query/menu `ControlBar`
through the Web SDK UI manager (`controlBar.show()` / `.hide()`). The control-bar
components themselves are chosen at player creation from the installed feature
set: `scripts/assemble-bridge.sh` generates a `WEB_CONTROL_BAR_COMPONENTS` list
(baseline buttons plus each selected feature's contribution, e.g.
`PictureInPictureToggle`, `AudioTrackButton`, `SubsCapsButton`) and injects it as
the web-only `webControlBarComponents` prop, so a copy never shows a button for a
feature it did not install. `controls` contributes no control-bar component; the
feature catalog marks controls Web support as supported.

## Sample

`samples/player/custom-controls` demonstrates hiding the native controls and
driving volume/mute and transport from React Native, with a React Native
fullscreen control. Because hiding the bar also removes the built-in fullscreen
exit affordance, the sample temporarily re-enables controls when entering
fullscreen and restores the hidden preference on exit — a pattern integrators
hiding the bar should follow. Its RN exit button exists because the iOS
fullscreen presentation (a modal view) and the Android Activity-root fullscreen
overlay both cover the app's normal controls.

## Verification

- Custom-controls sample typecheck, ESLint, and Jest: initial `controlsEnabled:
  false`, volume/mute updates, the controls toggle, and fullscreen enabling
  controls before entry and restoring the hidden preference on exit.
- Web bridge coverage: `controlsEnabled` drives the UI manager's control-bar
  show/hide.
- `scripts/check-bridge-copies.sh` (the generated control-bar list stays in step
  with installed features).
- Android release build and iOS Release simulator build.

There is no dedicated Android/iOS unit test for the controls feature; the
show/hide behavior is exercised by the sample.
