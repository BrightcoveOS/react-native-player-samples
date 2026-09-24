/**
 * @jest-environment jsdom
 */

import { describe, it, expect, jest, beforeEach } from '@jest/globals';
import React, { createRef } from 'react';
import { render, act } from '@testing-library/react';

jest.mock('react-native', () => {
  const ReactModule = require('react');
  const View = ReactModule.forwardRef(
    ({ children, testID, style, ...props }: any, ref: any) =>
      ReactModule.createElement(
        'div',
        { ref, 'data-testid': testID, style, ...props },
        children,
      ),
  );
  return {
    View,
    StyleSheet: {
      create: (styles: any) => styles,
    },
    TurboModuleRegistry: {
      getEnforcing: jest.fn(() => ({
        requestDownload: jest.fn(),
        listDownloads: jest.fn(async () => []),
        pauseDownload: jest.fn(),
        resumeDownload: jest.fn(),
        cancelDownload: jest.fn(),
        removeDownload: jest.fn(),
        onOfflineDownloadChanged: jest.fn(() => ({ remove: jest.fn() })),
      })),
      get: jest.fn(() => null),
    },
  };
});

import { BrightcovePlayerView } from '../../modules/brightcove-player/src/BrightcovePlayerView.web';
import { PlayerCommands } from '../../modules/brightcove-player/src/index.web';
import {
  classifyImaClientSideAdError,
  classifyWebAdError,
  classifyWebPlayerError,
  isAdClassWebPlayerError,
  validateSeekPosition,
  validateVolume,
  validatePlaybackRate,
} from '../../modules/brightcove-player/src/webErrorClassification';
import type {
  WebSdkPlayerInstance,
  WebSdkQualityLevel,
  WebSdkAudioTrack,
  WebSdkTextTrack,
  WebSdkTextTrackOptions,
  BrightcovePlayerWebHandle,
} from '../../modules/brightcove-player/src/BrightcovePlayerView.web';

class FakeWebSdkPlayer implements WebSdkPlayerInstance {
  accountId: string;
  config: Record<string, unknown> = {};
  attachedRoot: HTMLDivElement | null = null;
  videoElement = document.createElement('video');
  disposed = false;
  detached = false;
  playCalled = 0;
  pauseCalled = 0;
  seekPositions: number[] = [];
  volumeLevels: number[] = [];
  mutedStates: boolean[] = [];
  playbackRates: number[] = [];
  loadedModels: unknown[] = [];
  eventListeners: Map<string, Set<(eventData?: unknown) => void>> = new Map();
  playbackApiRequests: Array<{
    payload: { videoId: string };
    abortCalled: boolean;
    resolve: (value: unknown) => void;
    reject: (reason: unknown) => void;
  }> = [];

  playPromiseShouldReject = false;
  playRejectionError: Error = new Error('NotAllowedError: play failed');
  loadModelShouldThrow = false;
  loadModelError: Error = new Error('Failed to load video model');
  qualityLevels: WebSdkQualityLevel[] = [];
  audioTracks: WebSdkAudioTrack[] = [];
  textTracks: WebSdkTextTrack[] = [];
  controlBar = {
    show: jest.fn(() => {
      this.controlBarShown = true;
    }),
    hide: jest.fn(() => {
      this.controlBarShown = false;
    }),
  };
  controlBarShown = true;
  ad: {
    getAdId: () => string;
    getTitle: () => string;
    getDuration: () => number;
    isLinear: () => boolean;
    getAdvertiserName: () => string;
    getWidth: () => number;
    getHeight: () => number;
    getSkipTimeOffset: () => number;
  } | null = null;

  constructor(options: { accountId: string }) {
    this.accountId = options.accountId;
  }

  updateConfiguration(chunk: Record<string, unknown>) {
    this.config = { ...this.config, ...chunk };
    return this.config;
  }

  attach(root: HTMLDivElement) {
    this.attachedRoot = root;
  }

  getVideoElement() {
    return this.videoElement;
  }

  detach() {
    this.detached = true;
    this.attachedRoot = null;
  }

  dispose() {
    this.disposed = true;
    this.eventListeners.clear();
  }

  getVideoByIdFromPlaybackApi(payload: { videoId: string }) {
    let resolveFn!: (value: unknown) => void;
    let rejectFn!: (reason: unknown) => void;
    const promise = new Promise<unknown>((res, rej) => {
      resolveFn = res;
      rejectFn = rej;
    });

    const reqRecord = {
      payload,
      abortCalled: false,
      resolve: resolveFn,
      reject: rejectFn,
    };
    this.playbackApiRequests.push(reqRecord);

    return {
      abort: () => {
        reqRecord.abortCalled = true;
      },
      promise,
    };
  }

  loadBrightcoveVideoModel(model: unknown) {
    if (this.loadModelShouldThrow) {
      throw this.loadModelError;
    }
    this.loadedModels.push(model);
  }

  play() {
    this.playCalled++;
    if (this.playPromiseShouldReject) {
      return Promise.reject(this.playRejectionError);
    }
    return Promise.resolve();
  }

  pause() {
    this.pauseCalled++;
  }

  seek(seconds: number) {
    this.seekPositions.push(seconds);
  }

  setVolumeLevel(level: number) {
    this.volumeLevels.push(level);
  }

  mute() {
    this.mutedStates.push(true);
  }

  unmute() {
    this.mutedStates.push(false);
  }

  setPlaybackRate(rate: number) {
    this.playbackRates.push(rate);
    this.videoElement.playbackRate = rate;
  }

  getQualityLevels() {
    return this.qualityLevels;
  }

  getAudioTracks() {
    return this.audioTracks;
  }

  // Mirrors the real AudioTrack model: enabled IS the selection, so
  // selecting one track disables every other, exactly like a real
  // AudioTrackList (at most one track enabled at a time).
  selectAudioTrack(track: WebSdkAudioTrack) {
    this.audioTracks = this.audioTracks.map(existing => ({
      ...existing,
      enabled: existing.id === track.id,
    }));
    this.emit('playerAudioTracksChanged');
  }

  // The real component mutates track.mode directly (there is no
  // selectTextTrack method — the browser's real TextTrackList fires
  // 'change' automatically whenever any of its tracks' mode actually
  // changes). Mirror that reactivity here with a setter, since a plain
  // test double has no such built-in behavior.
  setTextTracks(tracks: (Omit<WebSdkTextTrack, 'mode'> & { mode: string })[]) {
    const emit = () => this.emit('playerTextTracksChanged');
    this.textTracks = tracks.map(track => {
      let mode = track.mode;
      const cueListeners = new Set<() => void>();
      return {
        id: track.id,
        kind: track.kind,
        language: track.language,
        label: track.label,
        activeCues: [] as unknown[],
        addEventListener(event: string, callback: () => void) {
          if (event === 'cuechange') cueListeners.add(callback);
        },
        removeEventListener(event: string, callback: () => void) {
          if (event === 'cuechange') cueListeners.delete(callback);
        },
        emitCueChange() {
          cueListeners.forEach(callback => callback());
        },
        get mode() {
          return mode;
        },
        set mode(next: string) {
          if (mode === next) return;
          mode = next;
          emit();
        },
      };
    });
  }

  getTextTracks() {
    return this.textTracks;
  }

  addedTextTracks: WebSdkTextTrackOptions[] = [];

  addTextTrack(options: WebSdkTextTrackOptions) {
    this.addedTextTracks.push(options);
    const track = {
      id: options.id,
      kind: options.kind,
      language: options.language,
      label: options.label,
      activeCues: [],
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      mode: 'disabled',
    } as unknown as WebSdkTextTrack;
    this.textTracks = [...this.textTracks, track];
    return track;
  }

  getUiManager() {
    return {
      getPlayerContainerUiComponent: () => ({
        getChild: (name: string) => (name === 'ControlBar' ? this.controlBar : null),
      }),
    };
  }

  ssaiIntegration: ReturnType<
    NonNullable<WebSdkPlayerInstance['getIntegrationsManager']>
  >['ssaiIntegration'] = undefined;

  getIntegrationsManager() {
    return {
      imaClientSideIntegration: {
        getCurrentAd: () => this.ad,
        requestAd: (adTagUrl: string) => {
          this.adRequests.push(adTagUrl);
        },
      },
      ssaiIntegration: this.ssaiIntegration,
    };
  }

  adRequests: string[] = [];

  addEventListener(event: string, callback: (eventData?: unknown) => void) {
    if (!this.eventListeners.has(event)) {
      this.eventListeners.set(event, new Set());
    }
    this.eventListeners.get(event)!.add(callback);
  }

  removeEventListener(event: string, callback: (eventData?: unknown) => void) {
    this.eventListeners.get(event)?.delete(callback);
  }

  emit(event: string, eventData?: unknown) {
    const listeners = this.eventListeners.get(event);
    if (listeners) {
      listeners.forEach(cb => cb(eventData));
    }
  }
}

