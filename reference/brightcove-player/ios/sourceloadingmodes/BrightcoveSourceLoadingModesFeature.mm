#import "BrightcoveSourceLoadingModesFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

#import "../core/BCOVErrorCategory.h"

typedef NS_ENUM(NSInteger, BCOVSourceLoadingMode) {
  BCOVSourceLoadingModeNone,
  BCOVSourceLoadingModeVideoReferenceId,
  BCOVSourceLoadingModePlaylistId,
  BCOVSourceLoadingModePlaylistReferenceId,
  BCOVSourceLoadingModeDirectUrl,
};

/**
 * Loads a Video Cloud source from an alternate catalog lookup (video
 * reference ID, playlist ID, playlist reference ID) or a direct HTTPS
 * HLS/MP4 stream, instead of the core's own numeric videoId lookup.
 *
 * Routed through claimsSourceLoading like BrightcoveOfflinePlaybackFeature:
 * exactly one of videoReferenceId, playlistId, playlistReferenceId, or
 * sourceUrl selects this feature as the current source's loader. A playlist
 * mode hands every resolved video to setVideos: at once (SDK-owned
 * end-of-item advancement, matching how the core's own single-video path
 * calls setVideos: with one element); the reported ready id is the
 * playlist's first video.
 */
@implementation BrightcoveSourceLoadingModesFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  NSString *_videoReferenceId;
  NSString *_playlistId;
  NSString *_playlistReferenceId;
  NSString *_sourceUrl;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:@"videoReferenceId", @"playlistId", @"playlistReferenceId", @"sourceUrl", nil];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _videoReferenceId = @"";
  _playlistId = @"";
  _playlistReferenceId = @"";
  _sourceUrl = @"";
}

