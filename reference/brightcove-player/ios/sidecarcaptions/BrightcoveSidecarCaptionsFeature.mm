#import "BrightcoveSidecarCaptionsFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>

#import <react/renderer/components/BrightcovePlayerViewSpec/EventEmitters.h>

using namespace facebook::react;

static std::string BCOVSidecarStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

static BOOL BCOVSidecarLanguageIsValid(NSString *language)
{
  if (language.length == 0) {
    return NO;
  }
  NSPredicate *predicate = [NSPredicate predicateWithFormat:
      @"SELF MATCHES %@", @"^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$"];
  return [predicate evaluateWithObject:language];
}

static BOOL BCOVSidecarUrlIsHttps(NSString *url)
{
  if (url.length == 0) {
    return NO;
  }
  NSURLComponents *components = [NSURLComponents componentsWithString:url];
  return [components.scheme.lowercaseString isEqualToString:@"https"] && components.host.length > 0;
}

static NSDictionary *BCOVSidecarFailedTrack(NSString *language, NSString *label, NSString *nativeCode)
{
  return @{@"language": language ?: @"", @"label": label ?: @"", @"nativeCode": nativeCode};
}

@implementation BrightcoveSidecarCaptionsFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;

  NSArray<NSDictionary<NSString *, NSString *> *> *_sidecarTracks;
  NSArray<NSDictionary<NSString *, NSString *> *> *_validTracks;
  BOOL _trackAdded;
  BOOL _sidecarFailureEmitted;
  BOOL _configurationValidated;
  BOOL _configurationDirty;
  AVPlayerItem *_observedItem;
}

