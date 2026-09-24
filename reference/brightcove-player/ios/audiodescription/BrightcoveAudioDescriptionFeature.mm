#import "BrightcoveAudioDescriptionFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static std::string BCOVAudioDescriptionStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

@implementation BrightcoveAudioDescriptionFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  __weak id<BCOVPlaybackSession> _session;
  NSString *_sourceVideoId;
  BOOL _requestedEnabled;
  BOOL _explicitSelectionApplied;
  AVMediaSelectionOption *_previousAudibleOption;
  NSString *_lastAvailabilityKey;
  BOOL _publicStatePublished;
  BOOL _sourceFailed;
  NSString *_lastStateKey;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"audioDescriptionEnabled"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
  _sourceVideoId = @"";
  _requestedEnabled = NO;
  _explicitSelectionApplied = NO;
  _previousAudibleOption = nil;
  _lastAvailabilityKey = nil;
  _publicStatePublished = NO;
  _sourceFailed = NO;
  _lastStateKey = nil;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"audioDescriptionEnabled"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveAudioDescriptionFeature does not own prop '%@'", name];
  }

  if (![value isKindOfClass:NSNumber.class]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveAudioDescriptionFeature requires a Boolean for '%@'", name];
  }

  BOOL requestedEnabled = [(NSNumber *)value boolValue];
  if (_requestedEnabled == requestedEnabled) {
    return;
  }

  _requestedEnabled = requestedEnabled;
  [self applyRequestedSelection];
  [self emitCurrentState];
}

- (void)onSourceReset
{
  _sourceFailed = NO;
  if (_publicStatePublished) {
    [self emitReset];
  }
  [self clearSessionState];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  if (_sourceFailed) {
    return;
  }

  [self clearSessionState];
  _session = session;
  _sourceVideoId = session.video.properties[[BCOVVideo PropertyKeyId]] ?: @"";
  _lastAvailabilityKey = nil;
  _lastStateKey = nil;
  [self rebuildOptionsAndEmitAvailability];
  if (![self applyRequestedSelection]) {
    [self emitCurrentState];
  }
}

- (void)onSelectedAudibleMediaOption:(AVMediaSelectionOption *)option
                             session:(id<BCOVPlaybackSession>)session
{
  if (_sourceFailed || _session == nil || _session != session) {
    return;
  }

  [self rebuildOptionsAndEmitAvailability];
  [self emitCurrentState];
}

- (void)onPlaybackError
{
  _sourceFailed = YES;
  [self clearSessionState];
}

- (void)onPlayerTearDown
{
  [self clearSessionState];
}

- (void)onInvalidate
{
  [self clearSessionState];
  _host = nil;
}

- (void)clearSessionState
{
  _session = nil;
  _sourceVideoId = @"";
  _explicitSelectionApplied = NO;
  _previousAudibleOption = nil;
  _lastAvailabilityKey = nil;
  _lastStateKey = nil;
}

- (void)rebuildOptionsAndEmitAvailability
{
  if (_session == nil) {
    return;
  }

  AVMediaSelectionGroup *group = _session.audibleMediaSelectionGroup;
  NSArray<AVMediaSelectionOption *> *options = group == nil
      ? @[]
      : [AVMediaSelectionGroup playableMediaSelectionOptionsFromArray:group.options];
  BOOL available = [self containsAudioDescriptionOption:options];
  NSString *availabilityKey = [self availabilityKeyForOptions:options];
  if ([_lastAvailabilityKey isEqualToString:availabilityKey]) {
    return;
  }

  _lastAvailabilityKey = availabilityKey;
  auto eventEmitter = [self eventEmitterOrRaise];
  if (eventEmitter) {
    eventEmitter->onAudioDescriptionAvailable(
      BrightcovePlayerViewEventEmitter::OnAudioDescriptionAvailable{
        .videoId = BCOVAudioDescriptionStdStringFromNSString(_sourceVideoId),
        .available = available,
      });
    _publicStatePublished = YES;
  }
}

