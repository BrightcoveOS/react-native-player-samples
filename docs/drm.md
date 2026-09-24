# DRM (Widevine and FairPlay)

## Scope

Playback of DRM-protected Video Cloud content on Android (Widevine) and iOS
(FairPlay), plus browser encrypted-media playback on Web.

DRM is **prop-less and command-less**: there is no `drmEnabled` prop, no DRM
event, and no DRM command. Protection is a property of the video in the catalog,
not of the component. The Playback API response carries the key systems, the
platform SDK detects them, and playback proceeds with the same API surface as an
unprotected video.

```ts
// No DRM props. The usage is identical to basic playback:
<BrightcovePlayerView
  accountId={accountId}
  policyKey={policyKey}
  videoId={videoId}
/>
```

A licence failure surfaces through the normalized content error contract with
`code: "drm"`. On the iOS simulator, FairPlay content is rejected before playback
as `not_playable` / `fairplay_requires_device` (see below).

## What DRM requires

- A video packaged with a DRM key system the target platform supports:
  **Widevine** (DASH) for Android, **FairPlay** (HLS) for iOS, and a
  browser-compatible encrypted source for Web.
- An account provisioned for the relevant licence service. For FairPlay the
  account must have an Apple application certificate registered with Brightcove;
  without it the content-key session cannot initialise. See the sample README's
  provisioning check.
- No bridge code or prop: the feature exists so a sample's bridge copy compiles
  the DRM wiring and classifies DRM errors consistently.

## Android

The `drm` feature (`DrmFeature`) is a no-op marker on Android — `ownedProps` is
empty and `attach`/`setProp` do nothing. The Brightcove ExoPlayer integration
detects a Widevine-packaged DASH source from the Playback API response and
negotiates the licence automatically; the bridge does not configure it.

DRM failures are classified by `PlayerErrorClassifier`, which maps the full
Media3 `ERROR_CODE_DRM_UNSPECIFIED .. ERROR_CODE_DRM_LICENSE_EXPIRED` range to
`code: "drm"`. A `DrmSession.DrmSessionException` is unwrapped to its `errorCode`
and classified the same way. No extra Gradle dependency is required.

**Verification ceiling:** Widevine has a software security level (L3), so the
full licence → keys → decrypt path runs on an emulator. A real device with a
secure video path negotiates L1 automatically. Confirm the handshake in logcat
(`WVCdm`, `security_level`, `onDrmKeysLoaded`) rather than by video playing
alone; on an L1 device the captured frame is black by design.

## iOS

`BrightcoveDrmFeature` wires Brightcove's FairPlay authorization proxy
(`BCOVFPSBrightcoveAuthProxy`, nil publisher/application ids → Brightcove's
hosted application certificate and licence server) into the playback
controller's `createFairPlaySessionProviderWithApplicationCertificate:…upstreamSessionProvider:`
chain.

Exactly one feature may contribute a FairPlay session provider. The core throws
an `NSInternalInconsistencyException` if a second provider is added. The offline
feature therefore contributes its own store-backed provider **only when loading
an offline source**; the DRM feature's provider owns all online sources. This is
why a bridge copy that installs both `drm` and `offline` must still build and
play — the CI `drm+offline` scratch compile exercises that composition.

DRM failures are classified in `BCOVErrorCategory`: AVFoundation
`AVErrorContentIsNotAuthorized`/`AVErrorApplicationIsNotAuthorized`, the
FairPlay error domains (`BCOVFPSConstants`, `BCOVFPSBrightcoveAuthProxy`,
`BCOVFairPlayManager`, `AVContentKeySessionErrorDomain`), and the offline
`ExpiredLicense`/`InvalidLicense` codes all map to `code: "drm"`; the category
recurses through `NSUnderlyingErrorKey`.

**Verification ceiling:** FairPlay decryption happens in device hardware that no
simulator has. The simulator reports `not_playable` / `fairplay_requires_device`
by design. Verify on a physical device; expect a black video area under
screenshot/recording, which is content protection, not a fault.

## Web

The Web bridge has **no** DRM/EME integration factory; EME is built into the
`@brightcove/web-sdk` player. The bridge's only DRM-specific code is error
classification: `webErrorClassification.ts` maps the `Eme` category, numeric
codes 3000–3010, 4004, and 5005 to `code: "drm"`. The feature catalog marks DRM
Web support as **partial** — it depends on the browser and the web player's
encrypted-media handling and is not feature-tested in this repository.

## Sample

`samples/player/drm` plays a DRM-protected video from account `6415855237001`
(video `6393164822112`). It uses the same props as basic playback and only adds
`onError` handling to display a `drm` failure. Its README documents the Android
L3 emulator check, the FairPlay physical-device requirement, and the FairPlay
certificate provisioning check.

DRM is also installed by the other protected-content samples
(`basic-playback`, `closed-captions`, `picture-in-picture`, `fullscreen`,
`custom-controls`), which point at the same DRM video.

## Verification

- Android `PlayerErrorClassifierTest`: every Media3 DRM code maps to `drm`, and
  a DRM session manager's untyped pre-echo is not terminally classified.
- iOS `BCOVErrorCategoryTests`: AV not-authorized codes, FairPlay domains, and
  offline licence codes map to `drm`.
- DRM sample web-bridge test: `Eme`/3005, 4004, 5005 classify as `drm`.
- DRM sample typecheck, ESLint, and Jest (error wiring).
- `scripts/check-bridge-copies.sh`, including the scratch `drm + offline` compile.
- Android release build and iOS Release simulator build.
