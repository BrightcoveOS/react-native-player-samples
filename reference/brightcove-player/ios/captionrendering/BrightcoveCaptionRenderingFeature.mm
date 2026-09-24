#import "BrightcoveCaptionRenderingFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static std::string BCOVCaptionRenderingStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

@interface BrightcoveCaptionRenderingFeature () <AVPlayerItemLegibleOutputPushDelegate>
@end

@implementation BrightcoveCaptionRenderingFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  __weak id<BCOVPlaybackSession> _session;
  BOOL _customCaptionRenderingEnabled;
  AVPlayerItemLegibleOutput *_legibleOutput;
  AVPlayerItem *_attachedItem;
}

- (instancetype)init
{
  if (self = [super init]) {
    _customCaptionRenderingEnabled = NO;
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"customCaptionRenderingEnabled"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"customCaptionRenderingEnabled"]) {
    _customCaptionRenderingEnabled = [value boolValue];
    return;
  }
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveCaptionRenderingFeature does not own prop '%@'", name];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _session = session;
  if (!_customCaptionRenderingEnabled || session == nil) {
    return;
  }

  [self attachOutputForSession:session];
}

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                 session:(id<BCOVPlaybackSession>)session
{
  if (!_customCaptionRenderingEnabled || session == nil) {
    return;
  }

  _session = session;
  if (_attachedItem == nil) {
    [self attachOutputForSession:session];
  }
}

- (void)onPropsCommitted
{
  if (_customCaptionRenderingEnabled) {
    if (_session != nil && _legibleOutput == nil) {
      [self attachOutputForSession:_session];
    }
    return;
  }

  [self tearDownLegibleOutput];
  [self emitCue:@"" startTime:0.0 endTime:0.0];
}

- (void)attachOutputForSession:(id<BCOVPlaybackSession>)session
{
  if (!_customCaptionRenderingEnabled) {
    return;
  }

  AVPlayerItem *currentItem = session.player.currentItem;
  if (currentItem == nil) {
    return;
  }

  if (_attachedItem == currentItem && _legibleOutput != nil) {
    return;
  }

  [self tearDownLegibleOutput];

  AVPlayerItemLegibleOutput *output = [[AVPlayerItemLegibleOutput alloc] init];
  output.suppressesPlayerRendering = YES;
  [output setDelegate:self queue:dispatch_get_main_queue()];
  [currentItem addOutput:output];
  _legibleOutput = output;
  _attachedItem = currentItem;
}

- (void)onSourceReset
{
  [self tearDownLegibleOutput];
  _session = nil;
  [self emitCue:@"" startTime:0.0 endTime:0.0];
}

- (void)onPlayerTearDown
{
  [self tearDownLegibleOutput];
  _session = nil;
}

- (void)onInvalidate
{
  [self tearDownLegibleOutput];
  _session = nil;
  _host = nil;
}

- (void)tearDownLegibleOutput
{
  if (_legibleOutput != nil) {
    [_legibleOutput setDelegate:nil queue:NULL];
    if (_attachedItem != nil) {
      [_attachedItem removeOutput:_legibleOutput];
    }
    _legibleOutput = nil;
  }
  _attachedItem = nil;
}

#pragma mark AVPlayerItemLegibleOutputPushDelegate

- (void)legibleOutput:(AVPlayerItemLegibleOutput *)output
    didOutputAttributedStrings:(NSArray<NSAttributedString *> *)attributedStrings
          nativeSampleBuffers:(NSArray *)nativeSampleBuffers
                  forItemTime:(CMTime)itemTime
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated || !_customCaptionRenderingEnabled ||
      output != _legibleOutput) {
    return;
  }

  if (attributedStrings.count == 0) {
    [self emitCue:@"" startTime:0.0 endTime:0.0];
    return;
  }

  NSMutableArray<NSString *> *strings = [NSMutableArray arrayWithCapacity:attributedStrings.count];
  for (NSAttributedString *attrString in attributedStrings) {
    if (attrString.string.length > 0) {
      [strings addObject:attrString.string];
    }
  }

  NSString *text = [strings componentsJoinedByString:@"\n"];
  double startTime = CMTIME_IS_NUMERIC(itemTime) ? CMTimeGetSeconds(itemTime) : 0.0;
  // AVPlayerItemLegibleOutput reports the presentation time but not the cue's
  // end time. Zero is the documented unknown sentinel; never invent a duration.
  [self emitCue:text startTime:startTime endTime:0.0];
}

- (void)emitCue:(NSString *)text startTime:(double)startTime endTime:(double)endTime
{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  auto eventEmitter = [host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  eventEmitter->onCaptionCueChanged(BrightcovePlayerViewEventEmitter::OnCaptionCueChanged{
    .text = BCOVCaptionRenderingStdStringFromNSString(text),
    .startTime = startTime,
    .endTime = endTime,
  });
}

@end
