#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Client-side ad insertion via Google IMA (CSAI), VMAP ("ad rules") only.
 *
 * Owns the adTagUrl prop (a VMAP URL). Contributes a BCOVIMASessionProvider to
 * the playback chain via sessionProviderWithUpstream:, tags each played video
 * with the VMAP ad tag so the IMA plugin requests the schedule, and forwards
 * the IMA ad lifecycle (delivered as BCOVIMA lifecycle events) to the JS onAd*
 * events. Ad errors go to onAdError, never the content onError.
 */
@interface BrightcoveAdsFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