describe('Web Error Classification & Validations', () => {
  it('classifies network errors', () => {
    expect(
      classifyWebPlayerError({
        category: 'Network',
        code: 1001,
        message: 'net fail',
      }).code,
    ).toBe('network');
    expect(
      classifyWebPlayerError({ code: 1003, message: 'timeout' }).code,
    ).toBe('network');
    expect(
      classifyWebPlayerError({ code: 4001, message: 'media net fail' }).code,
    ).toBe('network');
  });

  it('classifies not_found errors for 404/missing resource', () => {
    expect(
      classifyWebPlayerError({ code: 6020, message: 'video not found' }).code,
    ).toBe('not_found');
    expect(
      classifyWebPlayerError({ code: 6019, message: 'resource not found' })
        .code,
    ).toBe('not_found');
    expect(
      classifyWebPlayerError({
        code: 6027,
        message: 'concurrency video not found',
      }).code,
    ).toBe('not_found');
  });

  it('classifies invalid_configuration errors for missing/invalid auth/account', () => {
    expect(
      classifyWebPlayerError({ code: 6000, message: 'invalid account' }).code,
    ).toBe('invalid_configuration');
    expect(
      classifyWebPlayerError({ code: 6001, message: 'missing auth' }).code,
    ).toBe('invalid_configuration');
    expect(
      classifyWebPlayerError({ code: 6005, message: 'token required' }).code,
    ).toBe('invalid_configuration');
  });

  it('classifies drm errors', () => {
    expect(
      classifyWebPlayerError({
        category: 'Eme',
        code: 3005,
        message: 'license failed',
      }).code,
    ).toBe('drm');
    expect(
      classifyWebPlayerError({ code: 4004, message: 'media encrypted error' })
        .code,
    ).toBe('drm');
    expect(
      classifyWebPlayerError({
        code: 5005,
        message: 'segment decryption failed',
      }).code,
    ).toBe('drm');
  });

  it('classifies not_playable errors', () => {
    expect(
      classifyWebPlayerError({ code: 4003, message: 'format unsupported' })
        .code,
    ).toBe('not_playable');
    expect(
      classifyWebPlayerError({ code: 4005, message: 'no source' }).code,
    ).toBe('not_playable');
    expect(
      classifyWebPlayerError({ code: 6034, message: 'no playable sources' })
        .code,
    ).toBe('not_playable');
    expect(
      classifyWebPlayerError({ code: 5000, message: 'hls parse fail' }).code,
    ).toBe('not_playable');
  });

  it('separates fatal SSAI VMAP setup errors from in-ad OM errors', () => {
    [5022, 5023, 5024, 5027].forEach(code => {
      expect(isAdClassWebPlayerError({ code })).toBe(false);
    });
    [5025, 5026].forEach(code => {
      expect(isAdClassWebPlayerError({ code })).toBe(true);
    });
  });

  it('classifies playback errors for mid-stream/abort', () => {
    expect(
      classifyWebPlayerError({ code: 4000, message: 'aborted' }).code,
    ).toBe('playback');
    expect(
      classifyWebPlayerError({ code: 4006, message: 'unknown player error' })
        .code,
    ).toBe('unknown');
    expect(
      classifyWebPlayerError({
        code: 5004,
        message: 'segment selection failed',
      }).code,
    ).toBe('playback');
  });

  it('classifies unknown errors as unknown without guessing', () => {
    expect(classifyWebPlayerError({ code: 9999, message: 'custom' }).code).toBe(
      'unknown',
    );
    expect(classifyWebPlayerError(null).code).toBe('unknown');
    expect(classifyWebPlayerError(undefined).code).toBe('unknown');
  });

  it('validates seek positions strictly', () => {
    expect(validateSeekPosition(10)).toBeNull();
    expect(validateSeekPosition(0)).toBeNull();
    expect(validateSeekPosition(-1)).toBe(
      'positionSeconds must be non-negative',
    );
    expect(validateSeekPosition(NaN)).toBe('positionSeconds must be finite');
    expect(validateSeekPosition(Infinity)).toBe(
      'positionSeconds must be finite',
    );
    expect(validateSeekPosition(-Infinity)).toBe(
      'positionSeconds must be finite',
    );
  });

  it('validates volume and playback rate strictly', () => {
    expect(validateVolume(0.5)).toBeNull();
    expect(validateVolume(0)).toBeNull();
    expect(validateVolume(1)).toBeNull();
    expect(validateVolume(-0.1)).toBe('volume must be between 0 and 1');
    expect(validateVolume(1.1)).toBe('volume must be between 0 and 1');
    expect(validateVolume(NaN)).toBe('volume must be finite');

    expect(validatePlaybackRate(1)).toBeNull();
    expect(validatePlaybackRate(0.5)).toBeNull();
    expect(validatePlaybackRate(2)).toBeNull();
    expect(validatePlaybackRate(0)).toBe('playbackRate must be greater than 0');
    expect(validatePlaybackRate(-1)).toBe(
      'playbackRate must be greater than 0',
    );
    expect(validatePlaybackRate(NaN)).toBe('playbackRate must be finite');
  });

  it('classifies SSAI ad-class failures onto the ad-error contract, never a content code', () => {
    // A Network-category ad failure means an ad resource could not be fetched.
    expect(
      classifyWebAdError({ code: 5015, category: 'Network', message: 'ad request failed' }),
    ).toEqual({ code: 'load', message: 'ad request failed', nativeCode: '5015' });
    // Whatever the category cannot place is 'unknown' — including errors the
    // content classifier would call 'drm' or 'network' — because onAdError's
    // codes are 'load' | 'playback' | 'unknown', not PlayerErrorCode.
    expect(classifyWebAdError({ code: 5025, category: 'Eme', message: 'om failed' }).code).toBe(
      'unknown',
    );
    expect(classifyWebAdError({ code: 5009 }).code).toBe('unknown');
  });

  it('classifies client-side IMA ad errors by their IMA error type', () => {
    const imaAdErrorEvent = (type: string, message = 'VAST error', code: unknown = 1009) => ({
      originalEvent: {
        getError: () => ({
          getType: () => type,
          getMessage: () => message,
          getErrorCode: () => code,
        }),
      },
    });
    expect(classifyImaClientSideAdError(imaAdErrorEvent('adLoadError'))).toEqual({
      code: 'load',
      message: 'VAST error',
      nativeCode: '1009',
    });
    expect(
      classifyImaClientSideAdError(imaAdErrorEvent('adPlayError', 'media failed', 405)).code,
    ).toBe('playback');
    expect(classifyImaClientSideAdError(imaAdErrorEvent('unexpected')).code).toBe('unknown');
    // No IMA error on the payload: 'unknown', with the event's own message and code.
    expect(classifyImaClientSideAdError({ message: 'plugin error', code: 'x1' })).toEqual({
      code: 'unknown',
      message: 'plugin error',
      nativeCode: 'x1',
    });
    expect(classifyImaClientSideAdError(undefined)).toEqual({
      code: 'unknown',
      message: 'IMA client-side ad error',
      nativeCode: 'ima_client_side_ad_error',
    });
  });
});

