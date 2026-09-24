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
// the onReady / onError / playback-events / live callbacks exactly as the
// native side would.
type PlayerProps = {
  accountId: string;
  policyKey: string;
  videoId: string;
  autoPlay?: boolean;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onPlay?: () => void;
  onPause?: () => void;
  onEnded?: () => void;
  onProgress?: (e: {
    nativeEvent: { currentTime: number; duration: number };
  }) => void;
  onLiveStatus?: (e: {
    nativeEvent: { isLive: boolean; hasDvr: boolean };
  }) => void;
  onSeekableRangesChanged?: (e: {
    nativeEvent: {
      ranges: { startTime: number; endTime: number }[];
      liveEdge: number;
    };
  }) => void;
};

let lastPlayerProps: PlayerProps | undefined;

jest.mock('@brightcove/react-native-player', () => {
  const ReactModule = require('react');
  return {
    BrightcovePlayerView: ReactModule.forwardRef(
      (props: PlayerProps, ref: { current: object | null } | null) => {
        lastPlayerProps = props;
        if (ref) ref.current = {};
        return null;
      },
    ),
    PlayerCommands: { seekToLiveEdge: jest.fn() },
  };
});

import App from '../App';

const mockSeekToLiveEdge = jest.requireMock(
  '@brightcove/react-native-player',
).PlayerCommands.seekToLiveEdge as jest.Mock;

// A <Text> node's children prop can be a single string/number, or an array of
// strings/numbers/booleans/null (e.g. `{a} / {b}` renders three children).
// Flatten either shape into one string per node before joining across nodes,
// so a chip built from multiple interpolated children is not silently
// dropped from the search text.
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

// Count the Go live control by its testID on a pressable, not by text (the
// header description also contains the words "Go live").
const goLiveCount = (
  renderer: ReactTestRenderer.ReactTestRenderer,
): number =>
  renderer.root.findAll(
    node => node.props.testID === 'go-live' && typeof node.props.onPress === 'function',
  ).length;

beforeEach(() => {
  lastPlayerProps = undefined;
  mockSeekToLiveEdge.mockClear();
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
});

test('switching to the live source swaps the video id and clears live state', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  // The live slot ships as a placeholder: selecting it shows the configuration
  // note instead of mounting a player with an unconfigured id.
  const liveButton = renderer.root.findByProps({ testID: 'source-live' });
  await ReactTestRenderer.act(() => {
    liveButton.props.onPress();
  });

  expect(statusText(renderer.root)).toContain('placeholder');
  expect(
    renderer.root.findAllByProps({ testID: 'go-live' }),
  ).toHaveLength(0);

  // Switching back restores the on-demand player.
  const vodButton = renderer.root.findByProps({ testID: 'source-vod' });
  await ReactTestRenderer.act(() => {
    vodButton.props.onPress();
  });
  expect(lastPlayerProps!.videoId).toBe('5421538222001');
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

test('starts with the playback-state chip showing not started', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(statusText(renderer.root)).toContain('Not started');
});

test('onPlay and onPause update the playback-state chip', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPlay?.();
  });
  expect(statusText(renderer.root)).toContain('playing');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPause?.();
  });
  expect(statusText(renderer.root)).toContain('paused');
});

test('onEnded updates the playback-state chip', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onEnded?.();
  });

  expect(statusText(renderer.root)).toContain('ended');
});

test('onProgress formats the current time and duration as minutes:seconds', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onProgress?.({
      nativeEvent: { currentTime: 75, duration: 630 },
    });
  });

  expect(statusText(renderer.root)).toContain('1:15');
  expect(statusText(renderer.root)).toContain('10:30');
});

test('onLiveStatus reports on-demand content', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: false, hasDvr: false },
    });
  });

  expect(statusText(renderer.root)).toContain('On-demand');
});

test('onLiveStatus reports a live stream with DVR', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: true, hasDvr: true },
    });
  });

  expect(statusText(renderer.root)).toContain('Live (DVR)');
});

test('onSeekableRangesChanged renders the live window and edge', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onSeekableRangesChanged?.({
      nativeEvent: {
        ranges: [{ startTime: 120, endTime: 600 }],
        liveEdge: 600,
      },
    });
  });

  const text = statusText(renderer.root);
  expect(text).toContain('Seekable: 2:00–10:00');
  expect(text).toContain('Live edge: 10:00');
});

