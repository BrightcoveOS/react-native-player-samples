#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Google Cast (Chromecast) via the Brightcove Google Cast plugin.
 *
 * Owns the castEnabled prop. When enabled, adds a BCOVGoogleCastManager to the
 * playback controller (which hands the current video off to a selected Cast
 * receiver and back to local playback when the session ends), overlays a
 * GCKUICastButton on the player view so a receiver can be chosen, and forwards
 * GCKCastContext state changes to the JS onCastStateChanged event.
 *
 * Initialization-only: read when the player is first created. Cast discovery
 * requires GCKCastContext to be initialized once at app launch (the sample's
 * AppDelegate does this) and a real Chromecast on the same network — the
 * simulator finds no devices.
 */
@interface BrightcoveCastFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
