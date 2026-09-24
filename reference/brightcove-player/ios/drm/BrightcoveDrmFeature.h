#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * FairPlay DRM: contributes a FairPlay session provider to the playback
 * controller so a FairPlay-packaged Video Cloud source decrypts and plays.
 * FairPlay only works on physical devices, not the iOS Simulator.
 */
@interface BrightcoveDrmFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
