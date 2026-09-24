/**
 * Player configuration for the SSAI sample.
 *
 * Replace this public Brightcove demo tuple with the customer's SSAI-enabled
 * account, video, and ad configuration before distribution. The adConfigId is
 * required: it tells Video Cloud which VMAP to generate. Never put ad-server
 * credentials, signing keys, or other server-side secrets in this file.
 */
export const PLAYER_CONFIG = {
  accountId: '5434391461001',
  policyKey:
    'BCpkADawqM0T8lW3nMChuAbrcunBBHmh4YkNl5e6ZrKQwPiK_Y83RAOF4DP5tyBF_ONBVgrEjqW6fbV0nKRuHvjRU3E8jdT9WMTOXfJODoPML6NUDCYTwTHxtNlr5YdyGYaCPLhMUZ3Xu61L',
  videoId: '5702141808001',
  adConfigId: '0e0bbcd1-bba0-45bf-a986-1288e5f9fc85',
} as const;

if (__DEV__) {
  const values = Object.values(PLAYER_CONFIG);
  if (values.some(value => value.length === 0 || value.startsWith('YOUR_'))) {
    throw new Error(
      'Replace the placeholder values in src/playerConfig.ts with an SSAI-enabled Brightcove account, video, and ad config.',
    );
  }
}
