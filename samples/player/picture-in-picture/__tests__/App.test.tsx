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
  pictureInPictureEnabled?: boolean;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onPictureInPictureModeChanged?: (e: {
    nativeEvent: { active: boolean };
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
  expect(lastPlayerProps!.accountId).toBe('6415855237001');
  expect(lastPlayerProps!.videoId).toBe('6393164822112');
  expect(lastPlayerProps!.policyKey).toEqual(expect.stringContaining('BCpk'));
  expect(lastPlayerProps!.autoPlay).toBe(true);
  expect(lastPlayerProps!.pictureInPictureEnabled).toBe(true);
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
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: '6393164822112' } });
  });

  expect(statusText(renderer.root)).toContain('Ready video 6393164822112');
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

test('reflects Picture-in-Picture enter/exit from the native event', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(statusText(renderer.root)).toContain('Picture-in-Picture inactive');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPictureInPictureModeChanged?.({
      nativeEvent: { active: true },
    });
  });
  expect(statusText(renderer.root)).toContain('Picture-in-Picture active');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPictureInPictureModeChanged?.({
      nativeEvent: { active: false },
    });
  });
  expect(statusText(renderer.root)).toContain('Picture-in-Picture inactive');
});
