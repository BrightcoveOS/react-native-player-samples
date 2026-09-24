#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Connects the Brightcove playback controller to iOS background audio playback
 * and MPRemoteCommandCenter (Now Playing / lock-screen controls).
 *
 * Remote command and Now Playing ownership is process-wide, coordinated so that
 * active players take ownership one at a time.
 */
@interface BrightcoveBackgroundPlaybackFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