- (void)setProp:(NSString *)name value:(nullable id)value
{
  NSString *newValue = [value isKindOfClass:NSString.class] ? [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
  __strong NSString **target = NULL;
  if ([name isEqualToString:@"videoReferenceId"]) {
    target = &_videoReferenceId;
  } else if ([name isEqualToString:@"playlistId"]) {
    target = &_playlistId;
  } else if ([name isEqualToString:@"playlistReferenceId"]) {
    target = &_playlistReferenceId;
  } else if ([name isEqualToString:@"sourceUrl"]) {
    target = &_sourceUrl;
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveSourceLoadingModesFeature does not own prop '%@'", name];
    return;
  }
  if (![*target isEqualToString:newValue]) {
    *target = [newValue copy];
    [_host requestSourceReload];
  }
}

- (BCOVSourceLoadingMode)activeMode
{
  if (_videoReferenceId.length > 0) return BCOVSourceLoadingModeVideoReferenceId;
  if (_playlistId.length > 0) return BCOVSourceLoadingModePlaylistId;
  if (_playlistReferenceId.length > 0) return BCOVSourceLoadingModePlaylistReferenceId;
  if (_sourceUrl.length > 0) return BCOVSourceLoadingModeDirectUrl;
  return BCOVSourceLoadingModeNone;
}

- (BOOL)claimsSourceLoading
{
  return [self activeMode] != BCOVSourceLoadingModeNone;
}

- (void)onSourceReset
{
  // No per-request state to clear: each loadSource call is a single
  // fire-and-forget catalog request guarded by isCurrentRequest:, with no
  // queue or resolution loop to reset.
}

- (void)onInvalidate
{
  // Nothing owned beyond the weak host reference.
}

- (BOOL)isValidHttpsStreamURL:(NSString *)urlString
{
  NSURL *url = [NSURL URLWithString:urlString];
  if (url == nil || ![url.scheme.lowercaseString isEqualToString:@"https"] || url.host.length == 0) {
    return NO;
  }
  NSString *path = url.path.lowercaseString;
  return [path hasSuffix:@".m3u8"] || [path hasSuffix:@".m3u"] || [path hasSuffix:@".mp4"];
}

- (void)loadSource:(NSUInteger)requestGeneration
          accountId:(NSString *)accountId
          policyKey:(NSString *)policyKey
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || ![host isCurrentRequest:requestGeneration]) {
    return;
  }

  NSUInteger activeModeCount = (_videoReferenceId.length > 0) + (_playlistId.length > 0) +
      (_playlistReferenceId.length > 0) + (_sourceUrl.length > 0);
  if (activeModeCount > 1) {
    [host emitSourceLoadError:requestGeneration
                          code:@"invalid_configuration"
                    nativeCode:@"source_loading_modes_ambiguous"
                       message:@"Exactly one of videoReferenceId, playlistId, playlistReferenceId, "
                               @"or sourceUrl must be set; multiple were set at once"];
    return;
  }

  BCOVSourceLoadingMode mode = [self activeMode];

  // DirectUrl needs no credentials, but every other mode issues a Playback API
  // request through BCOVPlaybackService, which requires accountId + policyKey.
  // Reject an empty credential loudly here instead of constructing the service
  // with blank strings and failing opaquely downstream.
  if (mode != BCOVSourceLoadingModeNone && mode != BCOVSourceLoadingModeDirectUrl &&
      (accountId.length == 0 || policyKey.length == 0)) {
    [host emitSourceLoadError:requestGeneration
                          code:@"invalid_configuration"
                    nativeCode:@"source_loading_modes_missing_credentials"
                       message:@"accountId and policyKey are required for videoReferenceId, "
                               @"playlistId, and playlistReferenceId sources"];
    return;
  }

  switch (mode) {
    case BCOVSourceLoadingModeDirectUrl:
      [self loadDirectUrl:requestGeneration host:host];
      return;
    case BCOVSourceLoadingModeVideoReferenceId:
      [self loadVideoByReferenceId:requestGeneration accountId:accountId policyKey:policyKey host:host];
      return;
    case BCOVSourceLoadingModePlaylistId:
      [self loadPlaylistWithConfigurationKey:BCOVPlaybackService.ConfigurationKeyAssetID
                                        value:_playlistId
                              requestGeneration:requestGeneration
                                    accountId:accountId
                                    policyKey:policyKey
                                         host:host];
      return;
    case BCOVSourceLoadingModePlaylistReferenceId:
      [self loadPlaylistWithConfigurationKey:BCOVPlaybackService.ConfigurationKeyAssetReferenceID
                                        value:_playlistReferenceId
                              requestGeneration:requestGeneration
                                    accountId:accountId
                                    policyKey:policyKey
                                         host:host];
      return;
    case BCOVSourceLoadingModeNone:
      [host emitSourceLoadError:requestGeneration
                            code:@"invalid_configuration"
                      nativeCode:@"source_loading_modes_missing"
                         message:@"One of videoReferenceId, playlistId, playlistReferenceId, or "
                                 @"sourceUrl must be set when this feature claims the current source"];
      return;
  }
}

- (void)loadDirectUrl:(NSUInteger)requestGeneration host:(id<BrightcovePlayerFeatureHost>)host
{
  if (![self isValidHttpsStreamURL:_sourceUrl]) {
    [host emitSourceLoadError:requestGeneration
                          code:@"invalid_configuration"
                    nativeCode:@"source_loading_modes_invalid_url"
                       message:@"sourceUrl must be a valid https URL ending in .m3u8 or .mp4"];
    return;
  }

  NSURL *url = [NSURL URLWithString:_sourceUrl];
  BCOVVideo *video = [BCOVVideo videoWithURL:url];
  BCOVVideo *taggedVideo = [host taggedAndTransformedVideo:video forGeneration:requestGeneration];
  [host markVideoLoaded:requestGeneration readyVideoId:_sourceUrl];
  [host.playbackController setVideos:@[ taggedVideo ]];
}