describe('BrightcovePlayerView.web Component', () => {
  let fakePlayer: FakeWebSdkPlayer;

  beforeEach(() => {
    fakePlayer = new FakeWebSdkPlayer({ accountId: '5420904993001' });
  });

  it('initializes and configures the web SDK player and attaches to DOM container', async () => {
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        playerFactory={() => fakePlayer}
      />,
    );

    expect(fakePlayer.attachedRoot).not.toBeNull();
    expect(fakePlayer.config).toMatchObject({
      brightcove: { policyKey: 'test-policy' },
      ui: { language: 'en', playsinline: true },
    });
    expect(fakePlayer.playbackApiRequests.length).toBe(1);
    expect(fakePlayer.playbackApiRequests[0].payload.videoId).toBe('video-123');
  });

  it('loads video model when playback API resolves and emits onReady when playable', async () => {
    const onReady = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onReady={onReady}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    const dummyModel = { id: 'video-123', name: 'Test Video' };

    await act(async () => {
      req.resolve(dummyModel);
    });

    expect(fakePlayer.loadedModels).toContain(dummyModel);

    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(onReady).toHaveBeenCalledWith({
      nativeEvent: { videoId: 'video-123' },
    });
  });

  it('handles autoplay on ready', async () => {
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={true}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });

    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(fakePlayer.playCalled).toBe(1);
  });

  it('dispatches onPlayerCommandError when play rejects', async () => {
    const onPlayerCommandError = jest.fn();
    fakePlayer.playPromiseShouldReject = true;
    fakePlayer.playRejectionError = new Error('NotAllowedError');

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={true}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });

    await act(async () => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'play',
        code: 'failed',
      }),
    });
  });

  it('dispatches onPlayerCommandError when command executed before ready', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();

    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    await act(async () => {
      await ref.current?.play().catch(() => {});
    });

    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'play',
        code: 'not_ready',
      }),
    });
  });

  it('executes imperative commands (play, pause, seekTo) and PlayerCommands forwarding after ready', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();

    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    await act(async () => {
      PlayerCommands.play(ref.current);
      PlayerCommands.pause(ref.current);
      PlayerCommands.seekTo(ref.current, 30);
    });

    expect(fakePlayer.playCalled).toBe(1);
    expect(fakePlayer.pauseCalled).toBe(1);
    expect(fakePlayer.seekPositions).toEqual([30]);
    expect(onPlayerCommandError).not.toHaveBeenCalled();
  });

  it('rejects invalid seek position values through onPlayerCommandError', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();

    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    act(() => {
      ref.current?.seekTo(-5);
      ref.current?.seekTo(NaN);
      ref.current?.seekTo(Infinity);
    });

    expect(fakePlayer.seekPositions).toEqual([]);
    expect(onPlayerCommandError).toHaveBeenCalledTimes(3);
    expect(onPlayerCommandError).toHaveBeenLastCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'seekTo',
        code: 'invalid_argument',
      }),
    });
  });

  it('aborts prior Playback API request on videoId change and ignores stale resolution', async () => {
    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-1"
        playerFactory={() => fakePlayer}
      />,
    );

    expect(fakePlayer.playbackApiRequests.length).toBe(1);
    const req1 = fakePlayer.playbackApiRequests[0];

    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-2"
        playerFactory={() => fakePlayer}
      />,
    );

    expect(req1.abortCalled).toBe(true);
    expect(fakePlayer.playbackApiRequests.length).toBe(2);

    await act(async () => {
      req1.resolve({ id: 'video-1-stale' });
    });

    expect(fakePlayer.loadedModels).toEqual([]);

    const req2 = fakePlayer.playbackApiRequests[1];
    await act(async () => {
      req2.resolve({ id: 'video-2-fresh' });
    });

    expect(fakePlayer.loadedModels).toEqual([{ id: 'video-2-fresh' }]);
  });

  it('maps SDK playerError events accurately', async () => {
    const onError = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        onError={onError}
        playerFactory={() => fakePlayer}
      />,
    );

    act(() => {
      fakePlayer.emit('playerError', {
        error: { code: 6020, message: 'Video not found' },
      });
    });

    expect(onError).toHaveBeenCalledWith({
      nativeEvent: {
        code: 'not_found',
        message: 'Video not found',
        nativeCode: '6020',
      },
    });
  });

  it('cleans up and disposes idempotently on unmount', () => {
    const { unmount } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        playerFactory={() => fakePlayer}
      />,
    );

    expect(fakePlayer.attachedRoot).not.toBeNull();
    expect(fakePlayer.disposed).toBe(false);

    unmount();

    expect(fakePlayer.detached).toBe(true);
    expect(fakePlayer.disposed).toBe(true);
    expect(fakePlayer.eventListeners.size).toBe(0);
  });

  it('updates live volume, muted, and playbackRate props', () => {
    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        volume={0.5}
        muted={false}
        playbackRate={1}
        playerFactory={() => fakePlayer}
      />,
    );

    expect(fakePlayer.videoElement.volume).toBe(0.5);
    expect(fakePlayer.videoElement.muted).toBe(false);
    expect(fakePlayer.playbackRates).toContain(1);

    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        volume={0.8}
        muted={true}
        playbackRate={1.5}
        playerFactory={() => fakePlayer}
      />,
    );

    expect(fakePlayer.videoElement.volume).toBe(0.8);
    expect(fakePlayer.videoElement.muted).toBe(true);
    expect(fakePlayer.playbackRates).toContain(1.5);
  });

  it('clamps out-of-range volume and keeps the previous rate, matching native', () => {
    const onPlayerCommandError = jest.fn();
    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        volume={0.5}
        playbackRate={1.5}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );
    expect(fakePlayer.videoElement.volume).toBe(0.5);

    // Finite out-of-range volume clamps to the [0,1] endpoint, as both native
    // bridges do — it is not an error.
    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        volume={5}
        playbackRate={1.5}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );
    expect(fakePlayer.videoElement.volume).toBe(1);

    // An invalid rate is ignored, keeping the previously-applied rate.
    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        volume={1}
        playbackRate={0}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );
    expect(fakePlayer.playbackRates[fakePlayer.playbackRates.length - 1]).toBe(1.5);
    expect(onPlayerCommandError).not.toHaveBeenCalled();
  });

  it('does not spuriously fire onCaptionTrackChanged for an off-to-off transition', async () => {
    // Every text track's mode defaults to 'disabled', so "no track showing"
    // is the real starting state. An uninitialized-null starting ref would
    // make the very first resolved-to-'' check look like a change and fire
    // a phantom onCaptionTrackChanged before any real selection ever
    // happened — never observable in the audio-tracks equivalent (real HLS
    // content always has a default-enabled audio track), but caption
    // tracks genuinely start with none showing.
    fakePlayer.setTextTracks([
      { id: '0', kind: 'captions', language: 'en', label: 'English', mode: 'disabled' },
    ]);
    const onCaptionTrackChanged = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onCaptionTrackChanged={onCaptionTrackChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(onCaptionTrackChanged).not.toHaveBeenCalled();
  });

  it('never selects or reports a native kind:subtitles track, and force-disables one that starts showing', async () => {
    // Reproduces a real HLS/videojs-http-streaming behavior confirmed live:
    // when a manifest embeds native SUBTITLES groups (as most captioned VOD
    // sources do), vhs independently auto-registers each group a second
    // time as a native kind:'subtitles' TextTrack, labeled by the
    // manifest's raw NAME rather than a stable id, and immediately honors
    // the manifest's own DEFAULT=YES on it — rendering a cue before any
    // prop-driven selection ever runs, and entirely bypassing
    // captionsEnabled/captionTrackId. Only the Playback-API-added
    // kind:'captions' tracks (stable per-source ids) are addressable.
    fakePlayer.setTextTracks([
      { id: 'abc-123', kind: 'captions', language: 'en', label: 'English', mode: 'disabled' },
      // The manifest's own DEFAULT=YES already set this native track
      // 'showing' before applyCaptionSelection ever runs, exactly as vhs
      // does in practice.
      { id: 'English', kind: 'subtitles', language: 'en', label: 'English', mode: 'showing' },
    ]);
    const onCaptionsAvailable = jest.fn();
    const onCaptionTrackChanged = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onCaptionsAvailable={onCaptionsAvailable}
        onCaptionTrackChanged={onCaptionTrackChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // The native subtitles track must be force-disabled, and the caption
    // track must never be reported as active from it.
    expect(fakePlayer.textTracks.map(track => ({ id: track.id, mode: track.mode }))).toEqual([
      { id: 'abc-123', mode: 'disabled' },
      { id: 'English', mode: 'disabled' },
    ]);
    expect(onCaptionsAvailable).toHaveBeenCalledWith({
      nativeEvent: { tracks: [{ id: 'abc-123', language: 'en', label: 'English' }] },
    });
    expect(onCaptionTrackChanged).not.toHaveBeenCalled();
  });

  it('does not revert an audio track selected through the SDK own control-bar menu', async () => {
    // Reproduces a real bug confirmed live: picking a track through the Web
    // SDK's own control-bar audio-track menu sets AudioTrack.enabled
    // directly on the real list and fires playerAudioTracksChanged
    // immediately — before React ever gets a chance to re-render with a
    // correspondingly updated audioTrackId prop. Reasserting the
    // prop-driven selection on every such event (rather than only when the
    // track list itself changes) reverted the user's native-menu choice
    // back to the stale prop within the same tick, so the menu appeared to
    // do nothing.
    fakePlayer.audioTracks = [
      { id: '0', kind: 'main', language: 'en', label: 'en (Main)', enabled: true },
      { id: '1', kind: 'alternative', language: 'en', label: 'en (Alternate)', enabled: false },
    ];
    const onAudioTrackChanged = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        audioTrackId="0"
        onAudioTrackChanged={onAudioTrackChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(fakePlayer.audioTracks.map(track => track.enabled)).toEqual([true, false]);

    // The SDK's own control-bar menu selects track '1' directly — the
    // audioTrackId prop is still '0' (React has not re-rendered yet).
    act(() => {
      fakePlayer.selectAudioTrack(fakePlayer.audioTracks[1]);
    });

    // Must reflect the native menu's choice, not revert to the stale prop.
    expect(fakePlayer.audioTracks.map(track => track.enabled)).toEqual([false, true]);
    expect(onAudioTrackChanged).toHaveBeenLastCalledWith({
      nativeEvent: { id: '1', language: 'en' },
    });
  });

  it('does not revert a caption track selected through the SDK own control-bar menu', async () => {
    // Same bug, same fix, for captions: picking a track through the Web
    // SDK's own control-bar caption menu sets TextTrack.mode directly and
    // fires playerTextTracksChanged immediately, before React re-renders
    // with an updated captionTrackId prop.
    fakePlayer.setTextTracks([
      { id: '0', kind: 'captions', language: 'en', label: 'English', mode: 'disabled' },
      { id: '1', kind: 'captions', language: 'es', label: 'Spanish', mode: 'disabled' },
    ]);
    const onCaptionTrackChanged = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        captionsEnabled
        captionTrackId="0"
        onCaptionTrackChanged={onCaptionTrackChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(fakePlayer.textTracks.map(track => track.mode)).toEqual([
      'showing',
      'disabled',
    ]);

    // The SDK's own control-bar menu selects the Spanish track directly —
    // captionTrackId is still '0' (React has not re-rendered yet).
    act(() => {
      fakePlayer.textTracks[0].mode = 'disabled';
      fakePlayer.textTracks[1].mode = 'showing';
    });

    // Must reflect the native menu's choice, not revert to the stale prop.
    expect(fakePlayer.textTracks.map(track => track.mode)).toEqual([
      'disabled',
      'showing',
    ]);
    expect(onCaptionTrackChanged).toHaveBeenLastCalledWith({
      nativeEvent: { id: '1', language: 'es' },
    });
  });

  it('keeps captions off when an explicit captionTrackId is not on the source', async () => {
    fakePlayer.setTextTracks([
      { id: '0', kind: 'captions', language: 'en', label: 'English', mode: 'disabled' },
      { id: '1', kind: 'captions', language: 'es', label: 'Spanish', mode: 'disabled' },
    ]);

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        captionsEnabled
        captionTrackId="does-not-exist"
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // Native keeps captions off for an unknown id rather than substituting the
    // first track; web must match.
    expect(fakePlayer.textTracks.map(track => track.mode)).toEqual([
      'disabled',
      'disabled',
    ]);
  });

  it('reports a finite progress duration for a live stream (Infinity -> 0)', async () => {
    const onProgress = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onProgress={onProgress}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    Object.defineProperty(fakePlayer.videoElement, 'duration', {
      configurable: true,
      get: () => Infinity,
    });
    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('timeupdate'));
    });

    expect(onProgress).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({ duration: 0 }),
    });
  });

  it('reports post-playback rebuffering but ignores initial and seek buffering', async () => {
    const onRebufferStart = jest.fn();
    const onRebufferEnd = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onRebufferStart={onRebufferStart}
        onRebufferEnd={onRebufferEnd}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
      fakePlayer.videoElement.dispatchEvent(new Event('waiting'));
    });
    expect(onRebufferStart).not.toHaveBeenCalled();

    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('playing'));
      fakePlayer.videoElement.dispatchEvent(new Event('waiting'));
      fakePlayer.videoElement.dispatchEvent(new Event('waiting'));
    });
    expect(onRebufferStart).toHaveBeenCalledTimes(1);

    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('playing'));
    });
    expect(onRebufferEnd).toHaveBeenCalledTimes(1);

    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('seeking'));
      fakePlayer.videoElement.dispatchEvent(new Event('waiting'));
    });
    expect(onRebufferStart).toHaveBeenCalledTimes(1);
  });

  it('performs chapter seeks by request id and reports the actual seek result', async () => {
    const onChapterSeekCompleted = jest.fn();
    const stablePlayerFactory = () => fakePlayer;
    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        chapterSeekTime={-1}
        chapterSeekRequestId={0}
        onChapterSeekCompleted={onChapterSeekCompleted}
        playerFactory={stablePlayerFactory}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        chapterSeekTime={12}
        chapterSeekRequestId={1}
        onChapterSeekCompleted={onChapterSeekCompleted}
        playerFactory={stablePlayerFactory}
      />,
    );

    expect(fakePlayer.seekPositions).toEqual([12]);
    act(() => {
      Object.defineProperty(fakePlayer.videoElement, 'currentTime', {
        configurable: true,
        value: 12.1,
      });
      fakePlayer.videoElement.dispatchEvent(new Event('seeked'));
    });

    expect(onChapterSeekCompleted).toHaveBeenCalledWith({
      nativeEvent: {
        requestId: 1,
        positionSeconds: 12.1,
        completed: true,
      },
    });
  });

  it('forwards client-side IMA ad lifecycle events', async () => {
    fakePlayer.ad = {
      getAdId: () => 'ad-1',
      getTitle: () => 'Sample ad',
      getDuration: () => 15,
      isLinear: () => true,
      getAdvertiserName: () => 'Advertiser',
      getWidth: () => 640,
      getHeight: () => 360,
      getSkipTimeOffset: () => -1,
    };
    const onAdStarted = jest.fn();
    const onAdCompleted = jest.fn();
    const onAdBreakStarted = jest.fn();
    const onAdBreakEnded = jest.fn();
    const onAdQuartile = jest.fn();
    const onAdInteraction = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        adTagUrl="https://example.com/vmap.xml"
        autoPlay={false}
        onAdStarted={onAdStarted}
        onAdCompleted={onAdCompleted}
        onAdBreakStarted={onAdBreakStarted}
        onAdBreakEnded={onAdBreakEnded}
        onAdQuartile={onAdQuartile}
        onAdInteraction={onAdInteraction}
        playerFactory={() => fakePlayer}
      />,
    );

    expect(fakePlayer.config).toMatchObject({
      integrations: {
        imaClientSide: {
          serverUrl: 'https://example.com/vmap.xml',
          requestMode: 'ondemand',
        },
      },
    });

    act(() => {
      fakePlayer.emit('imaClientSideAdsPodStarted');
      fakePlayer.emit('imaClientSideAdStarted');
      fakePlayer.emit('imaClientSideFirstQuartile');
      fakePlayer.emit('imaClientSideAdClick');
      fakePlayer.emit('imaClientSideAdComplete');
      fakePlayer.emit('imaClientSideAdsPodEnded');
    });

    expect(onAdBreakStarted).toHaveBeenCalledWith({
      nativeEvent: { index: -1 },
    });
    expect(onAdStarted).toHaveBeenCalledWith({
      nativeEvent: { adTitle: 'Sample ad', duration: 15 },
    });
    expect(onAdQuartile).toHaveBeenCalledWith({
      nativeEvent: { adId: 'ad-1', quartile: 25 },
    });
    expect(onAdInteraction).toHaveBeenCalledWith({
      nativeEvent: { adId: 'ad-1', interaction: 'clicked' },
    });
    expect(onAdCompleted).toHaveBeenCalledWith({
      nativeEvent: { adTitle: 'Sample ad', duration: 15 },
    });
    expect(onAdBreakEnded).toHaveBeenCalledWith({
      nativeEvent: { index: -1 },
    });
  });

  it('forwards source, first-frame, duration, size, and seek lifecycle events', () => {
    const onSourceLoading = jest.fn();
    const onFirstFrame = jest.fn();
    const onDurationChanged = jest.fn();
    const onVideoSizeChanged = jest.fn();
    const onSeekStarted = jest.fn();
    const onSeekCompleted = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onSourceLoading={onSourceLoading}
        onFirstFrame={onFirstFrame}
        onDurationChanged={onDurationChanged}
        onVideoSizeChanged={onVideoSizeChanged}
        onSeekStarted={onSeekStarted}
        onSeekCompleted={onSeekCompleted}
        playerFactory={() => fakePlayer}
      />,
    );

    expect(onSourceLoading).toHaveBeenCalledWith({
      nativeEvent: { videoId: 'video-123' },
    });

    Object.defineProperties(fakePlayer.videoElement, {
      duration: { configurable: true, value: 90 },
      videoWidth: { configurable: true, value: 1280 },
      videoHeight: { configurable: true, value: 720 },
      currentTime: { configurable: true, writable: true, value: 0 },
    });
    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('loadedmetadata'));
      fakePlayer.videoElement.dispatchEvent(new Event('loadeddata'));
      fakePlayer.videoElement.currentTime = 12;
      fakePlayer.videoElement.dispatchEvent(new Event('seeking'));
      fakePlayer.videoElement.dispatchEvent(new Event('seeked'));
    });

    expect(onFirstFrame).toHaveBeenCalledWith({
      nativeEvent: { videoId: 'video-123' },
    });
    expect(onDurationChanged).toHaveBeenCalledWith({
      nativeEvent: { durationSeconds: 90 },
    });
    expect(onVideoSizeChanged).toHaveBeenCalledWith({
      nativeEvent: { width: 1280, height: 720 },
    });
    expect(onSeekStarted).toHaveBeenCalledWith({
      nativeEvent: { requestedPositionSeconds: 12 },
    });
    expect(onSeekCompleted).toHaveBeenCalledWith({
      nativeEvent: { positionSeconds: 12, completed: true },
    });
  });

  it('renders custom caption cues through the cue event without native rendering', async () => {
    fakePlayer.setTextTracks([
      { id: 'caption-1', kind: 'captions', language: 'en', label: 'English', mode: 'disabled' },
    ]);
    const onCaptionCueChanged = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        captionsEnabled
        customCaptionRenderingEnabled
        onCaptionCueChanged={onCaptionCueChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(fakePlayer.textTracks[0].mode).toBe('hidden');
    const track = fakePlayer.textTracks[0] as WebSdkTextTrack & {
      activeCues: unknown[];
      emitCueChange: () => void;
    };
    track.activeCues = [
      { text: '<unsafe> cue', startTime: 3, endTime: 6 },
      { text: 'second line', startTime: 3, endTime: 5 },
    ];
    act(() => {
      track.emitCueChange();
    });

    expect(onCaptionCueChanged).toHaveBeenLastCalledWith({
      nativeEvent: {
        text: '<unsafe> cue\nsecond line',
        startTime: 3,
        endTime: 6,
      },
    });
  });

  it('prefetches the next video model and hands it off when the current video ends', async () => {
    const onPreloadQueued = jest.fn();
    const onPreloadHandoff = jest.fn();
    const onReady = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-current"
        preloadVideoId="video-next"
        autoPlay={false}
        onPreloadQueued={onPreloadQueued}
        onPreloadHandoff={onPreloadHandoff}
        onReady={onReady}
        playerFactory={() => fakePlayer}
      />,
    );

    const currentRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      currentRequest.resolve({ id: 'video-current' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(fakePlayer.playbackApiRequests).toHaveLength(2);
    const preloadRequest = fakePlayer.playbackApiRequests[1];
    await act(async () => {
      preloadRequest.resolve({ id: 'video-next', name: 'Next Video' });
    });

    expect(onPreloadQueued).toHaveBeenCalledWith({
      nativeEvent: { videoId: 'video-next' },
    });

    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('ended'));
    });

    expect(fakePlayer.loadedModels).toContainEqual({
      id: 'video-next',
      name: 'Next Video',
    });
    expect(onPreloadHandoff).toHaveBeenCalledWith({
      nativeEvent: {
        previousVideoId: 'video-current',
        currentVideoId: 'video-next',
      },
    });

    act(() => {
      fakePlayer.emit('playerCanPlay');
    });
    expect(onReady).toHaveBeenLastCalledWith({
      nativeEvent: { videoId: 'video-next' },
    });
  });

  it('controlsEnabled uses UI Manager to show and hide the control bar', async () => {
    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        controlsEnabled={true}
        autoPlay={false}
        playerFactory={() => fakePlayer}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(fakePlayer.controlBar.show).toHaveBeenCalled();

    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        controlsEnabled={false}
        autoPlay={false}
        playerFactory={() => fakePlayer}
      />,
    );

    expect(fakePlayer.controlBar.hide).toHaveBeenCalled();
  });

  it('applies preferredPeakBitrate ceiling and enables lowest bitrate when all renditions exceed ceiling', async () => {
    const stableFactory = () => fakePlayer;
    fakePlayer.qualityLevels = [
      { id: '1', label: '1080p', bitrate: 5000000, enabled: true },
      { id: '2', label: '720p', bitrate: 2500000, enabled: true },
      { id: '3', label: '360p', bitrate: 800000, enabled: true },
    ];

    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        preferredPeakBitrate={3000000}
        autoPlay={false}
        playerFactory={stableFactory}
      />,
    );

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    expect(fakePlayer.qualityLevels.map(l => ({ bitrate: l.bitrate, enabled: l.enabled }))).toEqual([
      { bitrate: 5000000, enabled: false },
      { bitrate: 2500000, enabled: true },
      { bitrate: 800000, enabled: true },
    ]);

    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        preferredPeakBitrate={500000}
        autoPlay={false}
        playerFactory={stableFactory}
      />,
    );

    expect(fakePlayer.qualityLevels.map(l => ({ bitrate: l.bitrate, enabled: l.enabled }))).toEqual([
      { bitrate: 5000000, enabled: false },
      { bitrate: 2500000, enabled: false },
      { bitrate: 800000, enabled: true },
    ]);

    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        preferredPeakBitrate={0}
        autoPlay={false}
        playerFactory={stableFactory}
      />,
    );

    expect(fakePlayer.qualityLevels.map(l => ({ bitrate: l.bitrate, enabled: l.enabled }))).toEqual([
      { bitrate: 5000000, enabled: true },
      { bitrate: 2500000, enabled: true },
      { bitrate: 800000, enabled: true },
    ]);
  });

  it('executes seekToLiveEdge on live streams and reports errors when not live or not ready', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();

    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-live"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    act(() => {
      ref.current?.seekToLiveEdge?.();
    });
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'seekToLiveEdge',
        code: 'not_ready',
      }),
    });

    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-live' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    act(() => {
      ref.current?.seekToLiveEdge?.();
    });
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'seekToLiveEdge',
        code: 'invalid_state',
        nativeCode: 'not_live',
      }),
    });

    Object.defineProperties(fakePlayer.videoElement, {
      duration: { configurable: true, value: Infinity },
      seekable: {
        configurable: true,
        value: {
          length: 1,
          start: () => 0,
          end: () => 120,
        },
      },
    });

    act(() => {
      ref.current?.seekToLiveEdge?.();
    });

    expect(fakePlayer.seekPositions).toContain(120);
  });

  it('executeExitFullscreen reports unavailable when document.exitFullscreen is missing', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    const originalExitFullscreen = document.exitFullscreen;
    delete (document as Partial<Document>).exitFullscreen;

    try {
      render(
        <BrightcovePlayerView
          ref={ref}
          accountId="5420904993001"
          policyKey="test-policy"
          videoId="video-123"
          autoPlay={false}
          onPlayerCommandError={onPlayerCommandError}
          playerFactory={() => fakePlayer}
        />,
      );

      await act(async () => {
        await ref.current?.exitFullscreen?.();
      });

      expect(onPlayerCommandError).toHaveBeenCalledWith({
        nativeEvent: expect.objectContaining({
          command: 'exitFullscreen',
          code: 'unavailable',
          nativeCode: 'fullscreen_unsupported',
        }),
      });
    } finally {
      document.exitFullscreen = originalExitFullscreen;
    }
  });

  it('executeReload reports not-ready and fetch failures through onError and onPlayerCommandError', async () => {
    const onError = jest.fn();
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();

    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onError={onError}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const req1 = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req1.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    act(() => {
      ref.current?.reload?.();
    });

    expect(fakePlayer.playbackApiRequests).toHaveLength(2);
    const reloadReq = fakePlayer.playbackApiRequests[1];

    await act(async () => {
      reloadReq.reject({ code: 6020, message: 'Video not found on reload' });
    });

    expect(onError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        code: 'not_found',
        message: 'Video not found on reload',
      }),
    });
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'reload',
        code: 'failed',
        nativeCode: 'reload_failed',
      }),
    });
  });

  it('emits onPreloadError if loadBrightcoveVideoModel fails during preload handoff', async () => {
    const onPreloadError = jest.fn();

    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-current"
        preloadVideoId="video-next"
        autoPlay={false}
        onPreloadError={onPreloadError}
        playerFactory={() => fakePlayer}
      />,
    );

    const currentRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      currentRequest.resolve({ id: 'video-current' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    const preloadRequest = fakePlayer.playbackApiRequests[1];
    await act(async () => {
      preloadRequest.resolve({ id: 'video-next' });
    });

    fakePlayer.loadModelShouldThrow = true;

    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('ended'));
    });

    expect(onPreloadError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        videoId: 'video-next',
        code: 'playback',
        nativeCode: 'preload_handoff_failed',
      }),
    });
  });

  it('does not re-initialize on rerender with new array reference of same videoIds', async () => {
    const stableFactory = () => fakePlayer;
    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1', 'video-2']}
        autoPlay={false}
        playerFactory={stableFactory}
      />,
    );

    expect(fakePlayer.playbackApiRequests).toHaveLength(1);

    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1', 'video-2']}
        autoPlay={false}
        playerFactory={stableFactory}
      />,
    );

    expect(fakePlayer.playbackApiRequests).toHaveLength(1);
  });

  it('PlayerCommands logs rejected promises and caught exceptions with console.error', async () => {
    const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
    try {
      const rejectingHandle: BrightcovePlayerWebHandle = {
        play: jest.fn(() => Promise.reject(new Error('play error'))),
        pause: jest.fn(() => {
          throw new Error('pause sync error');
        }),
        seekTo: jest.fn(),
      };

      PlayerCommands.play(rejectingHandle);
      PlayerCommands.pause(rejectingHandle);
      await Promise.resolve();

      expect(consoleSpy).toHaveBeenCalledWith(
        '[BrightcovePlayerCommands] pause failed',
        expect.any(Error),
      );
      expect(consoleSpy).toHaveBeenCalledWith(
        '[BrightcovePlayerCommands] play failed',
        expect.any(Error),
      );
    } finally {
      consoleSpy.mockRestore();
    }
  });

  it('next at the last queue item emits a queue_at_end command error and does not fire onQueueCompleted', async () => {
    const onQueueCompleted = jest.fn();
    const onPlayerCommandError = jest.fn();
    const playerRef = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={playerRef}
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1', 'video-2']}
        autoPlay={false}
        onQueueCompleted={onQueueCompleted}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    // Resolve the first queue item and reach readiness.
    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // Advance to the second (last) item.
    act(() => {
      playerRef.current?.next?.();
    });
    expect(fakePlayer.playbackApiRequests).toHaveLength(2);
    await act(async () => {
      fakePlayer.playbackApiRequests[1].resolve({ id: 'video-2' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    onQueueCompleted.mockClear();
    onPlayerCommandError.mockClear();

    // A manual `next` at the last item is a typed rejection, not a
    // completion: onQueueCompleted is the natural-completion event only.
    act(() => {
      playerRef.current?.next?.();
    });

    expect(onQueueCompleted).not.toHaveBeenCalled();
    expect(onPlayerCommandError).toHaveBeenCalledTimes(1);
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: {
        command: 'next',
        code: 'invalid_state',
        message:
          "Cannot advance the queue: the last item is already playing and the repeat mode does not wrap the queue",
        nativeCode: 'queue_at_end',
      },
    });
  });

  it('fires onQueueCompleted exactly once for duplicate ended events at the last item', async () => {
    const onQueueCompleted = jest.fn();
    const onQueueItemChanged = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1']}
        autoPlay={false}
        onQueueCompleted={onQueueCompleted}
        onQueueItemChanged={onQueueItemChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // The single-item queue: a first `ended` completes the queue naturally.
    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('ended'));
    });
    expect(onQueueCompleted).toHaveBeenCalledTimes(1);

    // A second `ended` (re-dispatched event) must not fire the completion
    // callback again — the once-per-queue latch holds.
    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('ended'));
    });
    expect(onQueueCompleted).toHaveBeenCalledTimes(1);
  });

  it('next with no videoIds emits the typed queue_not_loaded error', async () => {
    const onPlayerCommandError = jest.fn();
    const playerRef = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={playerRef}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    onPlayerCommandError.mockClear();
    act(() => {
      playerRef.current?.next?.();
    });

    expect(onPlayerCommandError).toHaveBeenCalledTimes(1);
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: {
        command: 'next',
        code: 'invalid_state',
        message: 'Cannot advance the queue: no queue is loaded in this player',
        nativeCode: 'queue_not_loaded',
      },
    });
  });

  it('next at the last item with repeatMode all wraps to item 0', async () => {
    const onQueueCompleted = jest.fn();
    const onPlayerCommandError = jest.fn();
    const playerRef = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={playerRef}
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1', 'video-2']}
        repeatMode="all"
        autoPlay={false}
        onQueueCompleted={onQueueCompleted}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });
    act(() => {
      playerRef.current?.next?.();
    });
    await act(async () => {
      fakePlayer.playbackApiRequests[1].resolve({ id: 'video-2' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    onQueueCompleted.mockClear();
    onPlayerCommandError.mockClear();

    // repeat-all wraps: the manual next at the last item loads item 0 again
    // instead of reporting queue_at_end, and never completes the queue.
    act(() => {
      playerRef.current?.next?.();
    });
    expect(fakePlayer.playbackApiRequests).toHaveLength(3);
    await act(async () => {
      fakePlayer.playbackApiRequests[2].resolve({ id: 'video-1' });
    });
    expect(onPlayerCommandError).not.toHaveBeenCalled();
    expect(onQueueCompleted).not.toHaveBeenCalled();
    expect(fakePlayer.loadedModels).toHaveLength(3);
  });

  it('natural ended at the last item with repeatMode all wraps instead of completing', async () => {
    const onQueueCompleted = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1']}
        repeatMode="all"
        autoPlay={false}
        onQueueCompleted={onQueueCompleted}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // A wrapping queue never completes: the natural end of the last item
    // loads item 0 again.
    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('ended'));
    });
    expect(onQueueCompleted).not.toHaveBeenCalled();
    expect(fakePlayer.playbackApiRequests).toHaveLength(2);
    await act(async () => {
      fakePlayer.playbackApiRequests[1].resolve({ id: 'video-1' });
    });
  });

  it('repeatMode one loops the current item and never completes the queue', async () => {
    const onQueueCompleted = jest.fn();
    const onEnded = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1']}
        repeatMode="one"
        autoPlay={false}
        onQueueCompleted={onQueueCompleted}
        onEnded={onEnded}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // The element loops the item, so `ended` never reaches JS at all —
    // matching native's REPEAT_MODE_ONE — and the queue never completes.
    expect(fakePlayer.videoElement.loop).toBe(true);
    expect(onQueueCompleted).not.toHaveBeenCalled();
    expect(onEnded).not.toHaveBeenCalled();
  });

  it('a non-linear CSAI ad reports onAdOverlayStateChanged on start and complete', async () => {
    fakePlayer.ad = {
      getAdId: () => 'overlay-1',
      getTitle: () => 'Overlay ad',
      getDuration: () => 10,
      isLinear: () => false,
      getAdvertiserName: () => 'Advertiser',
      getWidth: () => 468,
      getHeight: () => 60,
      getSkipTimeOffset: () => -1,
    };
    const onAdOverlayStateChanged = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        adTagUrl="https://example.com/vmap.xml"
        autoPlay={false}
        onAdOverlayStateChanged={onAdOverlayStateChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    act(() => {
      fakePlayer.emit('imaClientSideAdStarted');
    });
    expect(onAdOverlayStateChanged).toHaveBeenCalledWith({
      nativeEvent: { adId: 'overlay-1', visible: true },
    });

    act(() => {
      fakePlayer.emit('imaClientSideAdComplete');
    });
    expect(onAdOverlayStateChanged).toHaveBeenLastCalledWith({
      nativeEvent: { adId: 'overlay-1', visible: false },
    });
  });

  it('SSAI break events report the contract break index -1', async () => {
    // The SSAI timeline listener: build a fake ssai integration with a
    // linear ad and verify the emitted break payload carries the shared
    // contract's -1, not the roll's positional index.
    const onAdBreakStarted = jest.fn();
    const ad = {
      absoluteStartTime: () => 0,
      absoluteEndTime: () => 30,
      adTitle: () => 'SSAI ad',
      duration: () => 30,
    };
    fakePlayer.ssaiIntegration = {
      getRelativeTimelineState: () => ({
        linearAdRoll: { indexOf: (candidate: unknown) => (candidate === ad ? 3 : -1) },
        linearAd: ad,
      }),
    } as never;
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        adConfigId="test-ad-config"
        autoPlay={false}
        onAdBreakStarted={onAdBreakStarted}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });
    // timeupdate drives updateSsaiTimeline: the ad becomes active, firing
    // the break-started payload.
    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('timeupdate'));
    });

    expect(onAdBreakStarted).toHaveBeenCalledTimes(1);
    expect(onAdBreakStarted).toHaveBeenCalledWith({
      nativeEvent: { index: -1 },
    });
  });

  it('enterFullscreen uses the prefixed request when the standard one is missing', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    const { container } = render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    // render().container > View-mock div > player container div.
    const playerDiv = container.firstElementChild!.firstElementChild as HTMLElement & {
      webkitRequestFullscreen?: () => void;
    };
    let prefixedCalled = false;
    playerDiv.webkitRequestFullscreen = () => {
      prefixedCalled = true;
    };
    const originalRequest = playerDiv.requestFullscreen;
    delete (playerDiv as Partial<HTMLElement>).requestFullscreen;
    try {
      await act(async () => {
        await ref.current?.enterFullscreen?.();
      });
      expect(prefixedCalled).toBe(true);
      expect(onPlayerCommandError).not.toHaveBeenCalled();
    } finally {
      playerDiv.requestFullscreen = originalRequest;
      delete playerDiv.webkitRequestFullscreen;
    }
  });

  it('enterFullscreen targets the video.js element so the in-player toggle stays in sync', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    const { container } = render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    // The web SDK mounts the <video> inside a `.video-js` root; the in-player
    // FullscreenToggle fullscreens that root. Mirror that structure so the
    // command and the toggle must agree on the same element — the regression
    // was requesting fullscreen on our wrapper container instead, which left
    // the toggle reading "Fullscreen" and unable to exit.
    const playerDiv = container.firstElementChild!.firstElementChild as HTMLElement;
    const videoJsRoot = document.createElement('div');
    videoJsRoot.className = 'video-js';
    playerDiv.appendChild(videoJsRoot);
    videoJsRoot.appendChild(fakePlayer.videoElement);

    let fullscreened: string | null = null;
    videoJsRoot.requestFullscreen = () => {
      fullscreened = 'video-js';
      return Promise.resolve();
    };
    playerDiv.requestFullscreen = () => {
      fullscreened = 'container';
      return Promise.resolve();
    };

    await act(async () => {
      await ref.current?.enterFullscreen?.();
    });
    expect(fullscreened).toBe('video-js');
    expect(onPlayerCommandError).not.toHaveBeenCalled();
  });

  it('the webkitfullscreenchange listener drives the same handler', async () => {
    const onFullscreenChanged = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onFullscreenChanged={onFullscreenChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // The prefixed Safari event must be handled like the standard one; the
    // second dispatch of an unchanged state is deduped.
    const original = document.fullscreenElement;
    Object.defineProperty(document, 'fullscreenElement', {
      configurable: true,
      get: () => null,
    });
    try {
      act(() => {
        document.dispatchEvent(new Event('webkitfullscreenchange'));
      });
      expect(onFullscreenChanged).toHaveBeenCalledWith({
        nativeEvent: { active: false },
      });
      const callsAfterFirst = onFullscreenChanged.mock.calls.length;
      act(() => {
        document.dispatchEvent(new Event('webkitfullscreenchange'));
      });
      expect(onFullscreenChanged.mock.calls.length).toBe(callsAfterFirst);
    } finally {
      Object.defineProperty(document, 'fullscreenElement', {
        configurable: true,
        get: () => original,
      });
    }
  });

  it('fullscreen change for a contained fullscreen element reports active (video.js child div)', async () => {
    const onFullscreenChanged = jest.fn();
    const { container } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onFullscreenChanged={onFullscreenChanged}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // video.js fullscreens its own child player div, not the container or
    // the video element: a contained fullscreen element must count as active.
    // The mocked View renders a div wrapping the player container div.
    // render().container > View-mock div > player container div.
    const playerDiv = container.firstElementChild!.firstElementChild;
    const contained = document.createElement('div');
    playerDiv!.appendChild(contained);
    const original = document.fullscreenElement;
    Object.defineProperty(document, 'fullscreenElement', {
      configurable: true,
      get: () => contained,
    });
    try {
      act(() => {
        document.dispatchEvent(new Event('fullscreenchange'));
      });
      expect(onFullscreenChanged).toHaveBeenLastCalledWith({
        nativeEvent: { active: true },
      });

      // An unrelated document-level fullscreen element stays inactive.
      const unrelated = document.createElement('div');
      document.body.appendChild(unrelated);
      Object.defineProperty(document, 'fullscreenElement', {
        configurable: true,
        get: () => unrelated,
      });
      act(() => {
        document.dispatchEvent(new Event('fullscreenchange'));
      });
      expect(onFullscreenChanged).toHaveBeenLastCalledWith({
        nativeEvent: { active: false },
      });
      unrelated.remove();
    } finally {
      Object.defineProperty(document, 'fullscreenElement', {
        configurable: true,
        get: () => original,
      });
      contained.remove();
    }
  });

  it('executeEnterPiP uses the prefixed presentation-mode API when the standard one is missing', async () => {
    const onPictureInPictureModeChanged = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    const video = fakePlayer.videoElement as HTMLVideoElement & {
      requestPictureInPicture?: unknown;
      webkitSupportsPresentationMode?: (mode: string) => boolean;
      webkitSetPresentationMode?: (mode: string) => void;
      presentationMode?: string;
    };
    const originalRequest = video.requestPictureInPicture;
    delete (video as Partial<HTMLVideoElement>).requestPictureInPicture;
    video.webkitSupportsPresentationMode = (mode: string) =>
      mode === 'picture-in-picture';
    let setMode: string | null = null;
    video.webkitSetPresentationMode = (mode: string) => {
      setMode = mode;
      video.presentationMode = mode;
    };

    try {
      render(
        <BrightcovePlayerView
          ref={ref}
          accountId="5420904993001"
          policyKey="test-policy"
          videoId="video-123"
          autoPlay={false}
          pictureInPictureEnabled={true}
          onPictureInPictureModeChanged={onPictureInPictureModeChanged}
          playerFactory={() => fakePlayer}
        />,
      );

      const firstRequest = fakePlayer.playbackApiRequests[0];
      await act(async () => {
        firstRequest.resolve({ id: 'video-123' });
      });
      act(() => {
        fakePlayer.emit('playerCanPlay');
      });

      await act(async () => {
        await ref.current?.enterPictureInPicture?.();
      });
      expect(setMode).toBe('picture-in-picture');

      // The prefixed presentation-mode event reports the active state.
      act(() => {
        video.dispatchEvent(new Event('webkitpresentationmodechanged'));
      });
      expect(onPictureInPictureModeChanged).toHaveBeenLastCalledWith({
        nativeEvent: { active: true },
      });
    } finally {
      video.requestPictureInPicture = originalRequest;
      delete video.webkitSupportsPresentationMode;
      delete video.webkitSetPresentationMode;
      delete video.presentationMode;
    }
  });

  it('previous moves back in the queue and restarts at the first item', async () => {
    const onQueueItemChanged = jest.fn();
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1', 'video-2']}
        autoPlay={false}
        onQueueItemChanged={onQueueItemChanged}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });
    act(() => {
      ref.current?.next?.();
    });
    await act(async () => {
      fakePlayer.playbackApiRequests[1].resolve({ id: 'video-2' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    onQueueItemChanged.mockClear();
    onPlayerCommandError.mockClear();

    // From item 1, previous loads item 0.
    act(() => {
      ref.current?.previous?.();
    });
    expect(fakePlayer.playbackApiRequests).toHaveLength(3);
    await act(async () => {
      fakePlayer.playbackApiRequests[2].resolve({ id: 'video-1' });
    });
    expect(onQueueItemChanged).toHaveBeenCalledWith({
      nativeEvent: { videoId: 'video-1', index: 0 },
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // At item 0 without repeat, previous restarts the current item — never
    // a failure while a queue is loaded.
    onPlayerCommandError.mockClear();
    act(() => {
      ref.current?.previous?.();
    });
    expect(onPlayerCommandError).not.toHaveBeenCalled();
    expect(fakePlayer.videoElement.currentTime).toBe(0);
    expect(fakePlayer.playCalled).toBeGreaterThan(0);
  });

  it('previous with no videoIds emits the typed queue_not_loaded error', async () => {
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    act(() => {
      ref.current?.previous?.();
    });
    expect(onPlayerCommandError).toHaveBeenCalledTimes(1);
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: {
        command: 'previous',
        code: 'invalid_state',
        message: 'Cannot go to the previous queue item: no queue is loaded in this player',
        nativeCode: 'queue_not_loaded',
      },
    });
  });

  it('commands after a terminal source error are rejected with source_failed; reload recovers', async () => {
    const onError = jest.fn();
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onError={onError}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // A terminal player error fails the source.
    act(() => {
      fakePlayer.emit('playerError', { error: { code: 4000, message: 'boom' } });
    });
    expect(onError).toHaveBeenCalledTimes(1);

    onPlayerCommandError.mockClear();
    act(() => {
      ref.current?.play?.();
    });
    act(() => {
      ref.current?.seekTo?.(1);
    });
    act(() => {
      ref.current?.next?.();
    });
    expect(onPlayerCommandError).toHaveBeenCalledTimes(3);
    const calls = onPlayerCommandError.mock.calls as Array<
      [{ nativeEvent: { code: string; nativeCode: string } }]
    >;
    for (const call of calls) {
      expect(call[0].nativeEvent.code).toBe('invalid_state');
      expect(call[0].nativeEvent.nativeCode).toBe('source_failed');
    }

    // Reload stays available as the recovery path.
    onPlayerCommandError.mockClear();
    act(() => {
      ref.current?.reload?.();
    });
    expect(onPlayerCommandError).not.toHaveBeenCalled();
    expect(fakePlayer.playbackApiRequests).toHaveLength(2);
  });

  it('a failure of the last queue item latches source_failed like any terminal error', async () => {
    const onError = jest.fn();
    const onQueueItemFailed = jest.fn();
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1', 'video-2']}
        autoPlay={false}
        onError={onError}
        onQueueItemFailed={onQueueItemFailed}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    await act(async () => {
      fakePlayer.playbackApiRequests[0].resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });
    act(() => {
      ref.current?.next?.();
    });
    // The last item cannot be resolved, so the queue has nothing left to play.
    await act(async () => {
      fakePlayer.playbackApiRequests[1].reject({ code: 6019, message: 'video not found' });
    });
    expect(onQueueItemFailed).toHaveBeenCalledTimes(1);
    expect(onError).toHaveBeenCalledTimes(1);

    onPlayerCommandError.mockClear();
    act(() => {
      ref.current?.play?.();
    });
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'play',
        code: 'invalid_state',
        nativeCode: 'source_failed',
      }),
    });
  });

  it('reports an SSAI ad-class failure with an ad-error code and keeps the source playing', async () => {
    const onError = jest.fn();
    const onAdError = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onError={onError}
        onAdError={onAdError}
        playerFactory={() => fakePlayer}
      />,
    );
    await act(async () => {
      fakePlayer.playbackApiRequests[0].resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    act(() => {
      fakePlayer.emit('playerError', {
        error: { code: 5015, category: 'Network', message: 'ad request failed' },
      });
    });
    expect(onAdError).toHaveBeenCalledWith({
      nativeEvent: { code: 'load', message: 'ad request failed', nativeCode: '5015' },
    });
    expect(onError).not.toHaveBeenCalled();
  });

  it('reports a client-side IMA ad error with the code its IMA error type implies', async () => {
    const onAdError = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        adTagUrl="https://example.com/vmap.xml"
        autoPlay={false}
        onAdError={onAdError}
        playerFactory={() => fakePlayer}
      />,
    );

    act(() => {
      fakePlayer.emit('imaClientSideAdError', {
        originalEvent: {
          getError: () => ({
            getType: () => 'adLoadError',
            getMessage: () => 'VAST response was empty',
            getErrorCode: () => 1009,
          }),
        },
      });
    });
    expect(onAdError).toHaveBeenCalledWith({
      nativeEvent: { code: 'load', message: 'VAST response was empty', nativeCode: '1009' },
    });
  });

  it('reload recovers a source that failed before readiness (mirrors native)', async () => {
    const onError = jest.fn();
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onError={onError}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    // The initial fetch rejects, so the source never reaches canplay and
    // sourceReadyRef stays false while the source is latched as failed.
    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.reject({ code: 6020, message: 'Video not found' });
    });
    expect(onError).toHaveBeenCalledTimes(1);

    // Reload is the recovery path even though the source never became ready.
    onPlayerCommandError.mockClear();
    act(() => {
      ref.current?.reload?.();
    });
    expect(onPlayerCommandError).not.toHaveBeenCalled();
    expect(fakePlayer.playbackApiRequests).toHaveLength(2);
  });

  it('an SSAI VMAP setup error fails the source instead of reporting an ad-only error', async () => {
    const onError = jest.fn();
    const onAdError = jest.fn();
    const onPlayerCommandError = jest.fn();
    const ref = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onError={onError}
        onAdError={onAdError}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // SsaiVmapParsingError (5022) occurs before the stitched source exists,
    // so it is a fatal source error (the same contract as Android/iOS), not an
    // ad-only failure.
    act(() => {
      fakePlayer.emit('playerError', {
        error: { code: 5022, message: 'vmap parse failed' },
      });
    });
    expect(onError).toHaveBeenCalledWith({
      nativeEvent: {
        code: 'unknown',
        message: 'vmap parse failed',
        nativeCode: '5022',
      },
    });
    expect(onAdError).not.toHaveBeenCalled();

    // The source failed: transport commands reject until reload/new source.
    act(() => {
      ref.current?.play?.();
    });
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'play',
        code: 'invalid_state',
        nativeCode: 'source_failed',
      }),
    });
  });

  it('changing an ad config prop after mount reports ad_config_init_only instead of a silent no-op', async () => {
    const onPlayerCommandError = jest.fn();
    const { rerender } = render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-123' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    onPlayerCommandError.mockClear();
    rerender(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        adTagUrl="https://example.com/vmap.xml"
        autoPlay={false}
        onPlayerCommandError={onPlayerCommandError}
        playerFactory={() => fakePlayer}
      />,
    );

    expect(onPlayerCommandError).toHaveBeenCalledTimes(1);
    expect(onPlayerCommandError).toHaveBeenCalledWith({
      nativeEvent: expect.objectContaining({
        command: 'setAdConfiguration',
        code: 'invalid_configuration',
        nativeCode: 'ad_config_init_only',
      }),
    });
  });

  it('playbackRate is reapplied after a same-player source swap', async () => {
    const ref = createRef<BrightcovePlayerWebHandle>();
    render(
      <BrightcovePlayerView
        ref={ref}
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1', 'video-2']}
        playbackRate={2}
        autoPlay={false}
        playerFactory={() => fakePlayer}
      />,
    );

    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });
    // HTML media resets the element's rate on the new resource; the first
    // canplay of the second item must reapply the requested 2x.
    fakePlayer.videoElement.playbackRate = 1;

    act(() => {
      ref.current?.next?.();
    });
    await act(async () => {
      fakePlayer.playbackApiRequests[1].resolve({ id: 'video-2' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });

    // The rate was applied for the first item and reapplied after the
    // swap's first canplay — never left at the element's reset default.
    expect(fakePlayer.playbackRates.length).toBeGreaterThanOrEqual(2);
    expect(fakePlayer.playbackRates.every(rate => rate === 2)).toBe(true);
    expect(fakePlayer.videoElement.playbackRate).toBe(2);
  });

  it('a preload handoff consumes the queue completion latch and queue index', async () => {
    const onQueueCompleted = jest.fn();
    const onPreloadHandoff = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoIds={['video-1']}
        preloadVideoId="video-2"
        autoPlay={false}
        onQueueCompleted={onQueueCompleted}
        onPreloadHandoff={onPreloadHandoff}
        playerFactory={() => fakePlayer}
      />,
    );

    // Resolve the current item, then the preload fetch it triggered.
    const firstRequest = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      firstRequest.resolve({ id: 'video-1' });
    });
    act(() => {
      fakePlayer.emit('playerCanPlay');
    });
    expect(fakePlayer.playbackApiRequests).toHaveLength(2);
    const preloadRequest = fakePlayer.playbackApiRequests[1];
    await act(async () => {
      preloadRequest.resolve({ id: 'video-2' });
    });
    expect(onPreloadHandoff).not.toHaveBeenCalled();

    // The natural end of the (only) queue item hands off instead of
    // completing the queue — the preloaded item is outside the videoIds
    // queue, so onQueueCompleted must not fire for it either, now or on its
    // own later `ended`.
    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('ended'));
    });
    expect(onPreloadHandoff).toHaveBeenCalledTimes(1);
    expect(onQueueCompleted).not.toHaveBeenCalled();

    act(() => {
      fakePlayer.videoElement.dispatchEvent(new Event('ended'));
    });
    expect(onQueueCompleted).not.toHaveBeenCalled();
  });
});

