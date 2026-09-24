/**
 * Player configuration for the playback-state sample.
 *
 * Replace the public Brightcove demo tuple below with the customer's own
 * account and policy key before distribution. A policy key is a client-side
 * playback key, not a private API credential; never put server-side secrets
 * (CRM/API tokens, signing keys, licence server secrets) in this file.
 *
 * The sample ships two selectable sources:
 *
 * - `On-demand` points at a public VOD asset, which exercises the playback
 *   lifecycle, progress, and the on-demand path.
 * - `Live / DVR` is a placeholder slot. Live-DVR content is account-specific
 *   and cannot be a permanent public fixture, so replace
 *   `YOUR_LIVE_DVR_VIDEO_ID` with a live-DVR asset id from an account that
 *   owns one. Until then the sample shows a configuration note instead of
 *   loading it.
 */
export const PLAYER_CONFIG = {
  accountId: '5420904993001',
  policyKey:
    'BCpkADawqM3DwCTPGyMMiG0loem8lXox3utO1lFEP1i-_l1MpjRSVXMTSsa2ToslC129_W6YzwJpXbpbIVRFwf35qYM0pxo2HJK-_SotgmgrkmJTQ-024GkXIelVSY8LOHZzRBtcBU57M6Is',
} as const;

export interface DemoSource {
  /** Stable key for the switch control. */
  key: 'vod' | 'live';
  /** Label shown on the switch control. */
  label: string;
  /** Video Cloud video id, or a YOUR_ placeholder until configured. */
  videoId: string;
}

export const DEMO_SOURCES: readonly DemoSource[] = [
  { key: 'vod', label: 'On-demand', videoId: '5421538222001' },
  { key: 'live', label: 'Live / DVR', videoId: 'YOUR_LIVE_DVR_VIDEO_ID' },
] as const;

export function isConfigured(videoId: string): boolean {
  return videoId.length > 0 && !videoId.startsWith('YOUR_');
}

if (__DEV__) {
  const accountValues = Object.values(PLAYER_CONFIG);
  if (accountValues.some(value => value.length === 0 || value.startsWith('YOUR_'))) {
    throw new Error(
      'Replace the placeholder values in src/playerConfig.ts with your Brightcove account before running this sample.',
    );
  }
  // The on-demand source must always be usable; a live placeholder is allowed
  // and handled in the UI with a configuration note.
  const vod = DEMO_SOURCES.find(source => source.key === 'vod');
  if (!vod || !isConfigured(vod.videoId)) {
    throw new Error(
      'src/playerConfig.ts must define a concrete on-demand videoId.',
    );
  }
}
