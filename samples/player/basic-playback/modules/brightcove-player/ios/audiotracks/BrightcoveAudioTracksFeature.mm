#import "BrightcoveAudioTracksFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

using namespace facebook::react;

static std::string BCOVAudioTracksStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

@implementation BrightcoveAudioTracksFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;
  NSString *_audioTrackId;
  __weak id<BCOVPlaybackSession> _audioSession;
  NSArray<AVMediaSelectionOption *> *_options;
  NSString *_activeTrackId;
  NSUInteger _sourceGeneration;
  BOOL _hasExplicitSelection;
}

- (instancetype)init
{
  if (self = [super init]) {
    _audioTrackId = @"";
    _activeTrackId = @"";
    _options = @[];
    _sourceGeneration = 0;
    _hasExplicitSelection = NO;
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"audioTrackId"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"audioTrackId"]) {
    _audioTrackId = [(value ?: @"") copy];
    return;
  }
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveAudioTracksFeature does not own prop '%@'", name];
}

- (void)onSourceReset
{
  _audioSession = nil;
  _options = @[];
  _sourceGeneration += 1;
  _hasExplicitSelection = NO;
  [self emitAudioTracksAvailable];
  _activeTrackId = @"";
  [self emitAudioTrackChanged:@""];
}

- (void)onPropsCommitted
{
  [self applyAudioTrackSelection];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _audioSession = session;
  [self rebuildOptions];
  [self emitAudioTracksAvailable];
  if (_audioSession.selectedAudibleMediaOption != nil) {
    [self setActiveTrackId:[self idForOption:_audioSession.selectedAudibleMediaOption]];
  }
  [self applyAudioTrackSelection];
}

- (void)onSelectedAudibleMediaOption:(AVMediaSelectionOption *)option
{
  if (_host.isInvalidated || _audioSession == nil) {
    return;
  }
  if (option == nil) {
    if (_audioSession.selectedAudibleMediaOption != nil) {
      return;
    }
    [self setActiveTrackId:@""];
    return;
  }
  NSUInteger index = [_options indexOfObject:option];
  if (index == NSNotFound) {
    return;
  }
  [self setActiveTrackId:[self idForOption:option]];
}

- (void)onPlayerTearDown
{
  _audioSession = nil;
}

- (void)onInvalidate
{
  _audioSession = nil;
  _options = @[];
}

- (void)rebuildOptions
{
  AVMediaSelectionGroup *group = [self audibleGroup];
  if (group == nil) {
    _options = @[];
    return;
  }
  NSArray<AVMediaSelectionOption *> *playable =
      [AVMediaSelectionGroup playableMediaSelectionOptionsFromArray:group.options];
  _options = playable ?: @[];
}

- (AVMediaSelectionGroup *)audibleGroup
{
  return _audioSession.audibleMediaSelectionGroup;
}

- (NSString *)idForOption:(AVMediaSelectionOption *)option
{
  if (option == nil) {
    return @"";
  }
  NSUInteger index = [_options indexOfObject:option];
  if (index == NSNotFound) {
    return @"";
  }
  return [NSString stringWithFormat:@"%lu:%lu",
          (unsigned long)_sourceGeneration, (unsigned long)index];
}

- (AVMediaSelectionOption *)optionForId:(NSString *)trackId
{
  if (trackId.length == 0) {
    return nil;
  }
  NSArray<NSString *> *parts = [trackId componentsSeparatedByString:@":"];
  if (parts.count != 2) {
    return nil;
  }
  NSString *genPart = parts[0];
  NSString *indexPart = parts[1];
  if (![genPart isEqualToString:[@(_sourceGeneration) stringValue]]) {
    return nil;
  }
  NSInteger index = indexPart.integerValue;
  if (index < 0 || index >= (NSInteger)_options.count) {
    return nil;
  }
  if (![[@(index) stringValue] isEqualToString:indexPart]) {
    return nil;
  }
  return _options[index];
}

- (NSString *)languageForOption:(AVMediaSelectionOption *)option
{
  NSString *language = option.locale.languageCode;
  if (language.length == 0) {
    language = [option extendedLanguageTag];
  }
  return language ?: @"";
}

- (NSString *)labelForOption:(AVMediaSelectionOption *)option
{
  NSString *label = nil;
  if ([_audioSession respondsToSelector:@selector(displayNameFromAudibleMediaSelectionOption:)]) {
    label = [_audioSession displayNameFromAudibleMediaSelectionOption:option];
  }
  if (label.length == 0) {
    label = option.displayName ?: @"";
  }
  return label ?: @"";
}

- (void)resetSelectionToDefault
{
  if (_hasExplicitSelection) {
    _hasExplicitSelection = NO;
    if ([_audioSession respondsToSelector:@selector(selectAudibleMediaOptionAutomatically)]) {
      [_audioSession selectAudibleMediaOptionAutomatically];
    }
  }
  AVMediaSelectionOption *current = _audioSession.selectedAudibleMediaOption;
  [self setActiveTrackId:current ? [self idForOption:current] : @""];
}

- (void)applyAudioTrackSelection
{
  if (_host.isInvalidated || _audioSession == nil) {
    return;
  }
  if (_options.count == 0) {
    [self setActiveTrackId:@""];
    return;
  }

  if (_audioTrackId.length > 0) {
    AVMediaSelectionOption *chosen = [self optionForId:_audioTrackId];
    if (chosen != nil) {
      _hasExplicitSelection = YES;
      _audioSession.selectedAudibleMediaOption = chosen;
      [self setActiveTrackId:_audioTrackId];
      return;
    }

    // Requested track id is invalid or from a stale source generation.
    // Do not reinterpret stale source-scoped IDs on the new source.
    [self resetSelectionToDefault];
    return;
  }

  // audioTrackId is empty (use SDK default).
  // If an explicit track was previously selected and is now cleared,
  // restore automatic selection using the documented SDK API.
  // Otherwise, leave the default selection intact.
  if (_hasExplicitSelection) {
    [self resetSelectionToDefault];
  }
}

- (void)setActiveTrackId:(NSString *)trackId
{
  if ([_activeTrackId isEqualToString:trackId]) {
    return;
  }
  _activeTrackId = [trackId copy];
  [self emitAudioTrackChanged:trackId];
}

- (void)emitAudioTracksAvailable
{
  std::vector<BrightcovePlayerViewEventEmitter::OnAudioTracksAvailableTracks> tracks;
  for (NSUInteger index = 0; index < _options.count; index++) {
    AVMediaSelectionOption *option = _options[index];
    tracks.push_back({
      .id = BCOVAudioTracksStdStringFromNSString([self idForOption:option]),
      .language = BCOVAudioTracksStdStringFromNSString([self languageForOption:option]),
      .label = BCOVAudioTracksStdStringFromNSString([self labelForOption:option]),
    });
  }

  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    eventEmitter->onAudioTracksAvailable(BrightcovePlayerViewEventEmitter::OnAudioTracksAvailable{
      .tracks = tracks,
    });
  }
}

- (void)emitAudioTrackChanged:(NSString *)trackId
{
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  NSString *language = @"";
  AVMediaSelectionOption *option = [self optionForId:trackId];
  if (option != nil) {
    language = [self languageForOption:option];
  }
  eventEmitter->onAudioTrackChanged(BrightcovePlayerViewEventEmitter::OnAudioTrackChanged{
    .id = BCOVAudioTracksStdStringFromNSString(trackId ?: @""),
    .language = BCOVAudioTracksStdStringFromNSString(language),
  });
}

@end
