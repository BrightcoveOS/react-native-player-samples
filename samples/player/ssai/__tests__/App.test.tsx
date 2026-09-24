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
  adConfigId?: string;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onAdStarted?: (e: { nativeEvent: { adTitle: string; duration: number } }) => void;
  onAdBreakStarted?: (e: { nativeEvent: { index: number } }) => void;
  onAdBreakEnded?: (e: { nativeEvent: { index: number } }) => void;
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
  expect(lastPlayerProps!.accountId).toBe('5434391461001');
  expect(lastPlayerProps!.videoId).toBe('5702141808001');
  expect(lastPlayerProps!.policyKey).toEqual(expect.stringContaining('BCpk'));
  expect(lastPlayerProps!.autoPlay).toBe(true);
  // The ad-config id must reach the native view, or no SSAI stream is requested.
  expect(lastPlayerProps!.adConfigId).toBe('0e0bbcd1-bba0-45bf-a986-1288e5f9fc85');
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
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: '5702141808001' } });
  });

  expect(statusText(renderer.root)).toContain('Ready video 5702141808001');
});

test('onAdStarted moves the UI into the ad state with the ad title', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAdStarted?.({
      nativeEvent: { adTitle: 'Stitched Preroll', duration: 15 },
    });
  });

  expect(statusText(renderer.root)).toContain('Ad playing: Stitched Preroll');
});

test('onAdBreakEnded returns the UI to content', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAdBreakEnded?.({ nativeEvent: { index: -1 } });
  });

  expect(statusText(renderer.root)).toContain('Content resumed');
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
