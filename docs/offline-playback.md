# Offline Playback and Downloads

## Scope

The offline feature is an app-scoped download manager plus an offline player
source. Downloads are durable native SDK records, not props on a player view:
they survive view unmounts, React reloads, and normal app process recreation.
The native SDK remains the source of truth; JavaScript restores state with
`listDownloads()` and receives subsequent item updates from one event stream.

The public surface is:

```ts
OfflinePlayback.requestDownload({ accountId, policyKey, videoId });
OfflinePlayback.requestDownloads(requests); // serial request acceptance helper
OfflinePlayback.listDownloads();
OfflinePlayback.pauseDownload(localId);
OfflinePlayback.resumeDownload(localId);
OfflinePlayback.cancelDownload(localId);
OfflinePlayback.removeDownload(localId);
OfflinePlayback.addDownloadChangedListener(listener);

<BrightcovePlayerView
  accountId={accountId}
  policyKey={policyKey}
  videoId=""
  offlineSourceId={download.localId}
/>
```

`localId` is opaque. Android currently uses the Video Cloud video ID because
the offline store keys persisted records that way; iOS uses the SDK's persistent
`BCOVOfflineVideoToken`. Consumers must store and pass it back unchanged.

`offlineSourceId` is an offline-only feature prop and is mutually exclusive
with `videoId`. The player feature resolves it from durable native storage and
does not make a new Playback API request. `accountId` and `policyKey` remain
required component props for the existing bridge shape; they are not used to
retrieve a local source after it has been selected.

Each `OfflineDownload` has a normalized state (`queued`, `downloading`,
`paused`, `completed`, `failed`, `cancelled`, `cancelling`, `deleting`, or the
terminal event-only `removed`), optional progress/total bytes, a normalized
error where available, and optional `licenseExpiresAt`. A platform reports an
unknown size as `undefined`, not a fabricated value. iOS reports
`bytesDownloaded` as 0 because AVFoundation exposes no byte counter for a
download; treat it as unavailable there and use `progress`, which both
platforms report as a 0-100 percentage (or `undefined` while unknown).

## Intentional v1 limits

- `requestDownload` is one asset. Neither shipped native SDK exposes an atomic
  batch/scheduler API. `requestDownloads` serially asks native code to accept
  each item; it does not promise transfer order, atomicity, or force-quit
  continuation.
- Android's offline plugin supports offline-enabled DASH/Widevine content;
  iOS supports HTTPS HLS and FairPlay. The shared API does not claim a common
  media format, DRM purchase/rental policy, automatic licence acquisition, or
  automatic licence renewal.
- `licenseExpiresAt` is populated when the platform exposes it (iOS FairPlay,
  Android persisted Widevine video metadata). There is no cross-platform expiry
  change event; refresh with `listDownloads()` when displaying stored content.
- A downloaded item cannot be removed while it is the active local source of a
  player. The native modules reject that destructive race with
  `active_offline_source`; switch the view back to an online/other source first.
  This is enforced by a per-id refcount held while the source is loaded, so the
  guard is exact: the id becomes removable as soon as no player owns it.
- One `localId` belongs to one account/policy at a time. On Android the store is
  keyed by video ID, so requesting the same `videoId` under a different
  `accountId`/`policyKey` while a download for it exists is rejected with
  `invalid_configuration` rather than silently routing later
  pause/resume/remove calls to the wrong catalog. Remove the existing download
  first if the account changed. Apps that need the same content under multiple
  accounts must keep separate app installs or wait for a store keyed by
  account+video (not in v1).
- iOS background-session restoration is SDK-managed but Apple does not resume a
  transfer after every force-quit/reboot scenario. The bridge never claims
  otherwise.

## Android implementation

The selected feature adds the Brightcove offline-playback plugin through the
generated `BRIDGE:FEATURE_DEPS` block in `android/build.gradle`, at the same
`brightcoveSdkVersion` the copy pins for the core SDK; non-offline sample
copies do not include that plugin. `BrightcoveOfflinePlaybackModule` is a
Codegen TurboModule registered only by an offline feature's generated Android
registry.

The module resolves a requested Video Cloud asset through the ordinary
`Catalog` (the same proven online Playback API path as the player view), then
passes that `Video` to persistent `OfflineCatalog.downloadVideo`. The offline
plugin's own `findVideoByID` produces an internal `No JSON` failure with this
SDK version despite a valid Playback API response, so it is deliberately not
used for online resolution. `OfflineCatalog` remains responsible for the
durable queue/store, control operations, status, and download listener events.

`BrightcoveOfflinePlaybackFeature` uses `OfflineCatalog.findOfflineVideoById`,
checks `DownloadStatus.STATUS_COMPLETE`, sets
`OfflineStoreManager.getInstance(context)` on the ExoPlayer display, then adds
the local video through the normal `BrightcoveExoPlayerVideoView` source path.
The core's ready event accepts a feature-provided video ID before `add(video)`:
the Android persisted `Video` can synchronously emit `BUFFERING_COMPLETED`
without retaining its original public ID, so relying only on the event payload
would incorrectly emit an empty `onReady.videoId`.