- (instancetype)init
{
  if (self = [super init]) {
    _sidecarTracks = @[];
    _validTracks = @[];
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObject:@"sidecarTracks"];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

- (void)setProp:(NSString *)name value:(id)value
{
  if (![name isEqualToString:@"sidecarTracks"]) {
    [NSException raise:NSInvalidArgumentException
                format:@"BrightcoveSidecarCaptionsFeature does not own prop '%@'", name];
  }
  if (value == nil) {
    _sidecarTracks = @[];
  } else {
    _sidecarTracks = [value copy];
  }
  _configurationDirty = YES;
}

- (void)onPropsCommitted
{
  if (!_configurationDirty) {
    return;
  }
  _configurationDirty = NO;
  _configurationValidated = YES;

  NSMutableArray<NSDictionary<NSString *, NSString *> *> *valid = [NSMutableArray array];
  NSMutableSet<NSString *> *seenLanguages = [NSMutableSet set];
  for (NSDictionary<NSString *, NSString *> *track in _sidecarTracks) {
    NSString *url = track[@"url"];
    NSString *language = track[@"language"];
    NSString *label = track[@"label"];
    if (label.length == 0) {
      label = language;
    }
    if (url.length == 0) {
      [self emitStatus:@"failed"
              language:language ?: @""
                 label:label ?: @""
                 error:@"invalid_configuration"
            nativeCode:@"missing_url"];
      continue;
    }
    if (language.length == 0) {
      [self emitStatus:@"failed"
              language:@""
                 label:label ?: @""
                 error:@"invalid_configuration"
            nativeCode:@"missing_language_tag"];
      continue;
    }
    if (!BCOVSidecarUrlIsHttps(url)) {
      [self emitStatus:@"failed"
              language:language
                 label:label
                 error:@"invalid_configuration"
            nativeCode:@"insecure_or_invalid_url"];
      continue;
    }
    if (!BCOVSidecarLanguageIsValid(language)) {
      [self emitStatus:@"failed"
              language:language
                 label:label
                 error:@"invalid_configuration"
            nativeCode:@"invalid_language_tag"];
      continue;
    }
    NSString *languageKey = [language.lowercaseString copy];
    if ([seenLanguages containsObject:languageKey]) {
      [self emitStatus:@"failed"
              language:language
                 label:label
                 error:@"invalid_configuration"
            nativeCode:@"duplicate_language"];
      continue;
    }
    [seenLanguages addObject:languageKey];
    [valid addObject:@{
      @"url": url,
      @"language": language,
      @"label": label,
    }];
  }
  _validTracks = [valid copy];
}

- (void)onSourceReset
{
  [self removeItemObservers];
  _trackAdded = NO;
  _sidecarFailureEmitted = NO;
  [self emitStatus:@"reset" language:@"" label:@"" error:@"" nativeCode:@""];
}

- (id<BCOVPlaybackSessionProvider>)sessionProviderWithUpstream:
    (id<BCOVPlaybackSessionProvider>)upstream
{
  if (_sidecarTracks.count == 0) {
    return upstream;
  }
  BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
  return [sdkManager createSidecarSubtitlesSessionProviderWithUpstreamSessionProvider:upstream];
}

- (BCOVVideo *)willSetVideo:(BCOVVideo *)video
{
  if (_sidecarTracks.count == 0) {
    return video;
  }
  if (!_configurationValidated) {
    [self onPropsCommitted];
  }
  if (_validTracks.count == 0) {
    return video;
  }

  return [video update:^(BCOVMutableVideo *mutableVideo) {
    NSMutableDictionary *properties = [mutableVideo.properties mutableCopy];
    NSMutableArray<NSDictionary *> *textTracks = [NSMutableArray array];
    NSArray<NSDictionary *> *currentTracks = properties[BCOVSSConstants.VideoPropertiesKeyTextTracks];
    if ([currentTracks isKindOfClass:NSArray.class]) {
      [textTracks addObjectsFromArray:currentTracks];
    }
    for (NSDictionary<NSString *, NSString *> *track in self->_validTracks) {
      NSString *url = track[@"url"];
      NSString *language = track[@"language"];
      NSString *label = track[@"label"];
      BOOL collision = NO;
      for (NSDictionary *existingTrack in currentTracks) {
        NSString *existingLanguage = existingTrack[BCOVSSConstants.TextTracksKeySourceLanguage];
        if ([existingLanguage isKindOfClass:NSString.class] &&
            [existingLanguage caseInsensitiveCompare:language] == NSOrderedSame) {
          collision = YES;
          break;
        }
      }
      if (collision) {
        [self emitStatus:@"failed"
                language:language
                   label:label
                   error:@"invalid_configuration"
              nativeCode:@"sidecar_language_collision"];
        continue;
      }
      [textTracks addObject:@{
        BCOVSSConstants.TextTracksKeySource: url,
        BCOVSSConstants.TextTracksKeySourceLanguage: language,
        BCOVSSConstants.TextTracksKeyLabel: label,
        BCOVSSConstants.TextTracksKeyKind: BCOVSSConstants.TextTracksKindSubtitles,
        BCOVSSConstants.TextTracksKeySourceType: BCOVSSConstants.TextTracksKeySourceTypeWebVTTURL,
      }];
      [self emitStatus:@"configured"
              language:language
                 label:label
                 error:@""
            nativeCode:@""];
      self->_trackAdded = YES;
    }
    properties[BCOVSSConstants.VideoPropertiesKeyTextTracks] = textTracks;
    mutableVideo.properties = properties;
  }];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  if (_trackAdded) {
    [self observeItem:session.player.currentItem];
  }
}

- (void)onLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
                   session:(id<BCOVPlaybackSession>)session
{
  if (_trackAdded) {
    [self observeItem:session.player.currentItem];
  }
}

- (void)onSelectedLegibleMediaOption:(AVMediaSelectionOption *)option
{
  if (option == nil || !_trackAdded) {
    return;
  }
  // AVFoundation derives displayName from the option's locale, not the label
  // this feature supplied when injecting the sidecar track, so it can never
  // be relied on to identify the track: requiring an exact match meant a
  // custom label (or a region-qualified tag like "en-US" whose languageCode
  // is only "en") could never emit "selected". Match on the full extended
  // language tag alone, case-insensitively, since that is the value we
  // configured when the track was added.
  NSString *lang = option.extendedLanguageTag ?: option.locale.languageCode;
  if (lang == nil) {
    return;
  }
  for (NSDictionary<NSString *, NSString *> *track in _validTracks) {
    NSString *language = track[@"language"];
    if ([lang caseInsensitiveCompare:language] == NSOrderedSame) {
      [self emitStatus:@"selected"
              language:language
                 label:track[@"label"]
                 error:@""
            nativeCode:@""];
      return;
    }
  }
}

- (void)onPlayerTearDown
{
  [self removeItemObservers];
  _trackAdded = NO;
}

- (void)onInvalidate
{
  [self removeItemObservers];
  _trackAdded = NO;
}

- (void)observeItem:(AVPlayerItem *)item
{
  if (item == nil || item == _observedItem) {
    return;
  }
  [self removeItemObservers];
  _observedItem = item;
  // AVPlayerItemStatusFailed and AVPlayerItemFailedToPlayToEndTimeNotification
  // both describe the primary asset's own playability, not the sidecar text
  // track's load state — attributing either to the sidecar would mask real
  // playback failures as caption errors. AVPlayerItemNewErrorLogEntryNotification
  // is the only signal that carries a per-resource URI, so it is the only one
  // we can scope to the configured sidecar URLs rather than guessing.
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(sidecarItemErrorNotification:)
                                               name:AVPlayerItemNewErrorLogEntryNotification
                                             object:item];
}

