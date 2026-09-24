# React Native Player Bridge

New Architecture bridge over the native Brightcove SDKs, embedded in this
sample and consumed through React Native autolinking as
`@brightcove/react-native-player`. It contains a Codegen-backed Fabric
component with native implementations for Android and iOS.

This is a copy of the canonical implementation in `reference/brightcove-player`
at the repository root. Fixes are made in the reference first and then
propagated to each sample's copy.

The Android component wraps `BrightcoveExoPlayerVideoView` and fetches through
`Catalog`. The iOS component wraps `BCOVPUIPlayerView` and fetches through
`BCOVPlaybackService`. Both forward the same ready/error/playback-state events
and own native player lifecycle and cleanup. The bridge also exposes Fabric
`play`, `pause`, and `seekTo` commands.

When `backgroundPlaybackEnabled` is set, Android uses Brightcove's media-session
and foreground-service notification integration. iOS enables the Brightcove
controller's background audio support and installs remote commands. The
consuming app still has to provide the platform host configuration described in
the sample README; the prop alone is not sufficient.

On iOS, the podspec declares the SwiftPM product needed to compile the bridge.
The consuming app target must also link `BrightcovePlayerSDK` from
`https://github.com/brightcove/brightcove-player-sdk-ios.git` so the dynamic
framework is embedded in the final application.
