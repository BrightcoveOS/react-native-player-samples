#import "BrightcoveQualityFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <AVFoundation/AVMetrics.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <CommonCrypto/CommonDigest.h>
#import <limits.h>
#import <math.h>

using namespace facebook::react;

static std::string BrightcoveQualityStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

static void *BrightcoveQualityPresentationSizeContext = &BrightcoveQualityPresentationSizeContext;

static NSString *BrightcoveQualityOpaqueId(NSString *value)
{
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

  NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [result appendFormat:@"%02x", digest[index]];
  }
  return result;
}

@class BrightcoveQualityFeature;

API_AVAILABLE(ios(18.0))
@interface BrightcoveQualityMetricSubscriber : NSObject <AVMetricEventStreamSubscriber>
@property(nonatomic, weak) BrightcoveQualityFeature *feature;
@end

@interface BrightcoveQualityFeature ()
- (void)handleMetricEvent:(AVMetricEvent *)event
           fromPublisher:(id<AVMetricEventStreamPublisher>)publisher API_AVAILABLE(ios(18.0));
@end

@implementation BrightcoveQualityMetricSubscriber

- (void)publisher:(id<AVMetricEventStreamPublisher>)publisher
  didReceiveEvent:(AVMetricEvent *)event API_AVAILABLE(ios(18.0))
{
  [_feature handleMetricEvent:event fromPublisher:publisher];
}

@end

@implementation BrightcoveQualityFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  __weak id<BCOVPlaybackSession> _session;
  AVPlayerItem *_observedItem;
  id _metricEventStream;
  id _metricSubscriber;
  NSString *_sourceId;
  NSString *_lastEventKey;
  double _preferredPeakBitrate;
  BOOL _observingPresentationSize;
  BOOL _sourceFailed;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"preferredPeakBitrate"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _preferredPeakBitrate = 0;
  _sourceFailed = NO;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"preferredPeakBitrate"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveQualityFeature does not own prop '%@'", name];
  }
  if (![value isKindOfClass:NSNumber.class]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveQualityFeature requires a number for '%@'", name];
  }

  double requested = [(NSNumber *)value doubleValue];
  if (!isfinite(requested) || requested < 0 || requested > INT_MAX) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveQualityFeature requires a finite non-negative peak bitrate"];
  }
  _preferredPeakBitrate = round(requested);
  [self applyPreferredPeakBitrate];
}

- (void)onSourceReset
{
  [self stopObserving];
  _sourceId = [NSUUID UUID].UUIDString.lowercaseString;
  _lastEventKey = nil;
  _sourceFailed = NO;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  if (_sourceFailed) {
    return;
  }

  [self stopObserving];
  _session = session;
  AVPlayerItem *item = session.player.currentItem;
  if (item == nil) {
    return;
  }

  _observedItem = item;
  [self applyPreferredPeakBitrate];

  if (@available(iOS 18.0, *)) {
    _metricEventStream = [AVMetricEventStream eventStream];
    [_metricEventStream addPublisher:item];
    [_metricEventStream subscribeToMetricEvent:AVMetricPlayerItemVariantSwitchEvent.class];
    _metricSubscriber = [BrightcoveQualityMetricSubscriber new];
    [(BrightcoveQualityMetricSubscriber *)_metricSubscriber setFeature:self];
    [_metricEventStream setSubscriber:_metricSubscriber queue:dispatch_get_main_queue()];
  }

  // Variant-switch metrics report later adaptive changes, but do not
  // necessarily report the rendition selected for initial playback. Keep the
  // access-log/presentation-size observers active on every iOS version so JS
  // always receives an initial rendition observation.
  [self startAccessLogObservationForItem:item];
}

- (void)onPlaybackError
{
  _sourceFailed = YES;
}

- (void)onPlayerTearDown
{
  [self stopObserving];
  _lastEventKey = nil;
}

- (void)onInvalidate
{
  [self stopObserving];
  _host = nil;
  _session = nil;
}

- (void)applyPreferredPeakBitrate
{
  if (_sourceFailed || _session == nil) {
    return;
  }

  id<BCOVPlaybackController> controller = _host.playbackController;
  if (controller != nil) {
    [controller setPreferredPeakBitRate:_preferredPeakBitrate];
    return;
  }

  AVPlayerItem *item = _session.player.currentItem;
  if (item != nil) {
    item.preferredPeakBitRate = _preferredPeakBitrate;
  }
}

