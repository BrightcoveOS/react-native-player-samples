#import <Foundation/Foundation.h>

#import "../core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Picture-in-Picture: shows the SDK's PiP button, auto-enters PiP when the
 * app is backgrounded while playing inline, and reports enter/exit to JS.
 */
@interface BrightcovePictureInPictureFeature : NSObject <BrightcovePlayerFeature>
@end

NS_ASSUME_NONNULL_END
