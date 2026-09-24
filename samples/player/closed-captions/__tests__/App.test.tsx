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
// that records the props it was handed so a test can both assert what reaches
// the native view and drive the caption callbacks exactly as native would.
type CaptionTrack = { id: string; language: string; label: string };
type PlayerProps = {
  accountId: string;
  policyKey: string;
  videoId: string;
  autoPlay?: boolean;
  captionsEnabled?: boolean;
  captionTrackId?: string;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onCaptionsAvailable?: (e: {
    nativeEvent: { tracks: CaptionTrack[] };
  }) => void;
  onCaptionTrackChanged?: (e: {
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

// Flatten every Text node's children (which may be strings or arrays of
// strings, e.g. `{status}{active ? ... : ''}`) into one searchable string.
const statusText = (tree: ReactTestInstance): string => {
  const parts: string[] = [];
  const collect = (child: unknown): void => {
    if (typeof child === 'string') {
      parts.push(child);
    } else if (Array.isArray(child)) {
      child.forEach(collect);
    }
  };
  tree.findAllByType(Text).forEach(node => collect(node.props.children));
  return parts.join(' ');
};

// A chip is a pressable element (it has an onPress) that contains a Text whose
// content is `label`. Matched by the onPress prop rather than the Pressable
// type, which react-test-renderer does not resolve to a single findable node.
const chipByLabel = (
  tree: ReactTestInstance,
  label: string,
): ReactTestInstance =>
  tree
    .findAll(
      node =>
        typeof node.props.onPress === 'function' &&
        node
          .findAllByType(Text)
          .some(t => t.props.children === label),
    )
    .at(-1)!;

// Is the chip with this label currently highlighted (active)? The sample marks
// the active chip with a distinct style; detect it by the chipActive style
// being present on the pressable. Falls back to reading the active flag the
// chip renders. Asserting this (not just status text) proves the controlled
// props and the UI agree — the point of the native-menu-sync fix.
const chipIsActive = (tree: ReactTestInstance, label: string): boolean => {
  const chip = chipByLabel(tree, label);
  const styles = ([] as unknown[]).concat(chip.props.style ?? []);
  // The active chip style sets a near-black background (#12141a); match on that marker.
  return styles.some(
    s => s && typeof s === 'object' && (s as { backgroundColor?: string }).backgroundColor === '#12141a',
  );
};

// Two same-language variants to prove id (not language) is the identity: both
// are "en" but distinct tracks with distinct ids and labels.
const AVAILABLE_TRACKS: CaptionTrack[] = [
  { id: '0', language: 'en', label: 'English' },
  { id: '1', language: 'en', label: 'English SDH' },
  { id: '2', language: 'es', label: 'Spanish' },
  { id: '3', language: 'ja', label: 'Japanese' },
];

beforeEach(() => {
  lastPlayerProps = undefined;
});

test('hands the demo account/policy/video to the native view, captions off', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps).toBeDefined();
  expect(lastPlayerProps!.accountId).toBe('6415855237001');
  expect(lastPlayerProps!.videoId).toBe('6393164822112');
  expect(lastPlayerProps!.policyKey).toEqual(expect.stringContaining('BCpk'));
  expect(lastPlayerProps!.captionsEnabled).toBe(false);
  expect(lastPlayerProps!.captionTrackId).toBe('');
});

test('starts in the loading state', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(statusText(renderer.root)).toContain('Loading');
});

test('onCaptionsAvailable renders a chip per track', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionsAvailable?.({
      nativeEvent: { tracks: AVAILABLE_TRACKS },
    });
  });

  // Off plus one per track, including both same-language "en" variants.
  for (const label of ['Off', 'English', 'English SDH', 'Spanish', 'Japanese']) {
    expect(chipByLabel(renderer.root, label)).toBeDefined();
  }
});

test('same-language variants are selectable by distinct id', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionsAvailable?.({
      nativeEvent: { tracks: AVAILABLE_TRACKS },
    });
  });

  // Selecting the second "en" track (English SDH) must send its id (1), not the
  // shared language "en" — proving the second same-language track is reachable.
  await ReactTestRenderer.act(() => {
    chipByLabel(renderer.root, 'English SDH').props.onPress();
  });

  expect(lastPlayerProps!.captionsEnabled).toBe(true);
  expect(lastPlayerProps!.captionTrackId).toBe('1');
  expect(chipIsActive(renderer.root, 'English SDH')).toBe(true);
  expect(chipIsActive(renderer.root, 'English')).toBe(false);
});

