#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Closed captions: drives the playback session's legible
 * AVMediaSelectionGroup from the captionsEnabled/captionTrackId props and
 * reports the available tracks and the active track to JS.
 */
@interface BrightcoveCaptionsFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
