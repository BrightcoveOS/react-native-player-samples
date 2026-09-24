#import "BrightcoveOmnitureFeature.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <BrightcoveAMC/BrightcoveAMC.h>
#import <ADBMediaHeartbeatConfig.h>

@implementation BrightcoveOmnitureFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  NSString *_trackingServer;
  NSString *_channel;
  NSString *_appVersion;
  NSString *_ovp;
  NSString *_playerName;
  BOOL _ssl;
  BOOL _debugLogging;
  __weak id<BCOVPlaybackController> _playbackController;
  BCOVAMCSessionConsumer *_sessionConsumer;
}

- (instancetype)init
{
  if (self = [super init]) {
    _ssl = YES;
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:
      @"heartbeatTrackingServer",
      @"heartbeatChannel",
      @"heartbeatAppVersion",
      @"heartbeatOvp",
      @"heartbeatPlayerName",
      @"heartbeatSsl",
      @"heartbeatDebugLogging",
      nil];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(nullable id)value
{
  if ([name isEqualToString:@"heartbeatTrackingServer"]) {
    _trackingServer = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"heartbeatChannel"]) {
    _channel = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"heartbeatAppVersion"]) {
    _appVersion = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"heartbeatOvp"]) {
    _ovp = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"heartbeatPlayerName"]) {
    _playerName = [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
  } else if ([name isEqualToString:@"heartbeatSsl"]) {
    _ssl = [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value boolValue] : YES;
  } else if ([name isEqualToString:@"heartbeatDebugLogging"]) {
    _debugLogging = [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value boolValue] : NO;
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveOmnitureFeature owns no prop '%@'", name];
  }

  [self ensureSessionConsumer];
}

- (void)configurePlaybackController:(id<BCOVPlaybackController>)playbackController
{
  _playbackController = playbackController;
  [self ensureSessionConsumer];
}

- (void)ensureSessionConsumer
{
  id<BCOVPlaybackController> playbackController = _playbackController;
  if (playbackController == nil || _sessionConsumer != nil ||
      _trackingServer.length == 0 || _channel.length == 0 ||
      _appVersion.length == 0 || _ovp.length == 0 || _playerName.length == 0) {
    return;
  }

  __weak __typeof__(self) weakSelf = self;
  BCOVAMCVideoHeartbeatConfigurationPolicy configPolicy = ^ADBMediaHeartbeatConfig *(id<BCOVPlaybackSession> session) {
    __strong __typeof__(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_trackingServer.length == 0) {
      return nil;
    }

    ADBMediaHeartbeatConfig *config = [ADBMediaHeartbeatConfig new];
    config.trackingServer = strongSelf->_trackingServer;
    config.channel = strongSelf->_channel;
    config.appVersion = strongSelf->_appVersion;
    config.ovp = strongSelf->_ovp;
    config.playerName = strongSelf->_playerName;
    config.ssl = strongSelf->_ssl;
    config.debugLogging = strongSelf->_debugLogging;
    return config;
  };

  BCOVAMCAnalyticsPolicy *policy = [[BCOVAMCAnalyticsPolicy alloc]
      initWithHeartbeatConfigurationPolicy:configPolicy];
  _sessionConsumer = [BCOVAMCSessionConsumer heartbeatAnalyticsConsumerWithPolicy:policy
                                                                          delegate:nil];
  [playbackController addSessionConsumer:_sessionConsumer];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  // Heartbeat tracking is configured only when all five required props are
  // set; the TS contract calls that same empty state "Heartbeat is not
  // configured" — a legal unconfigured copy. Raise only when a heartbeat
  // attempt was expected (every prop set) but the session consumer could not
  // be created — e.g. the controller hook raced the props. A copy with unset
  // props simply plays without tracking.
  if (_sessionConsumer == nil &&
      _trackingServer.length > 0 && _channel.length > 0 &&
      _appVersion.length > 0 && _ovp.length > 0 && _playerName.length > 0) {
    [NSException raise:NSInvalidArgumentException
                format:@"Omniture could not create its session consumer despite "
                        "complete heartbeat configuration (trackingServer, channel, "
                        "appVersion, ovp, playerName)."];
  }
}

- (void)onPlayerTearDown
{
  _sessionConsumer = nil;
  _playbackController = nil;
}

- (void)onInvalidate
{
  _sessionConsumer = nil;
  _playbackController = nil;
}

@end
