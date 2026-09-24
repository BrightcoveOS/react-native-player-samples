#import <React/RCTBridgeModule.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <BrightcovePlayerViewSpec/BrightcovePlayerViewSpec.h>
#endif

#ifdef RCT_NEW_ARCH_ENABLED
@interface BrightcoveOfflinePlaybackModule : NativeBrightcoveOfflinePlaybackSpecBase <NativeBrightcoveOfflinePlaybackSpec>
#else
@interface BrightcoveOfflinePlaybackModule : NSObject <RCTBridgeModule>
#endif
@end
