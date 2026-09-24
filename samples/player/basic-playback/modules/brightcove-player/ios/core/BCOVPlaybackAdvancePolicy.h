#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Whether the playback controller may auto-advance to the next queued item at
 * end-of-item.
 *
 * The `loop` prop is documented as single-video repeat, not playlist
 * repeat-all. While it is on, the core itself restarts the finished item, so
 * leaving the SDK's autoAdvance enabled would race that restart onto the next
 * queued item. Queue repetition is a separate concern owned by the playlists
 * feature's repeatMode. Kept pure so the rule is unit-testable.
 */
BOOL BCOVShouldAutoAdvance(BOOL loop);

NS_ASSUME_NONNULL_END
