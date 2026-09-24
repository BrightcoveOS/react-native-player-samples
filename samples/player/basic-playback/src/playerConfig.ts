/**
 * Player configuration for this sample.
 *
 * Replace the values below with the customer's own Brightcove account. The
 * values shipped here are Brightcove's public demo assets so the sample runs
 * out of the box; they are not secrets, but a shipping app must use its own
 * account, policy key, and video.
 *
 * A policy key is a client-side playback key, not a private API credential —
 * it is expected to ship inside the app. Never put server-side credentials
 * (CRM/API tokens, signing keys, license server secrets) in this file.
 */

export const PLAYER_CONFIG = {
  accountId: '6415855237001',
  policyKey:
    'BCpkADawqM3dtPuWvSDSrMwpq0TWhZ0pnpPuEEWNrfyb2L0wNPs_333JY8J5IE8vMNhgF92EBV0GL_5HTyeWxndxw1qO0L0ksdJPE33LLESUiRwf65CR6P8gzmeIxrK7NrTn2gPUv2ZkeYiXEG-3-yvjMkLbFmiO8y3-Wg',
  videoId: '6393164822112',
} as const;

// Fail fast during development if placeholder text is left in place, rather
// than sending a garbage account to the Playback API at runtime.
if (__DEV__) {
  const values = Object.values(PLAYER_CONFIG);
  if (values.some(value => value.length === 0 || value.startsWith('YOUR_'))) {
    throw new Error(
      'Replace the placeholder values in src/playerConfig.ts with your Brightcove account before running this sample.',
    );
  }
}