test('tapping Off disables captions', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionsAvailable?.({
      nativeEvent: { tracks: AVAILABLE_TRACKS },
    });
  });
  await ReactTestRenderer.act(() => {
    chipByLabel(renderer.root, 'English').props.onPress();
  });
  expect(lastPlayerProps!.captionsEnabled).toBe(true);

  await ReactTestRenderer.act(() => {
    chipByLabel(renderer.root, 'Off').props.onPress();
  });
  expect(lastPlayerProps!.captionsEnabled).toBe(false);
  expect(lastPlayerProps!.captionTrackId).toBe('');
});

test('a native-menu track change syncs the controlled state and active chip', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionsAvailable?.({
      nativeEvent: { tracks: AVAILABLE_TRACKS },
    });
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: '6393164822112' } });
  });

  // Start on Japanese via a chip.
  await ReactTestRenderer.act(() => {
    chipByLabel(renderer.root, 'Japanese').props.onPress();
  });
  expect(chipIsActive(renderer.root, 'Japanese')).toBe(true);

  // Now the user switches to Spanish through the player's OWN caption menu:
  // the authoritative callback fires with the new id. The controlled state and
  // the highlighted chip must follow it — not stay on Japanese.
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionTrackChanged?.({
      nativeEvent: { id: '2', language: 'es' },
    });
  });
  expect(lastPlayerProps!.captionTrackId).toBe('2');
  expect(chipIsActive(renderer.root, 'Spanish')).toBe(true);
  expect(chipIsActive(renderer.root, 'Japanese')).toBe(false);
  expect(statusText(renderer.root)).toContain('captions: Spanish');

  // And native "Off" clears the active chip.
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionTrackChanged?.({ nativeEvent: { id: '', language: '' } });
  });
  expect(lastPlayerProps!.captionsEnabled).toBe(false);
  expect(chipIsActive(renderer.root, 'Off')).toBe(true);
});

test('a source change resets tracks and clears the active selection', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionsAvailable?.({
      nativeEvent: { tracks: AVAILABLE_TRACKS },
    });
  });
  await ReactTestRenderer.act(() => {
    chipByLabel(renderer.root, 'Spanish').props.onPress();
  });
  expect(lastPlayerProps!.captionsEnabled).toBe(true);
  expect(chipIsActive(renderer.root, 'Spanish')).toBe(true);

  // A new source loads. The native side emits the authoritative reset the
  // feature now sends on onSourceReset: an empty track list followed by an
  // off track-changed event. The UI must drop the stale Spanish selection and
  // its chip rather than leaving JS believing Spanish is still active (the
  // cross-source stale-id bug). The old track chips disappear entirely.
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionsAvailable?.({ nativeEvent: { tracks: [] } });
    lastPlayerProps!.onCaptionTrackChanged?.({ nativeEvent: { id: '', language: '' } });
  });

  expect(lastPlayerProps!.captionsEnabled).toBe(false);
  expect(lastPlayerProps!.captionTrackId).toBe('');
  expect(chipIsActive(renderer.root, 'Off')).toBe(true);
  expect(
    renderer.root.findAll(
      node =>
        typeof node.props.onPress === 'function' &&
        node.findAllByType(Text).some(t => t.props.children === 'Spanish'),
    ),
  ).toHaveLength(0);
});

test('opaque ids from the native layer are passed through unparsed', async () => {
  // iOS mints source-namespaced ids like "3:1"; the JS layer must treat the id
  // as an opaque token and echo it back exactly, never parse or reformat it.
  const NS_TRACKS: CaptionTrack[] = [
    { id: '3:0', language: 'en', label: 'English' },
    { id: '3:1', language: 'en', label: 'English SDH' },
  ];
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onCaptionsAvailable?.({ nativeEvent: { tracks: NS_TRACKS } });
  });
  await ReactTestRenderer.act(() => {
    chipByLabel(renderer.root, 'English SDH').props.onPress();
  });
  expect(lastPlayerProps!.captionTrackId).toBe('3:1');
  expect(chipIsActive(renderer.root, 'English SDH')).toBe(true);
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
