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
  playbackRate?: number;
  audioTrackId?: string;
  volume?: number;
  muted?: boolean;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onAudioTracksAvailable?: (e: {
    nativeEvent: {
      tracks: { id: string; language: string; label: string }[];
    };
  }) => void;
  onAudioTrackChanged?: (e: {
    nativeEvent: { id: string; language: string };
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

const textContent = (children: unknown): string => {
  if (Array.isArray(children)) {
    return children.map(textContent).join('');
  }
  return typeof children === 'string' || typeof children === 'number'
    ? String(children)
    : '';
};

const statusText = (tree: ReactTestInstance): string =>
  tree.findAllByType(Text).map(node => textContent(node.props.children)).join(' ');

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
  expect(lastPlayerProps!.playbackRate).toBe(1);
  expect(lastPlayerProps!.volume).toBe(1);
  expect(lastPlayerProps!.muted).toBe(false);
});


test('updates volume and muted props from the sample controls', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    renderer.root.findByProps({ testID: 'volume-0.5' }).props.onPress();
  });
  expect(lastPlayerProps!.volume).toBe(0.5);

  await ReactTestRenderer.act(() => {
    renderer.root.findByProps({ testID: 'mute-toggle' }).props.onPress();
  });
  expect(lastPlayerProps!.muted).toBe(true);
  expect(statusText(renderer.root)).toContain('Volume: 50%');
  expect(statusText(renderer.root)).toContain('Muted: Yes');

  await ReactTestRenderer.act(() => {
    renderer.root.findByProps({ testID: 'mute-toggle' }).props.onPress();
  });
  expect(lastPlayerProps!.muted).toBe(false);
});

test('updates playbackRate prop from the sample rate chips', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps!.playbackRate).toBe(1);

  await ReactTestRenderer.act(() => {
    renderer.root.findByProps({ testID: 'rate-0.5' }).props.onPress();
  });
  expect(lastPlayerProps!.playbackRate).toBe(0.5);

  await ReactTestRenderer.act(() => {
    renderer.root.findByProps({ testID: 'rate-2' }).props.onPress();
  });
  expect(lastPlayerProps!.playbackRate).toBe(2);

  await ReactTestRenderer.act(() => {
    renderer.root.findByProps({ testID: 'rate-1.5' }).props.onPress();
  });
  expect(lastPlayerProps!.playbackRate).toBe(1.5);
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

test('renders available audio tracks and updates audioTrackId on selection', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: {
        tracks: [
          { id: '1:0', language: 'en', label: 'en (Main)' },
          { id: '1:1', language: 'en', label: 'en (Alternate)' },
        ],
      },
    });
  });

  const button = renderer.root.findByProps({ testID: 'audio-track-1:1' });
  expect(button).toBeDefined();

  await ReactTestRenderer.act(() => {
    button.props.onPress();
  });

  expect(lastPlayerProps!.audioTrackId).toBe('1:1');
  expect(statusText(renderer.root)).not.toContain('Active: 1:1');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTrackChanged?.({
      nativeEvent: { id: '1:1', language: 'en' },
    });
  });

  expect(statusText(renderer.root)).toContain('Active: 1:1');
});

test('handles source change with authoritative empty tracks and active track reset', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: {
        tracks: [
          { id: '1:0', language: 'en', label: 'en (Main)' },
          { id: '1:1', language: 'en', label: 'en (Alternate)' },
        ],
      },
    });
    lastPlayerProps!.onAudioTrackChanged?.({
      nativeEvent: { id: '1:0', language: 'en' },
    });
  });

  expect(statusText(renderer.root)).toContain('Active: 1:0');

  // Simulate source reset: authoritative empty tracks and empty active track
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: { tracks: [] },
    });
    lastPlayerProps!.onAudioTrackChanged?.({
      nativeEvent: { id: '', language: '' },
    });
  });

  expect(statusText(renderer.root)).toContain('No audio tracks available');
  expect(statusText(renderer.root)).not.toContain('Active:');
});

test('does not reuse a source A id for a same-label source B track', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: {
        tracks: [{ id: '1:0', language: 'en', label: 'English' }],
      },
    });
  });

  const sourceATrack = renderer.root.findByProps({ testID: 'audio-track-1:0' });
  await ReactTestRenderer.act(() => {
    sourceATrack.props.onPress();
  });
  expect(lastPlayerProps!.audioTrackId).toBe('1:0');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({ nativeEvent: { tracks: [] } });
    lastPlayerProps!.onAudioTrackChanged?.({
      nativeEvent: { id: '', language: '' },
    });
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: {
        tracks: [{ id: '2:0', language: 'en', label: 'English' }],
      },
    });
  });

  expect(lastPlayerProps!.audioTrackId).toBe('1:0');
  expect(renderer.root.findByProps({ testID: 'audio-track-2:0' })).toBeDefined();
  expect(statusText(renderer.root)).not.toContain('Active: 1:0');
});

test('keeps same-language role variants independently selectable by opaque ids', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: {
        tracks: [
          { id: '4:0', language: 'en', label: 'en (Main)' },
          { id: '4:1', language: 'en', label: 'en (Alternate)' },
        ],
      },
    });
  });

  expect(renderer.root.findByProps({ testID: 'audio-track-4:0' })).toBeDefined();
  expect(renderer.root.findByProps({ testID: 'audio-track-4:1' })).toBeDefined();

  await ReactTestRenderer.act(() => {
    renderer.root.findByProps({ testID: 'audio-track-4:1' }).props.onPress();
  });

  expect(lastPlayerProps!.audioTrackId).toBe('4:1');
});

test('displays default active track reported on initial load without explicit selection', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps!.audioTrackId).toBe('');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: {
        tracks: [
          { id: '0:0', language: 'en', label: 'English' },
          { id: '0:1', language: 'es', label: 'Spanish' },
        ],
      },
    });
    lastPlayerProps!.onAudioTrackChanged?.({
      nativeEvent: { id: '0:0', language: 'en' },
    });
  });

  expect(statusText(renderer.root)).toContain('Active: 0:0');
});

test('clears the reported active track after an invalid requested id', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTracksAvailable?.({
      nativeEvent: {
        tracks: [{ id: '5:0', language: 'en', label: 'English' }],
      },
    });
    lastPlayerProps!.onAudioTrackChanged?.({
      nativeEvent: { id: '5:0', language: 'en' },
    });
  });

  expect(statusText(renderer.root)).toContain('Active: 5:0');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onAudioTrackChanged?.({
      nativeEvent: { id: '', language: '' },
    });
  });

  expect(statusText(renderer.root)).not.toContain('Active:');
});
