#import "BrightcoveFeatureRegistry.h"

#import "airplay/BrightcoveAirPlayFeature.h"
#import "audiodescription/BrightcoveAudioDescriptionFeature.h"
#import "audiotracks/BrightcoveAudioTracksFeature.h"
#import "background/BrightcoveBackgroundPlaybackFeature.h"
#import "buffering/BrightcoveBufferingFeature.h"
#import "captionrendering/BrightcoveCaptionRenderingFeature.h"
#import "captions/BrightcoveCaptionsFeature.h"
#import "chapternavigation/BrightcoveChapterNavigationFeature.h"
#import "controls/BrightcoveControlsFeature.h"
#import "drm/BrightcoveDrmFeature.h"
#import "fullscreen/BrightcoveFullscreenFeature.h"
#import "lifecycle/BrightcovePlaybackLifecycleFeature.h"
#import "live/BrightcoveLiveFeature.h"
#import "offline/BrightcoveOfflinePlaybackFeature.h"
#import "pip/BrightcovePictureInPictureFeature.h"
#import "playbackevents/BrightcovePlaybackEventsFeature.h"
#import "playlists/BrightcovePlaylistsFeature.h"
#import "preloading/BrightcovePreloadingFeature.h"
#import "quality/BrightcoveQualityFeature.h"
#import "sidecarcaptions/BrightcoveSidecarCaptionsFeature.h"
#import "sourceloadingmodes/BrightcoveSourceLoadingModesFeature.h"
#import "thumbnail/BrightcoveThumbnailSeekingFeature.h"
#import "timedmetadata/BrightcoveTimedMetadataFeature.h"
#import "video360/BrightcoveVideo360Feature.h"

#if BRIGHTCOVE_FEATURE_ADS
#import "ads/BrightcoveAdsFeature.h"
#endif

#if BRIGHTCOVE_FEATURE_CAST
#import "cast/BrightcoveCastFeature.h"
#endif

#if BRIGHTCOVE_FEATURE_DAI
#import "dai/BrightcoveDaiFeature.h"
#endif

#if BRIGHTCOVE_FEATURE_SSAI
#import "ssai/BrightcoveSsaiFeature.h"
#endif

#if BRIGHTCOVE_FEATURE_FREEWHEEL
#import "freewheel/BrightcoveFreeWheelFeature.h"
#endif

#if BRIGHTCOVE_FEATURE_OMNITURE
#import "omniture/BrightcoveOmnitureFeature.h"
#endif

#if BRIGHTCOVE_FEATURE_PULSE
#import "pulse/BrightcovePulseFeature.h"
#endif

@implementation BrightcoveFeatureRegistry

+ (NSArray<id<BrightcovePlayerFeature>> *)installedFeatures
{
  NSMutableArray<id<BrightcovePlayerFeature>> *features = [NSMutableArray arrayWithArray:@[
    [BrightcoveAirPlayFeature new],
    [BrightcoveAudioDescriptionFeature new],
    [BrightcoveAudioTracksFeature new],
    [BrightcoveBackgroundPlaybackFeature new],
    [BrightcoveBufferingFeature new],
    [BrightcoveCaptionRenderingFeature new],
    [BrightcoveCaptionsFeature new],
    [BrightcoveChapterNavigationFeature new],
    [BrightcoveControlsFeature new],
    [BrightcoveDrmFeature new],
    [BrightcoveFullscreenFeature new],
    [BrightcovePlaybackLifecycleFeature new],
    [BrightcoveLiveFeature new],
    [BrightcoveOfflinePlaybackFeature new],
    [BrightcovePictureInPictureFeature new],
    [BrightcovePlaybackEventsFeature new],
    [BrightcovePlaylistsFeature new],
    [BrightcovePreloadingFeature new],
    [BrightcoveQualityFeature new],
    [BrightcoveSidecarCaptionsFeature new],
    [BrightcoveSourceLoadingModesFeature new],
    [BrightcoveThumbnailSeekingFeature new],
    [BrightcoveTimedMetadataFeature new],
    [BrightcoveVideo360Feature new],
  ]];

#if BRIGHTCOVE_FEATURE_ADS
  [features addObject:[BrightcoveAdsFeature new]];
#endif

#if BRIGHTCOVE_FEATURE_CAST
  [features addObject:[BrightcoveCastFeature new]];
#endif

#if BRIGHTCOVE_FEATURE_DAI
  [features addObject:[BrightcoveDaiFeature new]];
#endif

#if BRIGHTCOVE_FEATURE_SSAI
  [features addObject:[BrightcoveSsaiFeature new]];
#endif

#if BRIGHTCOVE_FEATURE_FREEWHEEL
  [features addObject:[BrightcoveFreeWheelFeature new]];
#endif

#if BRIGHTCOVE_FEATURE_OMNITURE
  [features addObject:[BrightcoveOmnitureFeature new]];
#endif

#if BRIGHTCOVE_FEATURE_PULSE
  [features addObject:[BrightcovePulseFeature new]];
#endif

  return [features copy];
}

@end
