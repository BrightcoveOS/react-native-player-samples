#import "BrightcoveTimedMetadataFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

@interface BrightcoveTimedMetadataFeature () <AVPlayerItemMetadataOutputPushDelegate>
@end

@implementation BrightcoveTimedMetadataFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  AVPlayerItem *_metadataItem;
  AVQueuePlayer *_metadataPlayer;
  AVPlayerItemMetadataOutput *_metadataOutput;
  NSMutableArray<NSDictionary<NSString *, id> *> *_pendingEvents;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet set];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _pendingEvents = [NSMutableArray array];
}

- (void)setProp:(NSString *)name value:(id)value
{
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveTimedMetadataFeature owns no prop '%@'", name];
}

- (void)onSourceReset
{
  [self detachMetadataOutput];
  [_pendingEvents removeAllObjects];
}

- (void)onPlayerTearDown
{
  [self detachMetadataOutput];
}

- (void)onInvalidate
{
  [self detachMetadataOutput];
  [_pendingEvents removeAllObjects];
}

- (void)onEventEmitterReady
{
  if (![_host typedEventEmitter]) {
    return;
  }
  NSArray<NSDictionary<NSString *, id> *> *pending = [_pendingEvents copy];
  [_pendingEvents removeAllObjects];
  for (NSDictionary<NSString *, id> *event in pending) {
    [self emitEvent:event];
  }
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  AVPlayerItem *item = session.player.currentItem;
  if (item == nil || item == _metadataItem) {
    return;
  }
  [self detachMetadataOutput];

  _metadataItem = item;
  _metadataPlayer = session.player;
  _metadataOutput = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:nil];
  [_metadataOutput setDelegate:self queue:dispatch_get_main_queue()];
  [_metadataItem addOutput:_metadataOutput];
}

- (void)metadataOutput:(AVPlayerItemMetadataOutput *)output
didOutputTimedMetadataGroups:(NSArray<AVTimedMetadataGroup *> *)groups
  fromPlayerItemTrack:(AVPlayerItemTrack *)track
{
  if (output != _metadataOutput || _metadataItem == nil) {
    return;
  }
  for (AVTimedMetadataGroup *group in groups) {
    CMTime currentTime = _metadataPlayer.currentTime;
    if (!CMTIME_IS_NUMERIC(currentTime)) {
      continue;
    }
    Float64 seconds = CMTimeGetSeconds(currentTime);
    if (!isfinite(seconds)) {
      continue;
    }
    for (AVMetadataItem *item in group.items) {
      if (![item.keySpace isEqualToString:AVMetadataKeySpaceID3]) {
        continue;
      }
      NSString *rawFrameId = [item.key isKindOfClass:NSString.class]
          ? (NSString *)item.key
          : nil;
      NSString *frameId = [rawFrameId uppercaseString];
      NSString *value = item.stringValue;
      // Android's public listener exposes Media3 TextInformationFrames only.
      // They map to raw ID3 text-frame IDs (TIT2, TXXX, ...), so filter iOS to
      // the same stable textual subset rather than emitting every string-backed
      // ID3 object under a platform-specific identifier.
      if (frameId.length == 0 || ![frameId hasPrefix:@"T"] || value == nil) {
        continue;
      }
      [self emitAtTime:seconds type:@"id3-text" key:frameId value:value];
    }
  }
}

- (void)outputSequenceWasFlushed:(AVPlayerItemOutput *)output
{
  // A seek or direction change flushes AVFoundation's output sequence. Do not
  // replay or synthesize metadata: the public contract is traversal-based, not
  // exactly-once delivery.
}

- (void)onCuePoints:(BCOVCuePointCollection *)cuePoints
       previousTime:(CMTime)previousTime
        currentTime:(CMTime)currentTime
{
  for (BCOVCuePoint *cuePoint in cuePoints.array) {
    CMTime position = cuePoint.position;
    if (!CMTIME_IS_NUMERIC(position)) {
      continue;
    }
    Float64 seconds = CMTimeGetSeconds(position);
    // iOS represents pre-roll as CMTime.zero, the same number a publisher can
    // use for a real point cue. The public iOS model does not preserve that
    // distinction; Android does. Restrict both platforms to positive positions
    // so the shared contract never claims these two shapes are equivalent.
    if (!isfinite(seconds) || seconds <= 0) {
      continue;
    }
    [self emitAtTime:seconds
                 type:@"cue-point"
                  key:@"type"
                value:cuePoint.type.lowercaseString ?: @""];
  }
}

- (void)detachMetadataOutput
{
  if (_metadataOutput != nil) {
    [_metadataOutput setDelegate:nil queue:NULL];
    [_metadataItem removeOutput:_metadataOutput];
  }
  _metadataOutput = nil;
  _metadataItem = nil;
  _metadataPlayer = nil;
}

- (void)emitAtTime:(double)time type:(NSString *)type key:(NSString *)key value:(NSString *)value
{
  NSDictionary<NSString *, id> *event = @{
    @"time": @(time),
    @"type": type,
    @"key": key,
    @"value": value,
  };
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  if (![host typedEventEmitter]) {
    [_pendingEvents addObject:event];
    return;
  }
  [self emitEvent:event];
}

- (void)emitEvent:(NSDictionary<NSString *, id> *)event
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  auto eventEmitter = [host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  eventEmitter->onTimedMetadata(BrightcovePlayerViewEventEmitter::OnTimedMetadata{
    .time = [event[@"time"] doubleValue],
    .type = std::string([event[@"type"] UTF8String] ?: ""),
    .data = {
      .key = std::string([event[@"key"] UTF8String] ?: ""),
      .value = std::string([event[@"value"] UTF8String] ?: ""),
    },
  });
}

@end