- (void)loadVideoByReferenceId:(NSUInteger)requestGeneration
                      accountId:(NSString *)accountId
                      policyKey:(NSString *)policyKey
                           host:(id<BrightcovePlayerFeatureHost>)host
{
  NSString *referenceId = [_videoReferenceId copy];
  BCOVPlaybackService *playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
  __weak __typeof(self) weakSelf = self;
  [playbackService findVideoWithConfiguration:@{
    BCOVPlaybackService.ConfigurationKeyAssetReferenceID: referenceId,
  }
                               queryParameters:nil
                                    completion:^(BCOVVideo *video, id jsonResponse, NSError *error) {
    // Catalog completions arrive on a background queue; the host state and
    // controller this handler touches are main-thread-only. Re-check the
    // request generation on main — the hop is another chance for a reset.
    dispatch_async(dispatch_get_main_queue(), ^{
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) return;
    id<BrightcovePlayerFeatureHost> currentHost = strongSelf->_host;
    if (currentHost == nil || ![currentHost isCurrentRequest:requestGeneration]) return;

    if (error != nil) {
      [currentHost emitSourceLoadError:requestGeneration
                                   code:BCOVErrorCategory(error)
                             nativeCode:[NSString stringWithFormat:@"%@:%ld", error.domain ?: @"", (long)error.code]
                                message:error.localizedDescription ?: @"Unable to retrieve the Brightcove video"];
      return;
    }
    if (video == nil) {
      [currentHost emitSourceLoadError:requestGeneration
                                   code:@"unknown"
                             nativeCode:@"playback_service_empty_response"
                                message:@"Brightcove returned neither a video nor an error"];
      return;
    }

    NSString *readyVideoId = video.properties[[BCOVVideo PropertyKeyId]] ?: referenceId;
    BCOVVideo *taggedVideo = [currentHost taggedAndTransformedVideo:video forGeneration:requestGeneration];
    [currentHost markVideoLoaded:requestGeneration readyVideoId:readyVideoId];
    [currentHost.playbackController setVideos:@[ taggedVideo ]];
    });
  }];
}

- (void)loadPlaylistWithConfigurationKey:(NSString *)configurationKey
                                    value:(NSString *)value
                        requestGeneration:(NSUInteger)requestGeneration
                                accountId:(NSString *)accountId
                                policyKey:(NSString *)policyKey
                                     host:(id<BrightcovePlayerFeatureHost>)host
{
  BCOVPlaybackService *playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
  __weak __typeof(self) weakSelf = self;
  [playbackService findPlaylistWithConfiguration:@{ configurationKey: value }
                                  queryParameters:nil
                                       completion:^(BCOVPlaylist *playlist, id jsonResponse, NSError *error) {
    // Catalog completions arrive on a background queue; hop to main before
    // touching host state or the controller, and re-check the generation.
    dispatch_async(dispatch_get_main_queue(), ^{
    __strong __typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) return;
    id<BrightcovePlayerFeatureHost> currentHost = strongSelf->_host;
    if (currentHost == nil || ![currentHost isCurrentRequest:requestGeneration]) return;

    if (error != nil) {
      [currentHost emitSourceLoadError:requestGeneration
                                   code:BCOVErrorCategory(error)
                             nativeCode:[NSString stringWithFormat:@"%@:%ld", error.domain ?: @"", (long)error.code]
                                message:error.localizedDescription ?: @"Unable to retrieve the Brightcove playlist"];
      return;
    }
    NSArray<BCOVVideo *> *videos = playlist.videos;
    if (playlist == nil || videos.count == 0) {
      [currentHost emitSourceLoadError:requestGeneration
                                   code:@"not_playable"
                             nativeCode:@"source_loading_modes_empty_playlist"
                                message:@"The Brightcove playlist contains no videos"];
      return;
    }

    BCOVVideo *firstVideo = videos.firstObject;
    NSString *readyVideoId = firstVideo.properties[[BCOVVideo PropertyKeyId]]
        ?: firstVideo.properties[[BCOVVideo PropertyKeyReferenceId]]
        ?: @"playlist";
    NSMutableArray<BCOVVideo *> *taggedVideos = [NSMutableArray arrayWithCapacity:videos.count];
    for (BCOVVideo *v in videos) {
      [taggedVideos addObject:[currentHost taggedAndTransformedVideo:v forGeneration:requestGeneration]];
    }
    [currentHost markVideoLoaded:requestGeneration readyVideoId:readyVideoId];
    [currentHost.playbackController setVideos:taggedVideos];
    });
  }];
}

@end
