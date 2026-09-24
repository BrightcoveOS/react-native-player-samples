import React from 'react';
import ReactTestRenderer, { type ReactTestInstance } from 'react-test-renderer';
import { Text } from 'react-native';

jest.mock('react-native-safe-area-context', () => {
  const ReactModule = require('react');
  const passthrough = ({ children }: { children: React.ReactNode }) =>
    ReactModule.createElement(ReactModule.Fragment, null, children);
  return { SafeAreaProvider: passthrough, SafeAreaView: passthrough };
});

type PlayerProps = {
  accountId: string;
  policyKey: string;
  videoId: string;
  autoPlay?: boolean;
  onReady?: (event: { nativeEvent: { videoId: string } }) => void;
  onError?: (event: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onFullscreenChanged?: (event: { nativeEvent: { active: boolean } }) => void;
  style?: unknown;
};

let lastPlayerProps: PlayerProps | undefined;

const mockEnterFullscreen = jest.fn();
const mockExitFullscreen = jest.fn();

jest.mock('@brightcove/react-native-player', () => {
  const ReactModule = require('react');
  return {
    BrightcovePlayerView: ReactModule.forwardRef((props: PlayerProps, ref: React.RefObject<unknown>) => {
      lastPlayerProps = props;
      ReactModule.useImperativeHandle(ref, () => ({}), []);
      return null;
    }),
    PlayerCommands: {
      enterFullscreen: (...args: unknown[]) => mockEnterFullscreen(...args),
      exitFullscreen: (...args: unknown[]) => mockExitFullscreen(...args),
    },
  };
});

import App from '../App';

const text = (tree: ReactTestInstance): string =>
  tree
    .findAllByType(Text)
    .map(node => node.props.children)
    .filter((child): child is string => typeof child === 'string')
    .join(' ');

beforeEach(() => {
  lastPlayerProps = undefined;
  mockEnterFullscreen.mockClear();
  mockExitFullscreen.mockClear();
});

test('hands the demo account/video and fullscreen callback to the native view', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps).toMatchObject({
    accountId: '6415855237001',
    policyKey: expect.stringContaining('BCpk'),
    videoId: '6393164822112',
    autoPlay: true,
  });
  expect(lastPlayerProps!.onFullscreenChanged).toEqual(expect.any(Function));
  expect(lastPlayerProps!.style).toEqual(expect.arrayContaining([
    expect.objectContaining({ aspectRatio: 16 / 9, width: '100%' }),
  ]));
});

test('starts in windowed mode', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(text(renderer.root)).toContain('Windowed');
  expect(text(renderer.root)).toContain('Brightcove player screen mode');
});

test('completed fullscreen transitions update React state', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onFullscreenChanged?.({ nativeEvent: { active: true } });
  });
  expect(text(renderer.root)).toContain('Exit fullscreen');
  expect(lastPlayerProps!.style).toEqual(expect.arrayContaining([
    expect.objectContaining({ width: expect.any(Number), height: expect.any(Number) }),
  ]));

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onFullscreenChanged?.({ nativeEvent: { active: false } });
  });
  expect(text(renderer.root)).toContain('Windowed');
  expect(lastPlayerProps!.style).toEqual(expect.arrayContaining([
    expect.objectContaining({ aspectRatio: 16 / 9, width: '100%' }),
  ]));
});

test('fullscreen button dispatches enter and exit commands', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  const button = renderer.root.findAllByType(require('react-native').Button)[0];
  await ReactTestRenderer.act(() => {
    button.props.onPress();
  });
  expect(mockEnterFullscreen).toHaveBeenCalledTimes(1);

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onFullscreenChanged?.({ nativeEvent: { active: true } });
  });
  const exitButton = renderer.root.findByType(require('react-native').Button);
  await ReactTestRenderer.act(() => {
    exitButton.props.onPress();
  });
  expect(mockExitFullscreen).toHaveBeenCalledTimes(1);
});

test('fullscreen state does not claim orientation changed', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onFullscreenChanged?.({ nativeEvent: { active: true } });
  });

  expect(text(renderer.root)).toContain('Exit fullscreen');
});