- (BOOL)applyRequestedSelection
{
  id<BCOVPlaybackSession> session = _session;
  if (_sourceFailed || session == nil) {
    return NO;
  }

  AVMediaSelectionGroup *group = session.audibleMediaSelectionGroup;
  if (group == nil) {
    return NO;
  }

  NSArray<AVMediaSelectionOption *> *options =
      [AVMediaSelectionGroup playableMediaSelectionOptionsFromArray:group.options];
  if (_requestedEnabled) {
    AVMediaSelectionOption *descriptionOption = nil;
    for (AVMediaSelectionOption *option in options) {
      if ([option hasMediaCharacteristic:AVMediaCharacteristicDescribesVideoForAccessibility]) {
        descriptionOption = option;
        break;
      }
    }

    if (descriptionOption == nil) {
      _explicitSelectionApplied = NO;
      _previousAudibleOption = nil;
      return NO;
    }

    if (session.selectedAudibleMediaOption == descriptionOption) {
      return NO;
    }
    if (!_explicitSelectionApplied) {
      _previousAudibleOption = session.selectedAudibleMediaOption;
    }
    _explicitSelectionApplied = YES;
    session.selectedAudibleMediaOption = descriptionOption;
    return YES;
  }

  if (_explicitSelectionApplied) {
    _explicitSelectionApplied = NO;
    AVMediaSelectionOption *previous = _previousAudibleOption;
    _previousAudibleOption = nil;
    if (previous != nil && [options containsObject:previous]) {
      session.selectedAudibleMediaOption = previous;
    } else {
      [session selectAudibleMediaOptionAutomatically];
    }
    return YES;
  }
  return NO;
}

- (void)emitCurrentState
{
  id<BCOVPlaybackSession> session = _session;
  if (_sourceFailed || session == nil) {
    return;
  }

  AVMediaSelectionGroup *group = session.audibleMediaSelectionGroup;
  NSArray<AVMediaSelectionOption *> *options = group == nil
      ? @[]
      : [AVMediaSelectionGroup playableMediaSelectionOptionsFromArray:group.options];
  BOOL available = [self containsAudioDescriptionOption:options];
  AVMediaSelectionOption *selected = session.selectedAudibleMediaOption;
  BOOL enabled = selected != nil &&
      [selected hasMediaCharacteristic:AVMediaCharacteristicDescribesVideoForAccessibility];
  NSString *stateKey = [NSString stringWithFormat:@"%@|%@|%@",
                                                   _sourceVideoId,
                                                   enabled ? @"1" : @"0",
                                                   available ? @"1" : @"0"];
  if ([_lastStateKey isEqualToString:stateKey]) {
    return;
  }

  auto eventEmitter = [self eventEmitterOrRaise];
  if (!eventEmitter) {
    return;
  }
  _lastStateKey = stateKey;
  _publicStatePublished = YES;
  eventEmitter->onAudioDescriptionChanged(
    BrightcovePlayerViewEventEmitter::OnAudioDescriptionChanged{
      .videoId = BCOVAudioDescriptionStdStringFromNSString(_sourceVideoId),
      .enabled = enabled,
      .available = available,
    });
}

- (void)emitReset
{
  auto eventEmitter = [self eventEmitterOrRaise];
  if (!eventEmitter) {
    return;
  }

  eventEmitter->onAudioDescriptionAvailable(
    BrightcovePlayerViewEventEmitter::OnAudioDescriptionAvailable{
      .videoId = "",
      .available = false,
    });
  eventEmitter->onAudioDescriptionChanged(
    BrightcovePlayerViewEventEmitter::OnAudioDescriptionChanged{
      .videoId = "",
      .enabled = false,
      .available = false,
    });
  _lastAvailabilityKey = nil;
  _publicStatePublished = NO;
}

- (NSString *)availabilityKeyForOptions:(NSArray<AVMediaSelectionOption *> *)options
{
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:options.count];
  [options enumerateObjectsUsingBlock:^(AVMediaSelectionOption *option, NSUInteger index, BOOL *stop) {
    NSString *language = option.extendedLanguageTag ?: @"";
    NSString *label = option.displayName ?: @"";
    BOOL describesVideo = [option hasMediaCharacteristic:AVMediaCharacteristicDescribesVideoForAccessibility];
    [parts addObject:[NSString stringWithFormat:@"%lu|%@|%@|%@",
                      (unsigned long)index,
                      language,
                      label,
                      describesVideo ? @"1" : @"0"]];
  }];
  return [parts componentsJoinedByString:@";"];
}

- (BOOL)containsAudioDescriptionOption:(NSArray<AVMediaSelectionOption *> *)options
{
  for (AVMediaSelectionOption *option in options) {
    if ([option hasMediaCharacteristic:AVMediaCharacteristicDescribesVideoForAccessibility]) {
      return YES;
    }
  }
  return NO;
}

- (std::shared_ptr<const BrightcovePlayerViewEventEmitter>)eventEmitterOrRaise
{
  if (_host == nil || _host.isInvalidated) {
    return nullptr;
  }

  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    [NSException raise:NSInternalInconsistencyException
                format:@"BrightcoveAudioDescriptionFeature received an event before its Fabric emitter was available"];
  }
  return eventEmitter;
}

@end
