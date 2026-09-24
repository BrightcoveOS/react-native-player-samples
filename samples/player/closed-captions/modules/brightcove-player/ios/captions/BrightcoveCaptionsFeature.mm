#import "BrightcoveCaptionsFeature.h"

#import <AVFoundation/AVFoundation.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>

using namespace facebook::react;

static std::string BCOVCaptionsStdStringFromNSString(NSString *value)
{
  const char *utf8 = value.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

@implementation BrightcoveCaptionsFeature {
  __weak id<BrightcovePlayerFeatureHost> _host;

  BOOL _captionsEnabled;
  // The id of the track the customer asked for (index into _options as a
  // string), or empty for "no specific track".
  NSString *_captionTrackId;

  __weak id<BCOVPlaybackSession> _captionSession;
  // The filtered, ordered legible options for the current source: playable and
  // not forced-only, i.e. exactly the tracks suitable to offer in a UI (per the
  // legibleMediaSelectionGroup SDK docs). A track's id is its index within this
  // list, namespaced by the source generation, so this list is the single
  // source of truth for discovery, identity, and selection. Rebuilt on every
  // source.
  NSArray<AVMediaSelectionOption *> *_options;
  // The id currently reported active (empty = off). Only ever set from the
  // native selection callback, so JS reflects the SDK's real state.
  NSString *_activeTrackId;
  // Incremented on every source reset. A track id embeds this generation
  // ("<gen>:<index>") so an id minted for a previous source cannot be
  // reinterpreted in a new source's option list — a stale captionTrackId prop
  // that survives the source change resolves to nil (captions stay off) instead
  // of silently selecting whatever track now sits at that index.
  NSUInteger _sourceGeneration;
  BOOL _captionsAvailablePending;
  BOOL _captionTrackChangedPending;
}

- (instancetype)init
{
  if (self = [super init]) {
    _captionTrackId = @"";
    _activeTrackId = @"";
    _options = @[];
  }
  return self;
}

- (NSSet<NSString *> *)ownedProps
{
  return [NSSet setWithObjects:@"captionsEnabled", @"captionTrackId", nil];
}

- (void)attachToHost:(id<BrightcovePlayerFeatureHost>)host
{
  _host = host;
}

// captionsEnabled and captionTrackId are applied together as one selection.
// The core forwards both changed props within a single Fabric update before
// finalizeUpdates, so we stash the values and apply once — never two competing
// selections (see -applyCaptionSelection, invoked from the core after props).
- (void)setProp:(NSString *)name value:(id)value
{
  if ([name isEqualToString:@"captionsEnabled"]) {
    _captionsEnabled = [value boolValue];
    return;
  }
  if ([name isEqualToString:@"captionTrackId"]) {
    _captionTrackId = [(value ?: @"") copy];
    return;
  }
  [NSException raise:NSInvalidArgumentException
              format:@"BrightcoveCaptionsFeature does not own prop '%@'", name];
}

- (void)onSourceReset
{
  _captionSession = nil;
  _options = @[];
  // New source namespace: ids minted for the previous source are now invalid.
  _sourceGeneration += 1;
  // Drop the pending request itself, not just relying on optionForId's
  // generation-prefix check to reject it later: a customer that changes
  // videoId without also changing captionTrackId in the same render (the
  // realistic case — the caption selection didn't change, only the source
  // did) leaves _captionTrackId holding the previous source's id in this ivar
  // until JS reacts to the authoritative reset below and re-renders. Clearing
  // it here means onSessionReady's applyCaptionSelection (which can run before
  // that JS round-trip completes) has nothing stale to even attempt to
  // resolve — captions correctly start from "no specific track" for the new
  // source rather than depending solely on the generation string mismatch.
  _captionTrackId = @"";
  // Emit an authoritative reset BEFORE any new selection: the previous source's
  // tracks no longer exist, so tell JS the list is empty and nothing is active.
  // Without this, a surviving controlled captionTrackId prop would leave JS
  // believing a track is selected across the source change.
  [self emitCaptionsAvailable];
  [self setActiveTrackId:@""];
}

// captionsEnabled + captionTrackId form one selection; apply the coalesced
// result once per transaction here (the core calls this after all prop setters),
// never per-prop, so there are no competing selections.
- (void)onPropsCommitted
{
  [self applyCaptionSelection];
}

- (void)onSessionReady:(id<BCOVPlaybackSession>)session
{
  _captionSession = session;
  [self rebuildOptions];
  [self emitCaptionsAvailable];
  [self applyCaptionSelection];
}

- (void)onEventEmitterReady
{
  if (_captionsAvailablePending) {
    _captionsAvailablePending = NO;
    [self emitCaptionsAvailable];
  }
  if (_captionTrackChangedPending) {
    _captionTrackChangedPending = NO;
    [self emitCaptionTrackChanged:_activeTrackId];
  }
}

// The legible selection changed — from our own selection, the player's native
// caption menu, or an AirPlay/route restoration. This is the authoritative
// signal, so onCaptionTrackChanged is emitted only here (never optimistically),
// keeping JS in sync with the SDK's real selection regardless of who changed it.
- (void)onSelectedLegibleMediaOption:(AVMediaSelectionOption *)option
{
  if (_host.isInvalidated) {
    return;
  }
  [self setActiveTrackId:option ? [self idForOption:option] : @""];
}

#pragma mark Track list (filtered, ordered — the identity source of truth)

- (void)rebuildOptions
{
  AVMediaSelectionGroup *group = [self legibleGroup];
  if (group == nil) {
    _options = @[];
    return;
  }
  // The group is unsorted and may contain unplayable and forced-only options;
  // the SDK docs say to filter with playableMediaSelectionOptionsFromArray: and
  // to exclude forced-only subtitles before presenting choices. Build that one
  // filtered list and use it everywhere.
  NSArray<AVMediaSelectionOption *> *playable =
      [AVMediaSelectionGroup playableMediaSelectionOptionsFromArray:group.options];
  NSMutableArray<AVMediaSelectionOption *> *filtered = [NSMutableArray array];
  for (AVMediaSelectionOption *option in playable) {
    if (![option hasMediaCharacteristic:AVMediaCharacteristicContainsOnlyForcedSubtitles]) {
      [filtered addObject:option];
    }
  }
  _options = [filtered copy];
}

- (AVMediaSelectionGroup *)legibleGroup
{
  // Prefer the SDK's session accessor (documented entry point) over reaching
  // into the AVAsset directly.
  return _captionSession.legibleMediaSelectionGroup;
}

// A track's stable per-source id is its index in the filtered list, namespaced
// by the source generation ("<gen>:<index>"). Distinct options — including
// same-language variants — therefore get distinct ids, and an id is only valid
// within the source that minted it.
- (NSString *)idForOption:(AVMediaSelectionOption *)option
{
  NSUInteger index = [_options indexOfObject:option];
  if (index == NSNotFound) {
    return @"";
  }
  return [NSString stringWithFormat:@"%lu:%lu",
          (unsigned long)_sourceGeneration, (unsigned long)index];
}

- (AVMediaSelectionOption *)optionForId:(NSString *)trackId
{
  // Ids are "<gen>:<index>". Reject anything that is not that exact shape, or
  // whose generation is not the current source's — an id from a previous source
  // must not resolve into this source's option list.
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
  // Guard against non-numeric index mapping to 0.
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

#pragma mark Selection

- (void)applyCaptionSelection
{
  if (_host.isInvalidated || _captionSession == nil) {
    return;
  }

  // Selection goes through BCOVPlaybackSession's own legible-selection API —
  // the same path Brightcove's ClosedCaptionMenuController uses: assigning
  // selectedLegibleMediaOption (an option, or nil for Off) is how the SDK
  // performs a Manual/Off selection, and it posts the SDK's selection
  // notification. Note SDK 7.2.16 exposes no public setter for
  // legibleMediaSelectionMode: the native menu tracks Manual/Off/Automatic in
  // that separate mode, which this option setter does not write, and only
  // Manual/Automatic selections are re-applied across an AirPlay route change.
  // The native-menu checkmark and AirPlay-restoration behavior therefore need
  // on-device verification (the simulator cannot AirPlay); they are not
  // asserted by the automated tests.

  // Off: deselect through the session setter (not the AVPlayerItem directly).
  // The delegate callback is not guaranteed to fire for a deselection, so emit
  // the off state directly here (it is a deterministic action we initiated).
  if (!_captionsEnabled) {
    _captionSession.selectedLegibleMediaOption = nil;
    [self setActiveTrackId:@""];
    return;
  }

  // Resolve the option:
  //  - a specific captionTrackId is honored only if it exists on this source;
  //    an unknown id leaves captions off rather than substituting another track.
  //  - with captions enabled and no specific id, use the first filtered option.
  //
  // The first-track default is a deliberate Manual selection, not
  // selectLegibleMediaOptionAutomatically: Automatic resolves against the
  // system's language/accessibility preferences (so it can pick a different
  // track, or none), whereas the cross-platform contract promises a
  // deterministic "first available track" that matches Android's behavior.
  AVMediaSelectionOption *chosen;
  if (_captionTrackId.length > 0) {
    chosen = [self optionForId:_captionTrackId];
    if (chosen == nil) {
      // The requested id is not on this source: leave captions off rather than
      // substitute another track. Deselection's delegate callback is not
      // guaranteed to fire, so emit the off state directly — otherwise JS would
      // keep showing the requested track as active while captions are actually
      // off (this mirrors both the !_captionsEnabled branch above and Android,
      // which resolves an unknown id to off and emits it).
      _captionSession.selectedLegibleMediaOption = nil;
      [self setActiveTrackId:@""];
      return;
    }
  } else {
    chosen = _options.firstObject;
  }
  if (chosen == nil) {
    // Captions enabled but the source has no usable tracks: nothing to select.
    // Report off so JS does not show a stale active track.
    [self setActiveTrackId:@""];
    return;
  }

  // Set through the session; onCaptionTrackChanged is emitted from the
  // resulting native callback, not here, so we never report a selection the
  // SDK did not actually make.
  _captionSession.selectedLegibleMediaOption = chosen;
}

- (void)setActiveTrackId:(NSString *)trackId
{
  if ([_activeTrackId isEqualToString:trackId]) {
    return;
  }
  _activeTrackId = [trackId copy];
  [self emitCaptionTrackChanged:trackId];
}

#pragma mark Emit

// The emit methods below guard only on the emitter being non-nil. Their callers
// (onSourceReset / onSessionReady / onSelectedLegibleMediaOption /
// applyCaptionSelection) already bail when the host is invalidated, so a late
// emit onto a torn-down view cannot originate here. Preserve that invariant if
// adding a new caller: guard isInvalidated at the entry point.
- (void)emitCaptionsAvailable
{
  // A plain loop (not enumerateObjectsUsingBlock:) so the std::vector can be
  // mutated — an ObjC block would capture it by const copy.
  std::vector<BrightcovePlayerViewEventEmitter::OnCaptionsAvailableTracks> tracks;
  for (NSUInteger index = 0; index < _options.count; index++) {
    AVMediaSelectionOption *option = _options[index];
    NSString *label = [_captionSession displayNameFromLegibleMediaSelectionOption:option]
        ?: (option.displayName ?: @"");
    tracks.push_back({
      .id = BCOVCaptionsStdStringFromNSString([self idForOption:option]),
      .language = BCOVCaptionsStdStringFromNSString([self languageForOption:option]),
      .label = BCOVCaptionsStdStringFromNSString(label),
    });
  }

  auto eventEmitter = [_host typedEventEmitter];
  if (eventEmitter) {
    _captionsAvailablePending = NO;
    eventEmitter->onCaptionsAvailable(BrightcovePlayerViewEventEmitter::OnCaptionsAvailable{
      .tracks = tracks,
    });
  } else {
    _captionsAvailablePending = YES;
  }
}

- (void)emitCaptionTrackChanged:(NSString *)trackId
{
  auto eventEmitter = [_host typedEventEmitter];
  if (!eventEmitter) {
    _captionTrackChangedPending = YES;
    return;
  }
  _captionTrackChangedPending = NO;
  // language is metadata mirrored from the active track (empty when off).
  NSString *language = @"";
  AVMediaSelectionOption *option = [self optionForId:trackId];
  if (option != nil) {
    language = [self languageForOption:option];
  }
  eventEmitter->onCaptionTrackChanged(BrightcovePlayerViewEventEmitter::OnCaptionTrackChanged{
    .id = BCOVCaptionsStdStringFromNSString(trackId),
    .language = BCOVCaptionsStdStringFromNSString(language),
  });
}

@end
