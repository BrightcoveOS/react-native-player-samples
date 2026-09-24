#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Surfaces playback lifecycle to JS: onPlay, onPause, onEnded, and a periodic
 * onProgress carrying the current position and duration (seconds).
 *
 * This reports playback state for the app to react to (custom controls, a
 * progress bar, resume-position). It does NOT configure Brightcove's analytics
 * beacons — the SDK sends those automatically. Owns no props (event-only): it
 * observes the core's lifecycle-event and progress forwards.
 */
@interface BrightcovePlaybackEventsFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
