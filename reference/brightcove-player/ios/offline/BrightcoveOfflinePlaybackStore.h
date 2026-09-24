#import <BrightcovePlayerSDK/BrightcovePlayerSDK.h>
#import <BrightcovePlayerSDK/BrightcovePlayerSDK-Swift.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol BrightcoveOfflinePlaybackStoreObserver <NSObject>

- (void)offlinePlaybackStoreDidChangeToken:(BCOVOfflineVideoToken)token;
- (void)offlinePlaybackStoreDidRemoveToken:(BCOVOfflineVideoToken)token;

@end

/**
 * The app-scoped owner of BCOVOfflineVideoManager. Brightcove requires this
 * manager to be initialized once per launch with one delegate; views and the
 * React Native module therefore share this coordinator instead of attempting
 * to model durable downloads as per-view state.
 */
@interface BrightcoveOfflinePlaybackStore : NSObject <BCOVOfflineVideoManagerDelegate>

@property (nonatomic, readonly, nullable) BCOVOfflineVideoManager *manager;
@property (nonatomic, readonly) id<BCOVFPSAuthorizationProxy> authProxy;

+ (instancetype)sharedStore;

- (void)addObserver:(id<BrightcoveOfflinePlaybackStoreObserver>)observer;
- (void)removeObserver:(id<BrightcoveOfflinePlaybackStoreObserver>)observer;

- (BOOL)acquireToken:(BCOVOfflineVideoToken)token;
- (void)deactivateToken:(BCOVOfflineVideoToken)token;
- (BOOL)isTokenActive:(BCOVOfflineVideoToken)token;
- (BOOL)beginRemovalForToken:(BCOVOfflineVideoToken)token;
- (void)finishRemovalForToken:(BCOVOfflineVideoToken)token;
- (BOOL)confirmRemovalForToken:(BCOVOfflineVideoToken)token;

/**
 * Terminate a removal that stopped waiting (the module's deletion timeout):
 * the token is forgotten entirely so the manager's next storage-change
 * notification cannot re-discover it as newly removed and emit a late
 * success after the promise already rejected.
 */
- (void)abandonRemovalForToken:(BCOVOfflineVideoToken)token;

@end

NS_ASSUME_NONNULL_END
