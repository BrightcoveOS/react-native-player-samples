/**
 * Player configuration for the DRM sample.
 *
 * Replace this public Brightcove DRM demo tuple with the customer's protected
 * video before distribution. Dynamic Delivery supplies Widevine/FairPlay key
 * system data through the Playback API; do not add license-server credentials,
 * private certificates, signing keys, or other server-side secrets here.
 */
export const PLAYER_CONFIG = {
  accountId: '6415855237001',
  policyKey:
    'BCpkADawqM3dtPuWvSDSrMwpq0TWhZ0pnpPuEEWNrfyb2L0wNPs_333JY8J5IE8vMNhgF92EBV0GL_5HTyeWxndxw1qO0L0ksdJPE33LLESUiRwf65CR6P8gzmeIxrK7NrTn2gPUv2ZkeYiXEG-3-yvjMkLbFmiO8y3-Wg',
  videoId: '6393164822112',
} as const;

if (__DEV__) {
  const values = Object.values(PLAYER_CONFIG);
  if (values.some(value => value.length === 0 || value.startsWith('YOUR_'))) {
    throw new Error(
      'Replace the placeholder values in src/playerConfig.ts with a DRM-enabled Brightcove account and video.',
    );
  }
}
