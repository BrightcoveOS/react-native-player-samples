#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * iOS-only AirPlay enablement. The SDK reports the resulting state as
 * external playback; it does not expose an AirPlay device identity.
 */
@interface BrightcoveAirPlayFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
