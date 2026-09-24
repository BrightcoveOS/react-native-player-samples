#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Server-side ad insertion (SSAI) via the Brightcove SSAI plugin.
 *
 * Owns the adConfigId prop. Adds the ad-config id to the Playback API request
 * (additionalSourceQueryParameters) so VideoCloud returns a VMAP-bearing video,
 * and contributes a BCOVSSAISessionProvider to the playback chain via
 * sessionProviderWithUpstream:, which stitches ads into a single stream. Ad
 * boundaries are observed through the core's ads-delegate forwards (onEnterAd:
 * etc.) and surfaced as the shared onAd* JS events.
 */
@interface BrightcoveSsaiFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