- (void)accessLogEntryAdded:(NSNotification *)notification
{
  AVPlayerItem *item = notification.object;
  if (item != _observedItem) {
    return;
  }
  if (!NSThread.isMainThread) {
    __weak BrightcoveQualityFeature *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf emitRenditionForItem:item];
    });
    return;
  }
  [self emitRenditionForItem:item];
}

- (void)startAccessLogObservationForItem:(AVPlayerItem *)item
{
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(accessLogEntryAdded:)
                                               name:AVPlayerItemNewAccessLogEntryNotification
                                             object:item];
  [item addObserver:self
         forKeyPath:@"presentationSize"
            options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
            context:BrightcoveQualityPresentationSizeContext];
  _observingPresentationSize = YES;
  [self emitRenditionForItem:item];
}

- (void)handleMetricEvent:(AVMetricEvent *)event
           fromPublisher:(id<AVMetricEventStreamPublisher>)publisher API_AVAILABLE(ios(18.0))
{
  if (![event isKindOfClass:AVMetricPlayerItemVariantSwitchEvent.class] ||
      _sourceFailed || _sourceId.length == 0 || _observedItem == nil || (AVPlayerItem *)publisher != _observedItem) {
    return;
  }

  AVMetricPlayerItemVariantSwitchEvent *switchEvent =
      (AVMetricPlayerItemVariantSwitchEvent *)event;
  // A failed switch reports the variant that was attempted, not the one
  // actually playing after this event. Emitting it here would misreport the
  // active rendition as changed when it did not.
  if (!switchEvent.didSucceed) {
    return;
  }

  AVAssetVariant *variant = switchEvent.toVariant;
  AVAssetVariantVideoAttributes *videoAttributes = variant.videoAttributes;
  if (videoAttributes == nil) {
    return;
  }

  id<BCOVPlaybackSession> session = _session;
  NSString *videoId = session.video.properties[[BCOVVideo PropertyKeyId]];
  if (![videoId isKindOfClass:NSString.class] || videoId.length == 0) {
    return;
  }

  // averageBitRate mirrors the HLS playlist's advertised BANDWIDTH/
  // AVERAGE-BANDWIDTH value, matching what Android reports (Format.bitrate,
  // read from the manifest) and what the iOS 15-17 fallback path below
  // reports (AVPlayerItemAccessLogEvent.indicatedBitrate, also server-
  // advertised). peakBitRate is a ceiling value with different semantics and
  // is intentionally not used here, so `bitrate` means the same thing on
  // every code path in this feature.
  NSInteger bitrate = variant.averageBitRate > 0 ? (NSInteger)llround(variant.averageBitRate) : 0;
  CGSize presentationSize = videoAttributes.presentationSize;
  if (presentationSize.width <= 0 || presentationSize.height <= 0) {
    presentationSize = _observedItem.presentationSize;
  }
  NSInteger width = presentationSize.width > 0 ? (NSInteger)llround(presentationSize.width) : 0;
  NSInteger height = presentationSize.height > 0 ? (NSInteger)llround(presentationSize.height) : 0;

  // Identity: prefer a real per-rendition URL/stableID where the OS actually
  // exposes one. iOS 26 offers both on videoRendition; below that, neither
  // AVAssetVariant nor AVMetricPlayerItemVariantSwitchEvent expose a URL or
  // stable ID (both are 26.0+ APIs), so add the codec list — available since
  // iOS 15 on AVAssetVariantVideoAttributes — to the identity input. This
  // does not fully eliminate collisions on iOS 18-25 (two variants with
  // identical codec/bitrate/resolution and no exposed URL are genuinely
  // indistinguishable through this API on those OS versions), but it stops
  // the common case of same-resolution/bitrate H.264 vs HEVC renditions
  // from being merged into one id.
  //
  // videoRendition/AVMetricMediaRendition are iOS 26.0+ *SDK* symbols, not
  // just runtime-guarded APIs: an Xcode toolchain whose SDK predates iOS 26
  // does not declare the type at all, so @available alone does not compile.
  // __IPHONE_OS_VERSION_MAX_ALLOWED gates on the SDK actually building this,
  // and @available still gates the call on the device actually running it.
  NSString *renditionKey = @"";
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
  if (@available(iOS 26.0, *)) {
    AVMetricMediaRendition *rendition = switchEvent.videoRendition;
    renditionKey = rendition.stableID ?: rendition.URL.absoluteString ?: @"";
  }
#endif
  if (renditionKey.length == 0) {
    NSArray<NSNumber *> *codecTypes = videoAttributes.codecTypes ?: @[];
    renditionKey = [codecTypes componentsJoinedByString:@","];
  }

  [self emitRenditionWithVideoId:videoId
                         bitrate:bitrate
                            width:width
                           height:height
                     renditionKey:renditionKey];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context
{
  if (context == BrightcoveQualityPresentationSizeContext && object == _observedItem &&
      [keyPath isEqualToString:@"presentationSize"]) {
    if (!NSThread.isMainThread) {
      __weak BrightcoveQualityFeature *weakSelf = self;
      AVPlayerItem *item = (AVPlayerItem *)object;
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf emitRenditionForItem:item];
      });
      return;
    }
    [self emitRenditionForItem:_observedItem];
    return;
  }
  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)emitRenditionForItem:(AVPlayerItem *)item
{
  if (_sourceFailed || _sourceId.length == 0 || item != _observedItem) {
    return;
  }

  id<BCOVPlaybackSession> session = _session;
  NSString *videoId = session.video.properties[[BCOVVideo PropertyKeyId]];
  if (![videoId isKindOfClass:NSString.class] || videoId.length == 0) {
    return;
  }

  AVPlayerItemAccessLogEvent *accessLogEvent = item.accessLog.events.lastObject;
  if (accessLogEvent == nil) {
    return;
  }
  double indicatedBitrate = accessLogEvent.indicatedBitrate;
  NSInteger bitrate = indicatedBitrate > 0 ? (NSInteger)llround(indicatedBitrate) : 0;
  CGSize presentationSize = item.presentationSize;
  NSInteger width = presentationSize.width > 0 ? (NSInteger)llround(presentationSize.width) : 0;
  NSInteger height = presentationSize.height > 0 ? (NSInteger)llround(presentationSize.height) : 0;
  NSString *uri = accessLogEvent.URI ?: @"";
  [self emitRenditionWithVideoId:videoId
                         bitrate:bitrate
                            width:width
                           height:height
                     renditionKey:uri];
}

