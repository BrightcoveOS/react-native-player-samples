# Ads (CSAI / Google IMA)

## Scope

Client-side ad insertion (CSAI) plays ads requested and rendered by the client
alongside the content, driven by an ad tag. This feature uses Google IMA.

```ts
adTagUrl?: string; // VMAP or VAST ad tag URL; mutually exclusive with adConfigId

onAdStarted?: DirectEventHandler<{ adTitle: string; duration: number }>;
onAdCompleted?: DirectEventHandler<{ adTitle: string; duration: number }>;
onAdBreakStarted?: DirectEventHandler<{ index: number }>;
onAdBreakEnded?: DirectEventHandler<{ index: number }>;
onAllAdsCompleted?: DirectEventHandler<{ completed: boolean }>;
onAdError?: DirectEventHandler<{ code: string; message: string; nativeCode: string }>;
onAdPaused?: DirectEventHandler<{ adId: string }>;
onAdResumed?: DirectEventHandler<{ adId: string }>;
onAdProgress?: DirectEventHandler<{ adId: string; positionSeconds: number; durationSeconds: number }>;
onAdQuartile?: DirectEventHandler<{ adId: string; quartile: number }>;
onAdSkipped?: DirectEventHandler<{ adId: string }>;
onAdInteraction?: DirectEventHandler<{ adId: string; interaction: string }>;
onAdMetadata?: DirectEventHandler<{ adId: string; adTitle: string }>;
onAdOverlayStateChanged?: DirectEventHandler<{ adId: string; visible: boolean }>;
```

CSAI (`adTagUrl`) and server-side ad insertion (`adConfigId`) are **mutually
exclusive** and have separate samples. The ad tag decides the whole schedule: a
VMAP response carries the pre/mid/post positions, so the app never places ad cue
points itself. A VAST tag, which requires the app to define positions, is out of
scope for the sample.

## Ad events

- `onAdStarted` / `onAdCompleted` fire per individual ad.
- `onAdBreakStarted` / `onAdBreakEnded` bracket each pod. The `index` is always
  `-1`: neither platform's ad SDK surfaces a stable ad-break index, so the
  contract keeps the field but does not report a meaningful value today.
- `onAllAdsCompleted` fires once when the whole schedule finishes.
- `onAdError` reports an **ad** failure with
  `code: one of 'load' | 'playback' | 'unknown'`. An ad failing does **not** fail
  content playback.
- `onAdPaused` / `onAdResumed` / `onAdProgress` / `onAdQuartile` / `onAdSkipped`
  / `onAdInteraction` / `onAdMetadata` / `onAdOverlayStateChanged` report the
  finer-grained ad lifecycle. `onAdQuartile` uses `quartile` in `{25, 50, 75}`.
  Non-linear ads report overlay visibility through `onAdOverlayStateChanged`.

## Failure routing

- An **ad** failure surfaces as `onAdError` and leaves the content playing.
- A **content** failure (including a failure to load the media itself) surfaces as
  the content `onError`, unchanged.

## Ad scheduling

Ad-break placement is Google IMA's, driven by the VMAP response. Mid-rolls are
tied to content positions, so seeking past an un-played mid-roll (for example,
straight to the end) can skip it while the post-roll still plays. The bridge does
not intercept seeks or ad scheduling; a caller that needs different behavior
configures IMA, not the bridge.

## Android

`AdsFeature` owns `adTagUrl`. It builds the Google IMA `GoogleIMAComponent`
against the player view, registers IMA ad listeners, and maps IMA ad events to
the contract above. Per-event generation guards reject ad events from an outgoing
source, and the SDK's shared `ERROR` event is claimed (suppressed) when it is
actually an ad failure, so an ad error is not double-reported as a content error.
It requires the `android-ima-plugin` dependency, which the assembled bridge copy
adds automatically when the `ads` feature is installed.

## iOS

`BrightcoveAdsFeature` owns `adTagUrl`, builds `BCOVIMAComponent` around the
playback controller, and sets `requiresControllerManagedPlayback` while an ad tag
is set so the IMA component owns the ad-to-content transition (the core does not
race it by calling `-play` on ready). IMA ad callbacks map to the contract above;
an in-ad failure maps to `onAdError`. It requires the `BrightcoveIMA` Swift
package and Google IMA, added automatically by the assembled bridge copy.

## Web

The Web bridge enables CSAI through the Web SDK's `imaClientSide` integration
factory when `adTagUrl` is set, and reads the SDK's ad events to emit the same
contract. `adTagUrl` is initialization-only on Web: it selects the ad integration
at player creation, so changing it after mount reports
`invalid_configuration` / `ad_config_init_only` rather than silently doing
nothing. The feature catalog marks ads Web support as **partial**.

## Sample

`samples/player/ads` plays a pre/mid/post schedule from Google's public VMAP
sample tag around Brightcove demo content, wiring `onAdStarted` /
`onAdCompleted` / `onAdBreakStarted` / `onAdBreakEnded` / `onAllAdsCompleted` /
`onAdError` and a content `onError` fallback. Its bridge copy installs `ads`
(which pulls the native IMA plugin and the BrightcoveIMA Swift package
automatically).

## Verification

- Ads sample typecheck, ESLint, and Jest: the ad tag is handed to the player and
  the ad event handlers are wired.
- Web bridge coverage: ad lifecycle events are forwarded; a post-mount ad
  configuration change reports `ad_config_init_only`.
- `scripts/check-bridge-copies.sh`.
- Android release build and iOS Release simulator build.

There is no Android/iOS unit test that drives the ads feature directly; the
native ad path is exercised by the sample against the demo VMAP tag.
