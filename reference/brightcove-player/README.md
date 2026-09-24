# React Native Player Bridge

Shared New Architecture bridge used by the sample applications in this
repository. The package contains a Codegen-backed Fabric component with native
implementations for Android and iOS.

The Android component wraps `BrightcoveExoPlayerVideoView` and fetches through
`Catalog`. The iOS component wraps `BCOVPUIPlayerView` and fetches through
`BCOVPlaybackService`. Both forward the same ready/error events and own native
player lifecycle and cleanup.

The optional Quality feature observes adaptive video rendition updates and
emits `onRenditionChanged` with serializable bitrate, resolution, selection mode,
and opaque source-scoped identifiers. It never forwards an Android `Format`, an
iOS access-log object, or a manual quality command to JavaScript.

On iOS, the podspec declares the SwiftPM product needed to compile the bridge.
The consuming app target must also link `BrightcovePlayerSDK` from
`https://github.com/brightcove/brightcove-player-sdk-ios.git` so the dynamic
framework is embedded in the final application.

## Native unit tests

`android/src/test` holds the Android unit tests; `ios/tests` holds their iOS
counterparts. The iOS test project (`ios/tests/BrightcovePlayerCoreTests.xcodeproj`)
compiles the pure classification/validation sources straight from `ios/` — the
same files that ship in the pod, never a copy — and links `BrightcovePlayerSDK`
through SwiftPM (the same `brightcove-player-sdk-ios` package the podspec
resolves), so it needs no React Native/Fabric toolchain or host app:

```sh
cd ios/tests
xcodebuild \
  -project BrightcovePlayerCoreTests.xcodeproj \
  -scheme BrightcovePlayerCoreTests \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

CI runs both suites; when a rule is extracted and tested on one platform, its
parallel on the other must be extracted and tested too.