- (void)emitRenditionWithVideoId:(NSString *)videoId
                         bitrate:(NSInteger)bitrate
                            width:(NSInteger)width
                           height:(NSInteger)height
                     renditionKey:(NSString *)renditionKey
{
  NSString *renditionInput = [NSString stringWithFormat:@"%@|%@|%ld|%ld|%ld",
                                                          _sourceId,
                                                          renditionKey,
                                                          (long)bitrate,
                                                          (long)width,
                                                          (long)height];
  if ([_lastEventKey isEqualToString:renditionInput]) {
    return;
  }

  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  _lastEventKey = renditionInput;

  eventEmitter->onRenditionChanged(BrightcovePlayerViewEventEmitter::OnRenditionChanged{
    .sourceId = BrightcoveQualityStdStringFromNSString(_sourceId),
    .videoId = BrightcoveQualityStdStringFromNSString(videoId),
    .renditionId = BrightcoveQualityStdStringFromNSString(BrightcoveQualityOpaqueId(renditionInput)),
    .bitrate = (double)bitrate,
    .width = (double)width,
    .height = (double)height,
  });
}

- (void)stopObserving
{
  if (_observedItem != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemNewAccessLogEntryNotification
                                                  object:_observedItem];
    if (_observingPresentationSize) {
      [_observedItem removeObserver:self
                         forKeyPath:@"presentationSize"
                            context:BrightcoveQualityPresentationSizeContext];
    }
  }
  [(id)_metricSubscriber setFeature:nil];
  _metricSubscriber = nil;
  _metricEventStream = nil;
  _observedItem = nil;
  _observingPresentationSize = NO;
  _session = nil;
}

@end
