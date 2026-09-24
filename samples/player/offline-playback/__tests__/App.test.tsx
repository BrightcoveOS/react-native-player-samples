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
  offlineSourceId?: string;
  autoPlay?: boolean;
  onReady?: (event: { nativeEvent: { videoId: string } }) => void;
  onError?: (event: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
};

type Download = {
  localId: string;
  videoId: string;
  state: 'queued' | 'completed' | 'removed';
  bytesDownloaded: number;
};

let lastPlayerProps: PlayerProps | undefined;
let mockDownloadListener: ((download: Download) => void) | undefined;
const mockRequestDownload = jest.fn();
const mockRequestDownloads = jest.fn();
const mockRemoveDownload = jest.fn();
const mockListDownloads = jest.fn();

jest.mock('@brightcove/react-native-player', () => ({
  BrightcovePlayerView: (props: PlayerProps) => {
    lastPlayerProps = props;
    return null;
  },
  OfflinePlayback: {
    requestDownload: (...args: unknown[]) => mockRequestDownload(...args),
    requestDownloads: (...args: unknown[]) => mockRequestDownloads(...args),
    removeDownload: (...args: unknown[]) => mockRemoveDownload(...args),
    listDownloads: () => mockListDownloads(),
    addDownloadChangedListener: (listener: (download: Download) => void) => {
      mockDownloadListener = listener;
      return { remove: jest.fn() };
    },
  },
}));

import App from '../App';

const text = (tree: ReactTestInstance): string =>
  tree
    .findAllByType(Text)
    .map(node => node.props.children)
    .filter((child): child is string => typeof child === 'string')
    .join(' ');

const textOfNode = (children: unknown): string => {
  if (Array.isArray(children)) return children.map(textOfNode).join('');
  return typeof children === 'string' || typeof children === 'number'
    ? String(children)
    : '';
};

const press = async (tree: ReactTestInstance, label: string) => {
  const button = tree.findAll(
    node =>
      typeof node.props.onPress === 'function' &&
      node.findAllByType(Text).some(child => textOfNode(child.props.children) === label),
  )[0];
  expect(button).toBeDefined();
  await ReactTestRenderer.act(async () => {
    await button!.props.onPress();
  });
};

beforeEach(() => {
  lastPlayerProps = undefined;
  mockDownloadListener = undefined;
  mockListDownloads.mockResolvedValue([]);
  mockRequestDownload.mockResolvedValue({
    localId: '1823870923251322266',
    videoId: '1823870923251322266',
    state: 'queued',
    bytesDownloaded: 0,
  });
  mockRequestDownloads.mockResolvedValue([]);
  mockRemoveDownload.mockResolvedValue(undefined);
});

test('restores persisted downloads and renders the online source by default', async () => {
  await ReactTestRenderer.act(async () => {
    ReactTestRenderer.create(<App />);
  });

  expect(mockListDownloads).toHaveBeenCalledTimes(1);
  expect(lastPlayerProps).toMatchObject({
    accountId: '4800266849001',
    videoId: '1823870923251322266',
    offlineSourceId: '',
    autoPlay: true,
  });
});

test('Download selected requests one durable native item', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await press(renderer.root, 'Download selected');

  expect(mockRequestDownload).toHaveBeenCalledWith(
    expect.objectContaining({
      accountId: '4800266849001',
      videoId: '1823870923251322266',
    }),
  );
  expect(text(renderer.root)).toContain('queued');
});

test('Queue 2 downloads requests each selected video', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await press(renderer.root, 'Queue 2 downloads');

  expect(mockRequestDownloads).toHaveBeenCalledWith([
    expect.objectContaining({ videoId: '1823870923251322266' }),
    expect.objectContaining({ videoId: '1767327231984365476' }),
  ]);
});

test('a completed item can become the local player source', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(async () => {
    mockDownloadListener?.({
      localId: 'local-token',
      videoId: '1823870923251322266',
      state: 'completed',
      bytesDownloaded: 42,
    });
  });
  await press(renderer.root, 'Play offline');

  expect(lastPlayerProps).toMatchObject({
    videoId: '',
    offlineSourceId: 'local-token',
  });
});

test('Play online releases the local player source before removal', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });
  await ReactTestRenderer.act(async () => {
    mockDownloadListener?.({
      localId: 'local-token',
      videoId: '1823870923251322266',
      state: 'completed',
      bytesDownloaded: 42,
    });
  });
  await press(renderer.root, 'Play offline');
  await press(renderer.root, 'Play online');

  expect(lastPlayerProps).toMatchObject({
    videoId: '1823870923251322266',
    offlineSourceId: '',
  });
});

test('a removed active item returns the player to the online source', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(async () => {
    mockDownloadListener?.({
      localId: 'local-token',
      videoId: '1823870923251322266',
      state: 'completed',
      bytesDownloaded: 42,
    });
  });
  await press(renderer.root, 'Play offline');
  await ReactTestRenderer.act(async () => {
    mockDownloadListener?.({
      localId: 'local-token',
    videoId: '1823870923251322266',
      state: 'removed',
      bytesDownloaded: 0,
    });
  });

  expect(lastPlayerProps).toMatchObject({
    videoId: '1823870923251322266',
    offlineSourceId: '',
  });
});
