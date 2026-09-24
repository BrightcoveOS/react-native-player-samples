# SSAI (Server-Side Ad Insertion)

Standalone bare React Native application demonstrating server-side ad insertion
(SSAI) with the Brightcove SSAI plugin. It embeds its own copy of the bridge
under `modules/brightcove-player` and consumes it through React Native
autolinking as `@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

The sample uses Brightcove's public SSAI demo account and an ad-config id to
play a server-stitched stream — content and ads are spliced together on the
server and delivered as a single stream — and shows how to drive and observe
SSAI from React Native:

- The `adConfigId` prop supplies a VideoCloud ad-config id. The video is
  requested with that ad-config so VideoCloud returns a VMAP-bearing stream;
  the native SSAI plugin plays the stitched result. Empty string means no ads.
- `onAdStarted` / `onAdCompleted` fire per individual ad, and `onAdBreakStarted`
  / `onAdBreakEnded` bracket each pod. `onAdError` reports an in-ad failure on
  Android; the iOS SSAI SDK exposes no recoverable per-ad error, so iOS omits
  `onAdError` and surfaces SSAI failures as a content `onError`.
- Unlike client-side ads (CSAI / `adTagUrl`), there is no separate ad video
  element; a VMAP fetch failure prevents the stitched stream from loading and
  therefore surfaces as a content `onError`, not `onAdError`.

SSAI requires the Brightcove SSAI plugin (Android) and the BrightcoveSSAI Swift
package (iOS); both are pulled in automatically because this sample's bridge
copy installs the ssai feature. SSAI is standalone — it does not use Google IMA.

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

## The video it ships

Configuration lives in `src/playerConfig.ts`: an account, policy key, video id,
and the `adConfigId` for the SSAI stream. Replace them with your own
SSAI-enabled account and ad-config id.

## Platform notes

- Android uses the Brightcove SSAI plugin; iOS uses the BrightcoveSSAI Swift
  package. Both are pulled in automatically by this sample's bridge copy.
- The web build uses Brightcove's web player; ad event coverage differs from
  native.
- An ad-config failure before the stitched stream exists surfaces as a content
  `onError`, not `onAdError`. On iOS `onAdError` is not available at all (the
  SDK has no recoverable per-ad error signal).

## Known limitations

- This sample inserts ads server-side. For client-side ads, use the `ads` sample
  (`adTagUrl`).
- The bundled account is a demonstration account. Replace it before shipping.

## Further reading

- [SSAI feature contract](../../../docs/ssai.md)