describe('Web sidecar multi-track configuration', () => {
  let fakePlayer: FakeWebSdkPlayer;

  beforeEach(() => {
    fakePlayer = new FakeWebSdkPlayer({ accountId: '5420904993001' });
  });

  const resolveSource = async () => {
    const req = fakePlayer.playbackApiRequests[0];
    await act(async () => {
      req.resolve({ id: 'video-123' });
    });
  };

  it('attaches every valid track and emits configured per track', async () => {
    const onSidecarTrackStatus = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        sidecarTracks={[
          { url: 'https://example.com/en.vtt', language: 'en', label: 'English' },
          { url: 'https://example.com/es.vtt', language: 'es' },
        ]}
        onSidecarTrackStatus={onSidecarTrackStatus}
        playerFactory={() => fakePlayer}
      />,
    );
    await resolveSource();

    expect(fakePlayer.addedTextTracks).toHaveLength(2);
    expect(fakePlayer.addedTextTracks[0]).toMatchObject({
      id: 'sidecar-en',
      language: 'en',
      label: 'English',
    });
    expect(fakePlayer.addedTextTracks[1]).toMatchObject({
      id: 'sidecar-es',
      language: 'es',
      label: 'es',
    });
    const configuredEvents = (
      onSidecarTrackStatus.mock.calls as [ { nativeEvent: { status: string; language: string } } ][]
    )
      .map(call => call[0].nativeEvent)
      .filter(event => event.status === 'configured');
    expect(configuredEvents.map(event => event.language)).toEqual(['en', 'es']);
  });

  it('rejects invalid tracks individually without blocking valid ones', async () => {
    const onSidecarTrackStatus = jest.fn();
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        sidecarTracks={[
          { url: 'http://insecure.example/en.vtt', language: 'en' },
          { url: 'https://example.com/es.vtt', language: 'es' },
          { url: 'https://example.com/dup.vtt', language: 'ES' },
          { url: 'https://example.com/de.vtt', language: 'en-' },
        ]}
        onSidecarTrackStatus={onSidecarTrackStatus}
        playerFactory={() => fakePlayer}
      />,
    );
    await resolveSource();

    expect(fakePlayer.addedTextTracks).toHaveLength(1);
    expect(fakePlayer.addedTextTracks[0]).toMatchObject({
      id: 'sidecar-es',
    });
    const failedEvents = (
      onSidecarTrackStatus.mock.calls as [
        { nativeEvent: { status: string; nativeCode: string } },
      ][]
    )
      .map(call => call[0].nativeEvent)
      .filter(event => event.status === 'failed');
    expect(failedEvents.map(event => event.nativeCode)).toEqual([
      'insecure_or_invalid_url',
      'duplicate_language',
      'invalid_language_tag',
    ]);
  });

  it('does not re-add existing sidecar tracks on prop re-application', async () => {
    render(
      <BrightcovePlayerView
        accountId="5420904993001"
        policyKey="test-policy"
        videoId="video-123"
        sidecarTracks={[{ url: 'https://example.com/en.vtt', language: 'en' }]}
        playerFactory={() => fakePlayer}
      />,
    );
    await resolveSource();
    expect(fakePlayer.addedTextTracks).toHaveLength(1);
    await act(async () => {
      fakePlayer.emit('playerCanPlay');
    });
    expect(fakePlayer.addedTextTracks).toHaveLength(1);
  });
});
