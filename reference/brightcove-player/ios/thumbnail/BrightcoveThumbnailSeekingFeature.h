#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Enables the Brightcove iOS SDK's native thumbnail preview while scrubbing.
 * The corresponding Android feature installs the SDK thumbnail plugin's
 * thumbnail-aware media controller.
 */
@interface BrightcoveThumbnailSeekingFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
