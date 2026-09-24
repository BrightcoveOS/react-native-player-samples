#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Reports whether the loaded video is a live (or live-DVR) stream, emits
 * seekable ranges for DVR content, and supports seeking to the live edge.
 *
 * When the SDK determines the video type, this emits onLiveStatus{isLive,hasDvr}
 * to JS and, for a live stream, swaps the player view's control layout to the
 * live (or live-DVR) layout so the live indicator and DVR scrubbing controls
 * appear. A live VideoCloud videoId flows through the same source path as
 * on-demand content, so no separate source model is needed. Owns no props
 * (event-only).
 */
@interface BrightcoveLiveFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
