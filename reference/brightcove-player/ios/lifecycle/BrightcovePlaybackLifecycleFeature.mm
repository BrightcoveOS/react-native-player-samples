#import "BrightcovePlaybackLifecycleFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static void *BCOVPlaybackLifecyclePresentationSizeContext =
    &BCOVPlaybackLifecyclePresentationSizeContext;

@implementation BrightcovePlaybackLifecycleFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  __weak AVPlayerItem *_observedItem;
  BOOL _observingPresentationSize;
  CGSize _lastSize;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet set];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _lastSize = CGSizeZero;
}

- (void)setProp:(NSString *)name value:(id)value
{
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcovePlaybackLifecycleFeature does not own prop '%@'", name];
}

- (void)onSourceReset
{
  [self removePresentationSizeObserver];
  _lastSize = CGSizeZero;
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  [self removePresentationSizeObserver];
  _lastSize = CGSizeZero;

  AVPlayerItem *item = session.player.currentItem;
  if (item == nil) {
    return;
  }

  _observedItem = item;
  _observingPresentationSize = YES;
  [item addObserver:self
         forKeyPath:@"presentationSize"
            options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
            context:BCOVPlaybackLifecyclePresentationSizeContext];
}

- (void)onPlayerTearDown
{
  [self removePresentationSizeObserver];
  _lastSize = CGSizeZero;
}

- (void)onInvalidate
{
  [self onPlayerTearDown];
  _host = nil;
}

- (void)removePresentationSizeObserver
{
  if (_observingPresentationSize && _observedItem != nil) {
    [_observedItem removeObserver:self
                       forKeyPath:@"presentationSize"
                          context:BCOVPlaybackLifecyclePresentationSizeContext];
  }
  _observingPresentationSize = NO;
  _observedItem = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context
{
  if (context == BCOVPlaybackLifecyclePresentationSizeContext &&
      [keyPath isEqualToString:@"presentationSize"] &&
      object == _observedItem) {
    CGSize size = [(AVPlayerItem *)object presentationSize];
    if (size.width <= 0 || size.height <= 0 ||
        CGSizeEqualToSize(size, _lastSize)) {
      return;
    }

    _lastSize = size;
    if (_host == nil || _host.isInvalidated) {
      return;
    }

    auto eventEmitter = [_host typedEventEmitter];
    if (!eventEmitter) {
      return;
    }
    eventEmitter->onVideoSizeChanged(
      BrightcovePlayerViewEventEmitter::OnVideoSizeChanged{
        .width = size.width,
        .height = size.height,
      });
    return;
  }

  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end
