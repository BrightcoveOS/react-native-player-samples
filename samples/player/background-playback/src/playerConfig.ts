/**
 * Player configuration for the background-playback sample.
 *
 * Replace this public Brightcove demo tuple with the customer's own account,
 * policy key, and video before distribution. A policy key is a client-side
 * playback key, not a private API credential; never put server-side secrets
 * (CRM/API tokens, signing keys, licence server secrets) in this file.
 */
export const PLAYER_CONFIG = {
  accountId: '5420904993001',
  policyKey:
    'BCpkADawqM3DwCTPGyMMiG0loem8lXox3utO1lFEP1i-_l1MpjRSVXMTSsa2ToslC129_W6YzwJpXbpbIVRFwf35qYM0pxo2HJK-_SotgmgrkmJTQ-024GkXIelVSY8LOHZzRBtcBU57M6Is',
  videoId: '5421538222001',
} as const;

if (__DEV__) {
  const values = Object.values(PLAYER_CONFIG);
  if (values.some(value => value.length === 0 || value.startsWith('YOUR_'))) {
    throw new Error(
      'Replace the placeholder values in src/playerConfig.ts with your Brightcove account and video before running this sample.',
    );
  }
}
