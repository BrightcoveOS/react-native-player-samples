/**
 * Player configuration for the playlists sample.
 *
 * Replace this public Brightcove demo account/queue with the customer's own
 * account and videos before distributing an app. Policy keys are client-side
 * playback keys and are expected in an app; never place server-side credentials
 * or signing keys here.
 */
export const PLAYER_CONFIG = {
  accountId: '5434391461001',
  policyKey:
    'BCpkADawqM0T8lW3nMChuAbrcunBBHmh4YkNl5e6ZrKQwPiK_Y83RAOF4DP5tyBF_ONBVgrEjqW6fbV0nKRuHvjRU3E8jdT9WMTOXfJODoPML6NUDCYTwTHxtNlr5YdyGYaCPLhMUZ3Xu61L',
  queue: [
    { videoId: '5702148954001', title: 'Introduction' },
    { videoId: '5702143016001', title: 'Documentation' },
    { videoId: '5702149062001', title: 'Android tools' },
  ],
} as const;

if (__DEV__) {
  const values = [
    PLAYER_CONFIG.accountId,
    PLAYER_CONFIG.policyKey,
    ...PLAYER_CONFIG.queue.map(item => item.videoId),
  ];
  if (values.some(value => value.length === 0 || value.startsWith('YOUR_'))) {
    throw new Error(
      'Replace the placeholder values in src/playerConfig.ts with your Brightcove account and queue.',
    );
  }
}
