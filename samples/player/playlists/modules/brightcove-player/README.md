# React Native Player Bridge

Shared New Architecture bridge used by the sample applications in this
repository. The package contains a Codegen-backed Fabric component with native
implementations for Android and iOS.

The Android component wraps `BrightcoveExoPlayerVideoView` and fetches through
`Catalog`. The iOS component wraps `BCOVPUIPlayerView` and fetches through
`BCOVPlaybackService`. Both forward the same ready/error events and own native
player lifecycle and cleanup.

The optional Playlists feature loads a Video Cloud queue from the `videoIds`
prop instead of a single video, resolving each ID from the catalog in order
and handing it to the native SDK's own queue. It supports `repeatMode`
("off"/"one"/"all"), `shuffle`, and imperative `next`/`previous` skip commands,
and reports `onQueueItemChanged`, `onQueueItemFailed`, and `onQueueCompleted`.

On iOS, the podspec declares the SwiftPM product needed to compile the bridge.
The consuming app target must also link `BrightcovePlayerSDK` from
`https://github.com/brightcove/brightcove-player-sdk-ios.git` so the dynamic
framework is embedded in the final application.