- (void)removeItemObservers
{
  AVPlayerItem *item = _observedItem;
  if (item != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemNewErrorLogEntryNotification
                                                  object:item];
  }
  _observedItem = nil;
}

- (void)sidecarItemErrorNotification:(NSNotification *)notification
{
  AVPlayerItem *item = notification.object;
  if (item != _observedItem || !_trackAdded || _sidecarFailureEmitted) {
    return;
  }
  AVPlayerItemErrorLogEvent *lastEvent = item.errorLog.events.lastObject;
  if (lastEvent == nil) {
    return;
  }
  // Only attribute the log entry to a sidecar track if its URI resolves to
  // the same host as one we configured: the primary asset's own segments/manifest
  // requests land on this same notification and must not be reported as a
  // sidecar failure.
  NSURLComponents *entryComponents = lastEvent.URI != nil
      ? [NSURLComponents componentsWithString:lastEvent.URI]
      : nil;
  BOOL matchesSidecarHost = NO;
  for (NSDictionary<NSString *, NSString *> *track in _validTracks) {
    NSURLComponents *sidecarComponents = [NSURLComponents componentsWithString:track[@"url"]];
    if (entryComponents != nil && sidecarComponents.host != nil &&
        [entryComponents.host caseInsensitiveCompare:sidecarComponents.host] == NSOrderedSame) {
      matchesSidecarHost = YES;
      break;
    }
  }
  if (!matchesSidecarHost) {
    return;
  }
  _sidecarFailureEmitted = YES;
  NSString *nativeCode = [NSString stringWithFormat:@"%@:%ld",
      lastEvent.errorDomain, (long)lastEvent.errorStatusCode];
  [self emitStatus:@"failed"
          language:_validTracks.firstObject[@"language"] ?: @""
             label:_validTracks.firstObject[@"label"] ?: @""
             error:@"load"
        nativeCode:nativeCode];
}

- (void)emitStatus:(NSString *)status
           language:(NSString *)language
              label:(NSString *)label
              error:(NSString *)error
         nativeCode:(NSString *)nativeCode

{
  id<BrightcovePlayerFeatureHost> host = _host;
  if (host == nil || host.isInvalidated) {
    return;
  }
  auto eventEmitter = [host typedEventEmitter];
  if (!eventEmitter) {
    return;
  }
  eventEmitter->onSidecarTrackStatus(BrightcovePlayerViewEventEmitter::OnSidecarTrackStatus{
    .status = BCOVSidecarStdStringFromNSString(status),
    .language = BCOVSidecarStdStringFromNSString(language),
    .label = BCOVSidecarStdStringFromNSString(label),
    .error = BCOVSidecarStdStringFromNSString(error),
    .nativeCode = BCOVSidecarStdStringFromNSString(nativeCode),
  });
}

@end