test('onSeekableRangesChanged handles multiple discontinuous ranges and moving live edge', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: true, hasDvr: true },
    });
    lastPlayerProps!.onSeekableRangesChanged?.({
      nativeEvent: {
        ranges: [
          { startTime: 60, endTime: 180 },
          { startTime: 240, endTime: 600 },
        ],
        liveEdge: 600,
      },
    });
  });

  let text = statusText(renderer.root);
  expect(text).toContain('Seekable: 1:00–3:00');
  expect(text).toContain('Live edge: 10:00');
  expect(goLiveCount(renderer)).toBe(1);

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onSeekableRangesChanged?.({
      nativeEvent: {
        ranges: [
          { startTime: 60, endTime: 180 },
          { startTime: 240, endTime: 720 },
        ],
        liveEdge: 720,
      },
    });
  });

  text = statusText(renderer.root);
  expect(text).toContain('Seekable: 1:00–3:00');
  expect(text).toContain('Live edge: 12:00');
});

test('Go live dispatches the native live-edge command for DVR content', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: true, hasDvr: true },
    });
    lastPlayerProps!.onSeekableRangesChanged?.({
      nativeEvent: {
        ranges: [{ startTime: 120, endTime: 600 }],
        liveEdge: 600,
      },
    });
  });

  const goLiveButton = renderer.root.find(
    node => node.props.testID === 'go-live',
  );
  await ReactTestRenderer.act(() => {
    goLiveButton.props.onPress();
  });

  expect(mockSeekToLiveEdge).toHaveBeenCalledTimes(1);
});

test.each([
  { label: 'VOD', isLive: false, hasDvr: false },
  { label: 'plain live', isLive: true, hasDvr: false },
])('$label does not render Go live', async ({ isLive, hasDvr }) => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive, hasDvr },
    });
  });

  expect(goLiveCount(renderer)).toBe(0);
});

test.each([
  { label: 'zero-length range', ranges: [{ startTime: 100, endTime: 100 }], liveEdge: 100 },
  { label: 'inverted range', ranges: [{ startTime: 200, endTime: 100 }], liveEdge: 200 },
  { label: 'negative start range', ranges: [{ startTime: -10, endTime: 100 }], liveEdge: 100 },
  { label: 'zero live edge', ranges: [{ startTime: 0, endTime: 100 }], liveEdge: 0 },
  { label: 'empty ranges', ranges: [], liveEdge: 100 },
])('$label does not render Go live even when hasDvr is true', async ({ ranges, liveEdge }) => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: true, hasDvr: true },
    });
    lastPlayerProps!.onSeekableRangesChanged?.({
      nativeEvent: { ranges, liveEdge },
    });
  });

  expect(goLiveCount(renderer)).toBe(0);
});

test('source reset precedes the next ready-time live classification', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: true, hasDvr: true },
    });
    lastPlayerProps!.onSeekableRangesChanged?.({
      nativeEvent: {
        ranges: [{ startTime: 120, endTime: 600 }],
        liveEdge: 600,
      },
    });
  });

  expect(statusText(renderer.root)).toContain('Live (DVR)');
  expect(goLiveCount(renderer)).toBe(1);

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: false, hasDvr: false },
    });
    lastPlayerProps!.onSeekableRangesChanged?.({
      nativeEvent: {
        ranges: [],
        liveEdge: 0,
      },
    });
  });

  expect(statusText(renderer.root)).toContain('On-demand');
  expect(statusText(renderer.root)).toContain('Seekable window unavailable');
  expect(goLiveCount(renderer)).toBe(0);

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: 'new-video' } });
  });
  expect(statusText(renderer.root)).toContain('Ready video new-video');
  expect(statusText(renderer.root)).toContain('On-demand');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({
      nativeEvent: { isLive: true, hasDvr: true },
    });
  });
  expect(statusText(renderer.root)).toContain('Live (DVR)');
});

test('ordering: onReady moves to ready before onLiveStatus updates stream type', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(statusText(renderer.root)).toContain('Loading');
  expect(statusText(renderer.root)).toContain('Live status pending');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: '5421538222001' } });
  });
  expect(statusText(renderer.root)).toContain('Ready video 5421538222001');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onLiveStatus?.({ nativeEvent: { isLive: true, hasDvr: true } });
  });
  expect(statusText(renderer.root)).toContain('Live (DVR)');
});