While a local source is loaded, the feature holds a refcount on that
`offlineSourceId` in the process-wide `OfflinePlaybackActiveSources` latch, and
releases it in `onSourceReset`. `removeDownload` calls `beginRemoval` on the
same latch and is rejected with `active_offline_source` while the count is
non-zero, so a download cannot be deleted out from under the ExoPlayer that is
reading it. The core must therefore run each feature's `onSourceReset` in the
same Fabric commit that replaces the source — including a change of only
`offlineSourceId`. `commitConfiguration` flushes the pending reset once before
and once after buffered feature props (`SourceResetScheduler`), so a reset armed
from inside a feature's `setProp` is not deferred to an unrelated later commit,
which would both leak the outgoing id's refcount and drop the incoming,
still-playing source's refcount. `SourceResetSchedulerTest` covers the ordering.

The module also remembers each download's account/policy (persisted in
`SharedPreferences`) so pause/resume/remove resolve the right `OfflineCatalog`.
It prunes that record whenever the SDK reports a download deleted
(`onDownloadDeleted`), covering our own removal, a licence expiry, or an
external delete — otherwise a deleted id keeps its credentials forever and
wrongly blocks a later download of the same id under a different account.

## iOS implementation

`BrightcoveOfflinePlaybackStore` owns the singleton
`BCOVOfflineVideoManager` and is its one delegate. It fans native progress,
pause, completion, storage-change, and failure notifications to the module,
which maps current `BCOVOfflineVideoStatus` records into `OfflineDownload`
events. The store also owns the Brightcove FairPlay authorization proxy.

The module resolves an online `BCOVVideo` with `BCOVPlaybackService`, validates
`canBeDownloaded`, and calls `requestVideoDownload`. It lists/control/deletes
the SDK's persistent offline tokens, exposes
`fairPlayLicenseExpiration(token)` as `licenseExpiresAt`, and preserves native
domain/code in `nativeCode` for errors.

The player feature obtains a local `BCOVVideo` via
`videoObjectFromOfflineVideoToken`, verifies `playableOffline`, tags it with
the bridge generation, and supplies it through `setVideos:`. It also wraps the
controller's session provider in Brightcove's FairPlay provider before the
controller is created, which is required for offline FairPlay HLS playback.
FairPlay local playback is rejected honestly on the iOS simulator.

The store mirrors the Android latch with its own
`acquireToken`/`deactivateToken` refcount: the feature acquires the token while
it is the active local source and releases it in `onSourceReset`, and
`removeDownload` rejects a token that is still active or already being removed
with `active_offline_source`. As on Android, the reset must fire in the same
commit that replaces the source.

## Bridge composition

`offline` is a normal selected feature in `scripts/feature-catalog.sh` but it
also contributes a TurboModule and Android SDK dependency. The assembler uses
the same catalog to generate all three things:

- Android/iOS feature registries;
- Android `FeatureRegistry.createNativeModules` and module metadata;
- the `BRIDGE:FEATURE_DEPS` block in `android/build.gradle` for selected
  plugin dependencies.

`scripts/check-bridge-copies.sh` verifies the native directories, both feature
registries, public prop surface, and generated Android dependency manifest stay
in agreement. The assembler's feature pruning now uses a Bash argument array:
the old shell-string form embedded literal quote characters in `find -path`
patterns and could silently copy a removed feature back into an unrelated
sample.

## Sample

`samples/player/offline-playback` uses two offline-enabled Native SDK test
assets from account `4800266849001`:

- `1823870923251322266` (Punisher);
- `1767327231984365476` (Redpoll with captions).

It demonstrates a one-item request, serial request acceptance for the
two-item selection, persisted rows, progress/state, local play, licence expiry
when supplied by the native SDK, and safe removal after switching away from an
active local player source.

## Verification

- Offline sample typecheck, ESLint, and Jest: 6 tests covering restoration,
  single/queue request dispatch, local-source selection, return to online, and
  removal state.
- Android `OfflineRemovalAndDownloadCategoryTest` (removal latch, download
  failure categories) and `OfflineCredentialPersistenceTest`.
- `SourceResetSchedulerTest` covering the two-phase reset ordering that keeps
  the active-source refcount correct across an offline-source switch.
- `scripts/check-bridge-copies.sh`.
- Android release builds for basic-playback and offline-playback.
- iOS simulator debug builds for basic-playback and offline-playback.
- Android emulator runtime: native module registration, online playback,
  offline-enabled asset download completion, persisted state after reinstall,
  and playback via `offlineSourceId` after both Wi-Fi and mobile data were
  disabled. `onReady` reported the original Video Cloud ID after the persisted
  video-ID fix. Removal was verified in both directions: removing a source the
  player had switched away from succeeds, while removing the still-active
  source returns the documented `active_offline_source` error without crashing.

The iOS simulator build proves Codegen, autolinking, TurboModule registration,
offline manager initialization, and the local-source/FairPlay provider wiring
compile. It cannot prove iOS offline HLS transfer, FairPlay licence expiry, or
offline playback: Apple does not make those paths available on the simulator.
Those require a physical iOS device and an offline-enabled HLS/FairPlay asset.
