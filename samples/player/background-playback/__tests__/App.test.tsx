/**
 * @format
 */

import React from 'react';
import ReactTestRenderer, { type ReactTestInstance } from 'react-test-renderer';
import { PermissionsAndroid, Platform, Text } from 'react-native';

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
// the onReady / onError / playback events exactly as the native side would.
type PlayerProps = {
  accountId: string;
  policyKey: string;
  videoId: string;
  autoPlay?: boolean;
  backgroundPlaybackEnabled?: boolean;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onPlay?: () => void;
  onPause?: () => void;
  onEnded?: () => void;
  onProgress?: (e: { nativeEvent: { currentTime: number; duration: number } }) => void;
};

let lastPlayerProps: PlayerProps | undefined;

jest.mock('@brightcove/react-native-player', () => ({
  BrightcovePlayerView: (props: PlayerProps) => {
    lastPlayerProps = props;
    return null;
  },
}));

import App from '../App';

const textOfNode = (children: unknown): string => {
  if (Array.isArray(children)) {
    return children.map(textOfNode).join('');
  }
  return typeof children === 'string' || typeof children === 'number'
    ? String(children)
    : '';
};

const statusText = (tree: ReactTestInstance): string =>
  tree
    .findAllByType(Text)
    .map(node => textOfNode(node.props.children))
    .join(' ');

beforeEach(() => {
  lastPlayerProps = undefined;
  jest.clearAllMocks();
});

test('hands the demo account/policy/video, autoPlay, and backgroundPlaybackEnabled to the native view', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps).toBeDefined();
  expect(lastPlayerProps!.accountId).toBe('5420904993001');
  expect(lastPlayerProps!.videoId).toBe('5421538222001');
  expect(lastPlayerProps!.policyKey).toEqual(expect.stringContaining('BCpk'));
  expect(lastPlayerProps!.autoPlay).toBe(true);
  expect(lastPlayerProps!.backgroundPlaybackEnabled).toBe(true);
});

test('starts in the loading state', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(statusText(renderer.root)).toContain('Loading demo video');
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

test('playback events update the state and progress chips', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPlay?.();
    lastPlayerProps!.onProgress?.({
      nativeEvent: {
        currentTime: 30,
        duration: 120,
      },
    });
  });

  const text = statusText(renderer.root);
  expect(text).toContain('playing');
  expect(text).toContain('0:30 / 2:00');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPause?.();
  });

  expect(statusText(renderer.root)).toContain('paused');
});

test('disables background playback when Android notification permission is denied', async () => {
  const originalOs = Platform.OS;
  const originalVersion = Platform.Version;
  Object.defineProperty(Platform, 'OS', { configurable: true, value: 'android' });
  Object.defineProperty(Platform, 'Version', { configurable: true, value: 33 });
  const permissionSpy = jest
    .spyOn(PermissionsAndroid, 'request')
    .mockResolvedValue(PermissionsAndroid.RESULTS.DENIED);
  let renderer!: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  expect(permissionSpy).toHaveBeenCalledWith(
    PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS,
  );
  expect(lastPlayerProps!.backgroundPlaybackEnabled).toBe(false);
  expect(statusText(renderer.root)).toContain(
    'Notification permission denied — lock-screen controls unavailable',
  );

  permissionSpy.mockRestore();
  Object.defineProperty(Platform, 'OS', { configurable: true, value: originalOs });
  Object.defineProperty(Platform, 'Version', {
    configurable: true,
    value: originalVersion,
  });
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
