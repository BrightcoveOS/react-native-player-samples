# Running the Player Samples

This runbook covers the React Native player samples in this repository. Each
sample is a self-contained bare React Native app that embeds its own copy of
the bridge under `modules/brightcove-player` and consumes it through React
Native autolinking as `@brightcove/react-native-player`. Android calls the
Brightcove Android SDK; iOS calls the Brightcove iOS SDK.

The canonical bridge lives at `reference/brightcove-player`; each sample keeps
an identical copy, and fixes are made in the reference first and propagated to
each sample's `modules/brightcove-player`.

Because a sample is a standalone project with its own `node_modules` and
`package-lock.json`, every command below runs from inside the sample directory
(e.g. `samples/player/basic-playback`) — the directory can even be copied out
of the repository and built on its own.

## Supported samples

The supported samples are listed in
[`supported-samples.md`](supported-samples.md) with their platforms and
limitations. They use the commands in this runbook unchanged:

`ads`, `background-playback`, `basic-playback`, `closed-captions`,
`custom-controls`, `drm`, `fullscreen`, `offline-playback`,
`picture-in-picture`, `playback-state`, `playlists`, `ssai`.

## Requirements

- Node.js 22.11 or later (the repository pins Node 24 in `.nvmrc` and CI tests
  on Node 24).
- Android Studio, the Android SDK, and an Android emulator or device.
- Xcode, an iOS Simulator, Bundler, and CocoaPods.
- Internet access for dependencies and the public Brightcove demo video.

If Xcode is installed at a non-default path, prefix command-line Xcode commands
with `DEVELOPER_DIR="/Applications/<your-xcode>.app/Contents/Developer"`.

## One-time setup

From the sample directory (JavaScript deps also install the embedded bridge via
its `file:` dependency):

```sh
npm install

# iOS native dependencies
bundle install
cd ios && bundle exec pod install && cd ..
```

Always open the generated `.xcworkspace`, never the `.xcodeproj`. The sample's
Xcode project is already configured with the app-target `BrightcovePlayerSDK`
Swift package dependency.

## Android

Development build with Metro (Fast Refresh while editing `App.tsx`):

```sh
npm run start          # terminal 1: Metro
npm run android        # terminal 2
```

Self-contained Release build (JS bundled into the APK, no Metro required — the
most reliable way to run the sample):

```sh
cd android
./gradlew :app:assembleRelease
# The samples intentionally ship no signing keystore, so this build produces
# app-release-unsigned.apk. Sign it with your own release keystore before
# installing on a device (an unsigned APK fails with
# INSTALL_PARSE_FAILED_NO_CERTIFICATES):
apksigner sign --ks <your-release.keystore> \
  --out app-release.apk \
  app/build/outputs/apk/release/app-release-unsigned.apk
adb install -r app-release.apk
adb shell am start -n <applicationId>/.MainActivity
```

For a debug build and the standard user-level debug key, use
`./gradlew :app:installDebug` (or `npm run android`) instead.

`<applicationId>` is the sample's package (e.g.
`com.brightcove.rnplayersamples.basicplayback`). If Gradle cannot find Java, set
`JAVA_HOME` to Android Studio's bundled JDK
(`/Applications/Android Studio.app/Contents/jbr/Contents/Home` on macOS).

## iOS

Run from Xcode:

```sh
npm run start          # Metro
open ios/<App>.xcworkspace
# select the scheme, pick a simulator, press Run
```

Self-contained Release build on the simulator (no Metro, no signing):

```sh
cd ios
xcodebuild   -workspace <App>.xcworkspace   -scheme <App>   -configuration Release   -sdk iphonesimulator   -destination 'generic/platform=iOS Simulator'   -derivedDataPath build   CODE_SIGNING_ALLOWED=NO   build

xcrun simctl boot "<Simulator Name>"
xcrun simctl install booted build/Build/Products/Release-iphonesimulator/<App>.app
xcrun simctl launch booted <bundleId>
```

The expected on-screen status for demo content is `Ready video <videoId>`,
where `<videoId>` is the value configured in that sample. Demo accounts and
video IDs vary; most samples keep them in `src/playerConfig.ts` or near the top
of `App.tsx`.

## Web

Basic Playback, Closed Captions, Picture-in-Picture, DRM, and SSAI have browser
builds. From the sample directory:

```sh
npm install
npm run web
```

Open `http://localhost:3000`. The browser build reuses the sample's `App.tsx`
and resolves the web bridge implementation automatically. Use
`npm run typecheck:web` to validate the browser-only prop surface and
`npm run web:build` to write a production bundle to the sample's build output
directory.

Web uses Brightcove's web player rather than the Android or iOS SDKs, so a
feature can have different platform behavior. Read the sample's Platform notes
before copying it.

## Changing a sample's bridge features

The `reference/brightcove-player` directory is the canonical bridge. A sample
contains only the features it needs; its generated registries and public prop
surface must agree with that feature list. Regenerate a sample bridge instead
of editing those generated files by hand:

```sh
# Example: core + captions + fullscreen + DRM
scripts/assemble-bridge.sh \
  --features "captions,fullscreen,drm" \
  samples/player/closed-captions/modules/brightcove-player
```

Run the command from the repository root. Pass a comma-separated feature list;
use `--features ""` for core only. The script rewrites the Android/iOS feature
registries, the narrowed public TypeScript surface, and feature-dependent native
dependencies. Finish by running `scripts/check-bridge-copies.sh`.

## Troubleshooting

- **`adb: no devices/emulators found`** — start an emulator and wait for it to
  boot (`adb wait-for-device`).
- **Android Gradle cannot find Java** — set `JAVA_HOME` (see above).
- **`xcodebuild` reports only Command Line Tools** — prefix with the full
  `DEVELOPER_DIR` for your Xcode.
- **iOS cannot find Pods** — run `bundle install`, then `bundle exec pod
  install` from `ios/`, and open the `.xcworkspace`.
- **A Catalog or Playback Service error** — confirm the account, policy key,
  and video id. The samples use a public demo asset; transient demo API errors
  usually clear on a restart.
