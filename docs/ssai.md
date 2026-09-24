# SSAI (Server-Side Ad Insertion)

## Scope

SSAI plays a Brightcove server-stitched stream: content and ads are combined on
the server and delivered as one continuous stream. The app supplies a VideoCloud
ad-config id; the SDK plays the stitched result.

```ts
adConfigId?: string; // VideoCloud ad-config id; mutually exclusive with adTagUrl

onAdStarted?: DirectEventHandler<{ adTitle: string; duration: number }>;
onAdCompleted?: DirectEventHandler<{ adTitle: string; duration: number }>;
onAdBreakStarted?: DirectEventHandler<{ index: number }>;
onAdBreakEnded?: DirectEventHandler<{ index: number }>;
onAdError?: DirectEventHandler<{ code: string; message: string; nativeCode: string }>; // Android-only
```

SSAI and client-side ads (`ads`, via `adTagUrl`) are **mutually exclusive** and
have separate samples. Empty `adConfigId` means no ads and the content plays
without a stitched stream.

## Ad events

- `onAdStarted` / `onAdCompleted` fire per individual ad.
- `onAdBreakStarted` / `onAdBreakEnded` bracket each pod. The `index` is always
  `-1`: the shared contract does not expose a platform ad-roll index (Android/iOS
  ad-roll metadata differs and would not be comparable).
- `onAdError` reports an **in-ad** failure, with
  `code: one of 'load' | 'playback' | 'unknown'`. It is **Android-only**: the
  BrightcoveSSAI iOS SDK surfaces SSAI failures only on the fatal lifecycle
  channel (timeline-load / VMAP-missing, reported as content `onError`), so the
  iOS public entry point (`index.ios.tsx`) omits `onAdError` rather than
  advertising an event that can never fire.
- There is **no `onAllAdsCompleted`** for SSAI: the SSAI plugin exposes no
  all-ads-completed signal, so the feature does not fabricate one.

`duration` is `0` for SSAI ads on Android (the plugin does not surface a usable
ad duration); treat it as unavailable.

## Failure routing

An SSAI failure has two shapes and each is reported truthfully:

- **In-ad failure** while content is already stitched and playing arrives as an
  ad error (`onAdError`) on Android; it does not fail the content. iOS has no
  recoverable in-ad error signal, so this shape does not occur there.
- **VMAP/setup failure before the stitched stream exists** prevents the stream
  from loading and therefore surfaces as a content `onError` on both platforms.
  On Android a missing Activity to build the SSAI component also fails the
  source (`nativeCode: ssai_no_activity`) rather than silently falling back to
  plain content.

## Android

`SsaiFeature` owns `adConfigId`. It adds the ad-config id as a Playback API query
parameter so VideoCloud returns a VMAP-bearing video, then hands the resolved
video to the SDK's `SSAIComponent.processVideo`, which rewrites the source to the
server-stitched stream. Per-listener and per-video generation guards reject stale
stitch/ad events from an outgoing source; `onSourceReset` removes listeners and
nulls the component. It deliberately does **not** suppress content errors, so a
VMAP failure surfaces as a content error while a genuine in-ad failure is an
`onAdError`. It requires the Brightcove SSAI plugin (and thumbnail plugin).

## iOS

`BrightcoveSsaiFeature` owns `adConfigId`, adds the ad-config id to the Playback
Service request, contributes an `BCOVSSAISessionProvider` (only when an ad-config
id is set), and adds `BCOVSSAIAdComponentDisplayContainer` as a session consumer.
Ad sequence/ad enter/exit callbacks map to `onAdBreakStarted`/`Ended` (index
`-1`) and `onAdStarted`/`Completed`. A `kBCOVSSAILifecycleErrorEvent` is routed
to the content error path. There is no `onAdError` on iOS — the SDK exposes no
recoverable per-ad error. It requires the `BrightcoveSSAI` Swift package.

## Web

The Web bridge enables SSAI through the Web SDK's `ssai` integration factory
(`SsaiIntegrationFactory`) when `adConfigId` is set, and reads the SDK's relative
timeline state to emit per-ad and per-break events (breaks use index `-1`).
In-ad OM errors classify as ad errors; VMAP request/parse errors deliberately
stay on the content `onError` path. `adConfigId` is initialization-only on Web:
changing it after mount reports `invalid_configuration` / `ad_config_init_only`.
The feature catalog marks SSAI Web support as **partial**.

## Sample

`samples/player/ssai` plays a stitched stream using a demo account and ad-config
id, wiring `onAdStarted`/`onAdCompleted`/`onAdBreakStarted`/`onAdBreakEnded`/
`onAdError` and a content `onError` fallback. Its bridge copy installs `ssai`
(which pulls the native plugin and Swift package automatically).

## Verification

- SSAI sample typecheck, ESLint, and Jest: the ad-config id is handed to the
  player and the ad event handlers are wired.
- Web bridge coverage: fatal SSAI VMAP setup errors are separated from in-ad OM
  errors; break events report index `-1`; a VMAP setup error fails the source
  instead of reporting an ad-only error; a post-mount ad-config change reports
  `ad_config_init_only`.
- `scripts/check-bridge-copies.sh`.
- Android release build and iOS Release simulator build.

There is no Android/iOS unit test that drives the SSAI feature directly; the
native ad path is exercised by the sample against the demo SSAI stream.
