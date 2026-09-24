/**
 * Player configuration for the ads (CSAI / Google IMA) sample.
 *
 * Replace this public Brightcove demo tuple with the customer's own account,
 * policy key, and video before distribution. The ad tag is a separate concern:
 * see AD_TAG below. Never put ad-server credentials, signing keys, or other
 * server-side secrets in this file.
 */
export const PLAYER_CONFIG = {
  accountId: '5420904993001',
  policyKey:
    'BCpkADawqM3DwCTPGyMMiG0loem8lXox3utO1lFEP1i-_l1MpjRSVXMTSsa2ToslC129_W6YzwJpXbpbIVRFwf35qYM0pxo2HJK-_SotgmgrkmJTQ-024GkXIelVSY8LOHZzRBtcBU57M6Is',
  videoId: '5421538222001',
} as const;

/**
 * Google's public VMAP ("ad rules") sample tag: a pre-roll, a mid-roll, and a
 * post-roll. The VMAP response defines the whole schedule, so the app supplies
 * only this one URL — it never places ad cue points itself. Replace it with the
 * customer's own VMAP ad tag before shipping.
 */
export const AD_TAG =
  'https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&iu=/124319096/external/ad_rule_samples&ciu_szs=300x250&ad_rule=1&impl=s&gdfp_req=1&env=vp&output=vmap&unviewed_position_start=1&cust_params=deployment%3Ddevsite%26sample_ar%3Dpremidpost&cmsid=496&vid=short_onecue&correlator=';

if (__DEV__) {
  const values = [...Object.values(PLAYER_CONFIG), AD_TAG];
  if (values.some(value => value.length === 0 || value.startsWith('YOUR_'))) {
    throw new Error(
      'Replace the placeholder values in src/playerConfig.ts with your Brightcove account, video, and VMAP ad tag before running this sample.',
    );
  }
}
