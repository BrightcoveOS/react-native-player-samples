# Ads (CSAI / Google IMA)

Standalone bare React Native application demonstrating client-side ad insertion
(CSAI) with Google IMA. It embeds its own copy of the bridge under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

The sample uses Brightcove's public demo account and Google's public VMAP ("ad
rules") sample tag to play a pre/mid/post ad schedule around the content, and
shows how to drive and observe client-side ads from React Native:

- The `adTagUrl` prop supplies a single VMAP URL. The VMAP response defines the
  whole schedule — pre-roll, mid-roll, post-roll — so the app never places ad
  cue points itself.
- `onAdStarted` / `onAdCompleted` fire per individual ad, and `onAdBreakStarted`
  / `onAdBreakEnded` bracket each pod. `onAllAdsCompleted` fires once the whole
  schedule finishes.
- `onAdError` reports an ad failure **without** failing content playback: an ad
  failing does not stop the video.

Client-side ads require the Brightcove IMA plugin (Android) and the BrightcoveIMA
Swift package plus Google IMA (iOS); both are pulled in automatically because
this sample's bridge copy installs the ads feature. CSAI and server-side ad
insertion (`adConfigId`) are mutually exclusive and have separate samples.

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

## The video and ad tag it ships

Configuration lives in `src/playerConfig.ts`: a demo account, policy key, and
video id, plus the VMAP `AD_TAG`. Replace the account, policy key, and video with
your own content, and the ad tag with your own VMAP ad tag, before shipping.

## Platform notes

- Android uses the Brightcove IMA plugin; iOS uses the BrightcoveIMA Swift
  package and Google IMA. Both are pulled in automatically by this sample's
  bridge copy.
- The web build uses Brightcove's web player and its IMA integration; ad event
  coverage can differ from native.
- An ad failure surfaces through `onAdError`; it does not fail the content. A
  content failure is reported separately through `onError`.

## Known limitations

- This sample inserts ads client-side via a VMAP ad tag. For server-side ad
  insertion, use the `ssai` sample (`adConfigId`).
- VAST tags, which require the app to define ad positions itself, are
  intentionally out of scope for this sample.
- Ad-break scheduling is Google IMA's: mid-rolls are tied to content positions,
  so seeking past an un-played mid-roll (for example, straight to the end) can
  skip it while the post-roll still plays. That is IMA's VMAP behavior, not the
  sample choosing to skip ads.
- The bundled account and ad tag are demonstration assets. Replace them before
  shipping.

## Further reading

- [Ads (CSAI) feature contract](../../../docs/ads.md)
