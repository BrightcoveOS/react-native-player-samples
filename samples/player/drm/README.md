# DRM

A standalone bare React Native application that plays a DRM-protected Video
Cloud video — **Widevine on Android and FairPlay on iOS**. It embeds its own
copy of the bridge (core + the `drm` feature) under
`modules/brightcove-player` and consumes it through React Native autolinking as
`@brightcove/react-native-player`.

**Support:** this sample is in the supported set — see
[`docs/supported-samples.md`](../../../docs/supported-samples.md).

There are **no DRM props**: protection is a property of the video in the
catalog. The Playback API response carries the key systems, the native SDK
detects them, and playback proceeds — the JS usage is identical to basic
playback. A licence failure surfaces through the normalized error contract as
`code: "drm"`.

## What it demonstrates

- Playing a Widevine-protected video on Android and a FairPlay-protected video
  on iOS with no DRM-specific props or setup in JavaScript.
- A licence or key-system failure surfacing as a normalized `code: "drm"` error
  through `onError`.

## The video it ships

Configuration lives in `src/playerConfig.ts` and points at a DRM-packaged demo
video. Because it is encrypted, its frames are **black in screenshots and screen
recordings** — that is content protection working, not a fault. Watch it on the
device.

Replace the account, policy key, and video id with your own DRM-packaged
content. If your video is not DRM-protected, remove the `drm` feature from this
sample's bridge feature list and re-assemble it (see
[`docs/running-samples.md`](../../../docs/running-samples.md)).

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

## Verifying DRM on Android (emulator is enough)

Widevine has a software security level (L3), so the full licence → keys →
decrypt path runs on the emulator. A playing video alone does not prove DRM
engaged — confirm the handshake in the logs:

```sh
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB shell am force-stop com.brightcove.rnplayersamples.drm   # cold start required
$ADB logcat -c
$ADB shell am start -n com.brightcove.rnplayersamples.drm/.MainActivity
sleep 10
$ADB logcat -d | grep -iE 'WVCdm|onDrmKeysLoaded|security_level'
```

Expected within a few seconds of launch:

- `WVCdm ... License response` — the Widevine licence server responded
- `SetFromLicense ... security_level_: L3` — keys installed (L3 = the
  emulator's software level; a real device with a secure video path negotiates
  L1 automatically, no code change)
- `ExoMediaPlayback: - onDrmKeysLoaded` — the SDK received the keys

Then the UI shows the video playing and the green `Ready video …` status.
Screenshots show the frame on the emulator (L3 decodes in software); on an L1
device the video area comes out black — that is the hardware protection
working, not a bug.

## Verifying FairPlay on iOS (physical device only)

FairPlay has no software level: decryption happens in the device's secure
hardware, which no simulator has. **The iOS Simulator can never play FairPlay
content** — the bridge reports `not_playable` / `fairplay_requires_device`
there by design. Verify on a real device (Xcode → select the device → run),
and expect a black video area in screenshots/recordings: that is FairPlay
working.

The account must be **provisioned for FairPlay licensing** (an Apple FairPlay
certificate package registered with Brightcove). Quick check for any account:

```sh
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://manifest.prod.boltdns.net/license/v1/fairplay_app_cert/<ACCOUNT_ID>"
```

- `200` — FairPlay provisioned; the sample's anonymous
  `BCOVFPSBrightcoveAuthProxy` path works as-is.
- `422` — not provisioned: the manifest may still advertise FairPlay key
  systems, but the application certificate cannot be fetched, so the content
  key session cannot initialise and `AVPlayerItem` fails. Point the sample at
  a provisioned account, or supply that account's publisher/application id to
  `BCOVFPSBrightcoveAuthProxy` in
  `modules/brightcove-player/ios/drm/BrightcoveDrmFeature.mm`.

## Platform notes

- **Android:** Widevine has a software security level (L3), so the full
  licence, key, and decrypt path runs on an emulator. A real device with a
  secure video path negotiates L1 automatically with no code change.
- **iOS:** FairPlay decrypts only in the device's secure hardware. The Simulator
  cannot play protected content; the bridge reports
  `not_playable` / `fairplay_requires_device` there by design.
- **Web:** the browser path uses the web player's own encrypted-media (EME)
  support rather than the native SDKs and is not feature-tested in this
  repository. Verify DRM on the native platforms.

## Known limitations

- There is no cross-platform licence pre-check in the shared API; a licence
  failure surfaces only when playback is attempted.
- iOS FairPlay playback requires a physical device and an account provisioned
  for FairPlay licensing.
- The bundled account is a demonstration account. Replace it before shipping.

## Further reading

- [DRM feature contract](../../../docs/drm.md)
