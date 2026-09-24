/**
 * @format
 */

import React from 'react';
import ReactTestRenderer, { type ReactTestInstance } from 'react-test-renderer';
import { Text } from 'react-native';

// SafeAreaProvider does not render its children under react-test-renderer
// (it waits for an onLayout that never fires), which would leave the tree
// empty and make any assertion below meaningless. Replace it with a
// pass-through so the app actually renders.
jest.mock('react-native-safe-area-context', () => {
  const ReactModule = require('react');
  const passthrough = ({ children }: { children: React.ReactNode }) =>
    ReactModule.createElement(ReactModule.Fragment, null, children);
  return { SafeAreaProvider: passthrough, SafeAreaView: passthrough };
});

// The native Fabric component cannot render in Jest. Replace it with a stub
// that records the props it was handed and exposes them so a test can drive
// the onReady / onError callbacks exactly as the native side would.
type PlayerProps = {
  accountId: string;
  policyKey: string;
  videoId: string;
  autoPlay?: boolean;
  adTagUrl?: string;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onAdStarted?: (e: { nativeEvent: { adTitle: string; duration: number } }) => void;
  onAdCompleted?: (e: { nativeEvent: { adTitle: string; duration: number } }) => void;
  onAdBreakStarted?: (e: { nativeEvent: { index: number } }) => void;
  onAdBreakEnded?: (e: { nativeEvent: { index: number } }) => void;
  onAllAdsCompleted?: (e: { nativeEvent: { completed: boolean } }) => void;
  onAdError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
};

let lastPlayerProps: PlayerProps | undefined;

jest.mock('@brightcove/react-native-player', () => ({
  BrightcovePlayerView: (props: PlayerProps) => {
    lastPlayerProps = props;
    return null;
  },
}));

import App from '../App';

const statusText = (tree: ReactTestInstance): string =>
  tree
    .findAllByType(Text)
    .map(node => node.props.children)
    .filter((child): child is string => typeof child === 'string')
    .join(' ');

beforeEach(() => {
  lastPlayerProps = undefined;
});

test('hands the demo account/policy/video and autoPlay to the native view', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps).toBeDefined();
  expect(lastPlayerProps!.accountId).toBe('5420904993001');
  expect(lastPlayerProps!.videoId).toBe('5421538222001');
  expect(lastPlayerProps!.policyKey).toEqual(expect.stringContaining('BCpk'));
  expect(lastPlayerProps!.autoPlay).toBe(true);
  // The VMAP ad tag must reach the native view, or no ads would be requested.
  expect(lastPlayerProps!.adTagUrl).toEqual(expect.stringContaining('output=vmap'));
});

test('starts in the loading state', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(statusText(renderer.root)).toContain('Loading');
});

test('onReady moves the UI to the ready state with the video id', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: '5421538222001' } });
  });

  expect(statusText(renderer.root)).toContain('Ready video 5421538222001');
});

test('onAdStarted moves the UI into the ad state with the ad title', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAdStarted?.({
      nativeEvent: { adTitle: 'Sample Preroll', duration: 10 },
    });
  });

  expect(statusText(renderer.root)).toContain('Ad playing: Sample Preroll');
});

test('onAdBreakStarted reports an ad break', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAdBreakStarted?.({ nativeEvent: { index: -1 } });
  });

  expect(statusText(renderer.root)).toContain('Ad break started');
});

test('onAdCompleted reports the individual ad as completed', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAdCompleted?.({
      nativeEvent: { adTitle: 'Sample Preroll', duration: 10 },
    });
  });

  expect(statusText(renderer.root)).toContain('Ad completed');
});

test('onAllAdsCompleted reports the whole schedule finished', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAllAdsCompleted?.({ nativeEvent: { completed: true } });
  });

  expect(statusText(renderer.root)).toContain('All ads completed');
});

test('onAdError surfaces the ad error without claiming content failed', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAdError?.({
      nativeEvent: {
        code: 'load',
        message: 'VAST could not be fetched',
        nativeCode: 'IMAErrorDomain:1005',
      },
    });
  });

  const text = statusText(renderer.root);
  expect(text).toContain('Ad error (load)');
  expect(text).toContain('VAST could not be fetched');
});

test('onError surfaces the normalized code and message', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onError?.({
      nativeEvent: {
        code: 'not_found',
        message: 'Unable to retrieve the Brightcove video',
        nativeCode: 'catalog_error',
      },
    });
  });

  const text = statusText(renderer.root);
  expect(text).toContain('not_found');
  expect(text).toContain('Unable to retrieve the Brightcove video');
});
