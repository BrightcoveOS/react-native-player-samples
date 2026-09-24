#import "BrightcoveDrmFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

@implementation BrightcoveDrmFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet set];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveDrmFeature owns no props; received '%@'", name];
}

// Wrap the upstream provider in a FairPlay session provider. The auth proxy
// with nil ids uses Brightcove's hosted FairPlay application certificate and
// licence server, which is what a Video Cloud FairPlay-packaged source expects;
// the SDK fetches the certificate and per-asset licence automatically once the
// provider is in the controller's chain. Returning a wrapping provider (rather
// than configuring the controller after creation) is the only way to enable
// FairPlay, because the provider must exist when the controller is built.
- (BOOL)providesFairPlaySessionProvider
{
  // Exactly one FairPlay provider may wrap the chain. Offline installs its
  // own store-backed provider for local sources and wins there; DRM provides
  // for everything else, so feature-owned online sources (playlists,
  // source-loading-modes) stay FairPlay-playable instead of silently failing
  // license provisioning with zero providers.
  return ![_host hasFeatureProvidingFairPlayExcludingFeature:self];
}

- (id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (id<BCOVPlaybackSessionProvider>)upstream
{
  if ([_host hasFeatureProvidingFairPlayExcludingFeature:self]) {
    return upstream;
  }

  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  BCOVFPSBrightcoveAuthProxy *authProxy =
      [[BCOVFPSBrightcoveAuthProxy alloc] initWithPublisherId:nil
                                                applicationId:nil];
  return [sdkManager createFairPlaySessionProviderWithApplicationCertificate:nil
                                                          authorizationProxy:authProxy
                                                        upstreamSessionProvider:upstream];
}

@end
