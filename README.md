# Brightcove Player Samples for React Native

This repository contains sample applications for playing Brightcove video in
React Native apps on Android and iOS, with web support available for selected
samples through React Native Web.

Each sample is a small, self-contained application focused on a specific player
capability, such as basic playback, closed captions, playlists, advertising
(client-side and server-side), DRM, Picture-in-Picture, offline playback, and
playback-state/live-DVR reporting.

Use the samples to see Brightcove features working end to end, understand the
required React Native and native integration, and adapt the relevant
implementation for your own application.

> **Note:** This repository is a collection of runnable examples, not an npm
> package. Each sample can be built and used independently.

## Repository structure

* **`samples/`** — runnable sample applications, organized by player capability.
* **`docs/`** — setup guides, platform-specific instructions, and
  troubleshooting information.
* **`reference/`** — canonical source for the React Native bridge used by the
  samples. See [The bridge model](#the-bridge-model) for details.

## The supported set

This repository contains only the validated, customer-supported samples. Each
one is documented with its known limitations and treated as stable for
customers to copy. See
[`docs/supported-samples.md`](docs/supported-samples.md) for the list and the
support bar.

## The bridge model

React Native applications interact with the Brightcove native player SDKs through
a native bridge.

The React Native component exposes the player API to JavaScript, while the
underlying native implementation integrates with the Brightcove Player SDK for
Android or iOS.

Each sample includes its own copy of this bridge under:

```text
modules/brightcove-player
```

This keeps every sample self-contained. You can copy a complete sample folder and
build it without depending on other parts of this repository.

Each sample's `package.json` depends on that embedded copy through a `file:`
dependency (`"@brightcove/react-native-player": "file:./modules/brightcove-player"`),
which React Native autolinks. To adopt the bridge in your own app, copy the
`modules/brightcove-player` directory into your project and add the same `file:`
dependency.

The `reference/` directory contains the canonical source used to maintain the
sample bridges. When you are only running or reading an individual sample, you do
not need to interact with it. When you change **which features** a bridge copy
contains, edit the copy in `reference/` and regenerate the sample's copy with
`scripts/assemble-bridge.sh` (see
[`docs/running-samples.md`](docs/running-samples.md)).

## Advertising

Brightcove supports both client-side and server-side advertising workflows.

**Client-side advertising (CSAI)** uses an ad tag URL (VMAP). Ads are requested
and played by the client alongside the video content.

**Server-side ad insertion (SSAI)** combines content and advertising into the
stream before it reaches the player, allowing the application to play a
continuous stream containing both.

This repository ships the **SSAI** sample, which drives server-side advertising
through the `adConfigId` prop, and the **Ads** sample, which drives client-side
advertising (CSAI) through a VMAP `adTagUrl`. Separate samples demonstrate the
two approaches because their configuration and playback flows differ.

## Who these samples are for

These samples are intended for mobile developers and solutions engineers building
React Native applications using the bare React Native workflow.

You should be comfortable with:

* React Native and npm
* Android Studio for Android development
* Xcode and CocoaPods for iOS development

No prior Brightcove experience is required.

## Requirements

To run the samples, you will need:

* A **Brightcove Video Cloud account** with an account ID and policy key when
  using your own content. The samples include Brightcove demo credentials so you
  can get started immediately.
* **Node.js 22.11 or later.** The repository pins Node 24 in `.nvmrc`, which is
  the version used by CI.
* **Android Studio** with its bundled Java runtime for Android development.
* **Xcode** and **CocoaPods** for iOS development.
* A **physical device or simulator/emulator**, depending on the capability being
  demonstrated.

Some supported paths — FairPlay DRM, iOS Picture-in-Picture, and offline DRM —
require physical hardware.

### Platform versions

| Item                      | Version                          |
| ------------------------- | -------------------------------- |
| React Native              | 0.86.2                           |
| React                     | 19.2.3                           |
| React Native architecture | New Architecture                 |
| Android                   | minSdk 24, target/compile SDK 36 |
| iOS                       | 15.1 or later                    |
| Node.js                   | 22.11 or later (24 tested)       |

The player bridge uses React Native Fabric and Codegen and therefore requires the
React Native New Architecture.

These are the versions the samples are built and tested against. The code may run
on other versions, but those are not guaranteed.

The initial installation also requires an internet connection to download
JavaScript and native dependencies.

### Integrating into an existing application

If you are adapting a sample into an app that already exists, in addition to
meeting the platform versions above:

* The app must use the React Native New Architecture.
* **Android:** add Brightcove's Maven repository to the app's Gradle
  configuration:

  ```gradle
  maven { url "https://repo.brightcove.com/releases" }
  ```

* **iOS:** the app target must link the `BrightcovePlayerSDK` product from
  `https://github.com/brightcove/brightcove-player-sdk-ios.git`, up to the next
  major version from `7.2.16`, so Xcode links and embeds the dynamic framework.

## Run your first sample

The **Basic Playback** sample is the simplest place to start.

From the repository root:

```sh
cd samples/player/basic-playback

# Install JavaScript dependencies
npm install

# Install iOS native dependencies
(cd ios && bundle install && bundle exec pod install)

# Start Metro
npm start
```

With Metro running, open a second terminal and launch the application:

```sh
npm run android
```

or:

```sh
npm run ios
```

The sample uses Brightcove demo content by default, so you can run it without
configuring your own Video Cloud account.

To use your own content, replace the account ID, policy key, and video ID in the
sample's configuration. Most samples keep these in `src/playerConfig.ts`; the
Fullscreen and Offline Playback samples define them near the top of `App.tsx`.

For a self-contained Release build that does not need Metro (and, on Android, how
to sign the unsigned APK), see the Release-build sections of
[`docs/running-samples.md`](docs/running-samples.md).

## Choosing a sample

Samples under `samples/player` are organized by capability. Each sample README
contains setup instructions, platform details, and information specific to that
feature. The supported samples are listed in
[`docs/supported-samples.md`](docs/supported-samples.md).

A good path through the supported samples is:

1. **Basic Playback** — play a single Brightcove video.
2. **Closed Captions** — work with text tracks and caption selection.
3. **Playlists** — play multiple videos as a queue.
4. **Picture-in-Picture** — continue playback outside the main application view.
5. **Fullscreen** — integrate native fullscreen playback.
6. **Custom Controls** — build your own player controls.
7. **DRM** — play protected content using Widevine or FairPlay.
8. **Offline Playback** — download content and play it without a network
   connection.
9. **SSAI** — play a stream with server-side advertising.
10. **Ads** — insert client-side ads (CSAI) with a VMAP ad tag.
11. **Playback State** — observe playback lifecycle/progress and live-DVR state,
    and seek to the live edge.
12. **Background Playback** — keep audio playing when the app is backgrounded,
    with lock-screen and notification controls.

You can start with the capability closest to your use case and copy the complete
sample as a foundation for your implementation.

## Platform support

All samples provide Android and iOS implementations. Selected samples additionally
support the web through React Native Web and Brightcove's web player.

| Sample             | Android | iOS | Web     |
| ------------------ | :-----: | :-: | :-----: |
| Basic Playback     |    ✓    |  ✓  |    ✓    |
| Closed Captions    |    ✓    |  ✓  |    ✓    |
| Playlists          |    ✓    |  ✓  |    —    |
| Picture-in-Picture |    ✓    |  ✓  |    ✓    |
| Fullscreen         |    ✓    |  ✓  |    —    |
| Custom Controls    |    ✓    |  ✓  |    —    |
| DRM                |    ✓    |  ✓  | partial |
| Offline Playback   |    ✓    |  ✓  |    —    |
| SSAI               |    ✓    |  ✓  |    ✓    |
| Ads                |    ✓    |  ✓  | partial |
| Playback State     |    ✓    |  ✓  |    ✓    |
| Background Playback |    ✓    |  ✓  |    —    |

* **✓** — implementation is available for the platform.
* **partial** — the platform is present but a capability differs from native;
  see the sample's README.
* **—** — the sample does not provide an implementation for that platform.

Web support uses Brightcove's web player rather than the Android or iOS SDKs, so
capabilities and APIs may differ between native and web implementations. DRM on
web relies on the web player's own encrypted-media support and is not
feature-tested in this repository. Refer to each sample's README for
platform-specific behavior.

## Common questions

### Do I need to be online?

Streaming samples require a network connection. The Offline Playback sample
demonstrates downloading content for playback without an active connection.

### Which platforms are supported?

Android and iOS are supported throughout the sample collection. Selected samples
also provide web implementations through React Native Web.

### Can I install the bridge as an npm package?

No. The bridge is embedded directly in each sample so that the sample remains
self-contained.

When using an example as the basis for your application, copy the complete sample
or the relevant bridge implementation rather than adding the bridge as a shared
package dependency.

### Where do I configure my Brightcove account?

Account configuration lives in `src/playerConfig.ts` for most samples; the
Fullscreen and Offline Playback samples define it near the top of `App.tsx`.

The samples use Brightcove demo content by default. Replace the demo account ID,
policy key, and video ID with your own values when you are ready to use your
Video Cloud content.

### How do I run the tests?

From an individual sample directory:

```sh
npm run typecheck
npm run lint
npm test
```

For a sample that has a web build, also run `npm run typecheck:web` to check the
browser prop surface, and `npm run web:build` to produce a production web bundle.

### How do I run the web build?

Web-enabled samples (Basic Playback, Closed Captions, Picture-in-Picture, DRM,
SSAI, Ads, and Playback State) run in the browser through React Native Web and
Brightcove's web player. From the sample directory:

```sh
npm install
npm run web
```

Then open `http://localhost:3000`. Use `npm run web:build` for a production
bundle written to the sample's build output directory.

## Troubleshooting

### Native changes are not taking effect

After changing native code or native dependencies, stop Metro and rebuild the
application.

For iOS, rerun CocoaPods when necessary:

```sh
cd ios
bundle exec pod install
```

Then open the `.xcworkspace` rather than the `.xcodeproj`.

### Metro is serving stale code

Restart Metro and reset its cache:

```sh
npm start -- --reset-cache
```

### Android cannot find a device

Start an Android emulator or connect a physical device, then verify that it is
available:

```sh
adb devices
```

You can also wait for a device with:

```sh
adb wait-for-device
```

### Android cannot find Java

Configure `JAVA_HOME` to point to the Java runtime bundled with Android Studio.

### iOS cannot find CocoaPods dependencies

From the `ios/` directory, run:

```sh
bundle install
bundle exec pod install
```

Then open the generated `.xcworkspace`.

### Catalog or playback errors

Check that the account ID, policy key, and video ID are correct and that the
selected video is available to the configured account.

The included demo content can also be used to confirm that the local player
integration is working before switching to your own Video Cloud content.

For additional setup and platform-specific instructions, see
[`docs/running-samples.md`](docs/running-samples.md).

## Getting help

When reporting an issue, include:

* the sample you are running,
* the platform and device or simulator/emulator,
* the command you ran,
* the relevant error output, and
* any configuration changes you made.

This information makes it easier to identify whether the issue comes from the
React Native environment, native platform setup, Brightcove configuration, or the
sample itself.

## License

This repository is licensed under the [Apache License 2.0](LICENSE).
