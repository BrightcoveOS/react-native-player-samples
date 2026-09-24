#import "BrightcoveOfflinePlaybackStore.h"

#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>

@implementation BrightcoveOfflinePlaybackStore {
  BCOVOfflineVideoManager *_manager;
  BCOVFPSBrightcoveAuthProxy *_authProxy;
  NSHashTable<id<BrightcoveOfflinePlaybackStoreObserver>> *_observers;
  NSMutableDictionary<BCOVOfflineVideoToken, NSNumber *> *_activeTokenOwnerCounts;
  NSMutableSet<BCOVOfflineVideoToken> *_knownTokens;
  NSMutableSet<BCOVOfflineVideoToken> *_removingTokens;
}

+ (instancetype)sharedStore
{
  static BrightcoveOfflinePlaybackStore *store;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    store = [BrightcoveOfflinePlaybackStore new];
  });
  return store;
}

- (instancetype)init
{
  if (self = [super init]) {
    _observers = [NSHashTable weakObjectsHashTable];
    _activeTokenOwnerCounts = [NSMutableDictionary dictionary];
    _removingTokens = [NSMutableSet set];
    _authProxy = [[BCOVFPSBrightcoveAuthProxy alloc] initWithPublisherId:nil applicationId:nil];
    [BCOVOfflineVideoManager initializeOfflineVideoManagerWithDelegate:self options:nil];
    _manager = [BCOVOfflineVideoManager sharedManager];
    _manager.authProxy = _authProxy;
    _knownTokens = [NSMutableSet setWithArray:_manager.offlineVideoTokens];
  }
  return self;
}

- (BCOVOfflineVideoManager *)manager
{
  return _manager;
}

- (id<BCOVFPSAuthorizationProxy>)authProxy
{
  return _authProxy;
}

- (void)addObserver:(id<BrightcoveOfflinePlaybackStoreObserver>)observer
{
  [_observers addObject:observer];
}

- (void)removeObserver:(id<BrightcoveOfflinePlaybackStoreObserver>)observer
{
  [_observers removeObject:observer];
}

- (BOOL)acquireToken:(BCOVOfflineVideoToken)token
{
  if ([_removingTokens containsObject:token]) {
    return NO;
  }
  NSInteger owners = _activeTokenOwnerCounts[token].integerValue;
  _activeTokenOwnerCounts[token] = @(owners + 1);
  return YES;
}

- (void)deactivateToken:(BCOVOfflineVideoToken)token
{
  NSInteger owners = _activeTokenOwnerCounts[token].integerValue - 1;
  if (owners <= 0) {
    [_activeTokenOwnerCounts removeObjectForKey:token];
  } else {
    _activeTokenOwnerCounts[token] = @(owners);
  }
}

- (BOOL)isTokenActive:(BCOVOfflineVideoToken)token
{
  return _activeTokenOwnerCounts[token].integerValue > 0;
}

- (BOOL)beginRemovalForToken:(BCOVOfflineVideoToken)token
{
  if ([self isTokenActive:token] || [_removingTokens containsObject:token]) {
    return NO;
  }
  [_removingTokens addObject:token];
  return YES;
}

- (void)finishRemovalForToken:(BCOVOfflineVideoToken)token
{
  [_removingTokens removeObject:token];
}

- (BOOL)confirmRemovalForToken:(BCOVOfflineVideoToken)token
{
  if (![_removingTokens containsObject:token] && ![_knownTokens containsObject:token]) {
    return NO;
  }
  [self finishRemovalForToken:token];
  [_knownTokens removeObject:token];
  return YES;
}

// A removal that gave up waiting (the module's timeout) is terminally handled:
// forget the token entirely so the manager's next storage-change notification
// does not re-discover it as "removed" and emit a late success after the
// promise already rejected. The removal is not retried — a later
// removeDownload for the same token starts a fresh cycle.
- (void)abandonRemovalForToken:(BCOVOfflineVideoToken)token
{
  [self finishRemovalForToken:token];
  [_knownTokens removeObject:token];
}

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
    aggregateDownloadTask:(AVAggregateAssetDownloadTask *)aggregateDownloadTask
            didProgressTo:(NSTimeInterval)progressPercent
        forMediaSelection:(AVMediaSelection *)mediaSelection
{
  [self notifyToken:offlineVideoToken];
}

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
        assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask
            didProgressTo:(NSTimeInterval)progressPercent
{
  [self notifyToken:offlineVideoToken];
}

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
    didFinishDownloadWithError:(NSError *)error
{
  [self notifyToken:offlineVideoToken];
}

- (void)downloadWasPausedForOfflineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
{
  [self notifyToken:offlineVideoToken];
}

- (void)offlineVideoStorageDidChange
{
  NSSet<BCOVOfflineVideoToken> *currentTokens = [NSSet setWithArray:_manager.offlineVideoTokens];
  NSMutableSet<BCOVOfflineVideoToken> *removedTokens = [_knownTokens mutableCopy];
  [removedTokens minusSet:currentTokens];
  for (BCOVOfflineVideoToken token in removedTokens) {
    if ([self confirmRemovalForToken:token]) {
      [self notifyRemovedToken:token];
    }
  }
  _knownTokens = [currentTokens mutableCopy];
  for (BCOVOfflineVideoToken token in currentTokens) {
    [self notifyToken:token];
  }
}

- (void)notifyToken:(BCOVOfflineVideoToken)token
{
  [_knownTokens addObject:token];
  void (^notify)(void) = ^{
    for (id<BrightcoveOfflinePlaybackStoreObserver> observer in self->_observers) {
      [observer offlinePlaybackStoreDidChangeToken:token];
    }
  };
  if (NSThread.isMainThread) {
    notify();
  } else {
    dispatch_async(dispatch_get_main_queue(), notify);
  }
}

- (void)notifyRemovedToken:(BCOVOfflineVideoToken)token
{
  void (^notify)(void) = ^{
    for (id<BrightcoveOfflinePlaybackStoreObserver> observer in self->_observers) {
      [observer offlinePlaybackStoreDidRemoveToken:token];
    }
  };
  if (NSThread.isMainThread) {
    notify();
  } else {
    dispatch_async(dispatch_get_main_queue(), notify);
  }
}

@end
