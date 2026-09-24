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

type PlayerProps = {
  accountId: string;
  policyKey: string;
  videoIds: string[];
  repeatMode: string;
  shuffle: boolean;
  autoPlay?: boolean;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
  onQueueItemChanged?: (e: {
    nativeEvent: { videoId: string; index: number };
  }) => void;
  onQueueItemFailed?: (e: {
    nativeEvent: {
      videoId: string;
      index: number;
      code: string;
      message: string;
      nativeCode: string;
    };
  }) => void;
  onQueueCompleted?: () => void;
  onPlayerCommandError?: (e: {
    nativeEvent: {
      command: string;
      code: string;
      message: string;
      nativeCode: string;
    };
  }) => void;
};

let lastPlayerProps: PlayerProps | undefined;

const nextCalls: unknown[] = [];
const previousCalls: unknown[] = [];

jest.mock('@brightcove/react-native-player', () => ({
  BrightcovePlayerView: (props: PlayerProps) => {
    lastPlayerProps = props;
    return null;
  },
  PlayerCommands: {
    next: (ref: unknown) => nextCalls.push(ref),
    previous: (ref: unknown) => previousCalls.push(ref),
  },
}));

import App from '../App';

const textValue = (value: unknown): string => {
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return value.map(textValue).join('');
  return '';
};

const statusText = (tree: ReactTestInstance): string =>
  tree.findAllByType(Text).map(node => textValue(node.props.children)).join(' ');

// A button is a pressable element (it has an onPress) that contains a Text
// whose content includes `label`. Matched by the onPress prop rather than the
// Pressable type, which react-test-renderer does not resolve to a single
// findable node.
const buttonByLabel = (
  tree: ReactTestInstance,
  label: string,
): ReactTestInstance =>
  tree
    .findAll(
      node =>
        typeof node.props.onPress === 'function' &&
        node
          .findAllByType(Text)
          .some(t => textValue(t.props.children).includes(label)),
    )
    .at(-1)!;

beforeEach(() => {
  lastPlayerProps = undefined;
  nextCalls.length = 0;
  previousCalls.length = 0;
});

test('hands the demo queue, repeatMode, shuffle, and autoPlay to the native view', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps).toBeDefined();
  expect(lastPlayerProps!.accountId).toBe('5434391461001');
  expect(lastPlayerProps!.videoIds).toEqual([
    '5702148954001',
    '5702143016001',
    '5702149062001',
  ]);
  expect(lastPlayerProps!.policyKey).toEqual(expect.stringContaining('BCpk'));
  expect(lastPlayerProps!.repeatMode).toBe('off');
  expect(lastPlayerProps!.shuffle).toBe(false);
  expect(lastPlayerProps!.autoPlay).toBe(true);
});

test('starts in the loading state with no current item', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(statusText(renderer.root)).toContain('Loading queue');
});

test('onQueueItemChanged highlights the current queue item', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemChanged?.({
      nativeEvent: { videoId: '5702143016001', index: 1 },
    });
  });

  const documentationRow = renderer.root
    .findAllByType(Text)
    .find(node => textValue(node.props.children) === 'Documentation')!;
  const styles = ([] as unknown[]).concat(documentationRow.props.style ?? []);
  expect(
    styles.some(
      s => s && typeof s === 'object' && (s as { fontWeight?: string }).fontWeight === '700',
    ),
  ).toBe(true);
});

test('onQueueItemFailed marks the failed item without changing the current one', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemFailed?.({
      nativeEvent: {
        videoId: '5702143016001',
        index: 1,
        code: 'not_found',
        message: 'Unable to retrieve the Brightcove video',
        nativeCode: 'catalog_error',
      },
    });
  });

   expect(statusText(renderer.root)).toContain('failed');

   await ReactTestRenderer.act(() => {
     lastPlayerProps!.onQueueItemChanged?.({
       nativeEvent: { videoId: '5702143016001', index: 1 },
     });
   });

   expect(statusText(renderer.root)).not.toContain('failed');
});

test('onQueueCompleted surfaces the completed state', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueCompleted?.();
  });

  expect(statusText(renderer.root)).toContain('Queue completed');
});

test('onPlayerCommandError surfaces a real at-end rejection', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  // Play the last item with repeat off: this is the one state where "next"
  // is genuinely a queue-at-end rejection.
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemChanged?.({
      nativeEvent: { videoId: '5702149062001', index: 2 },
    });
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPlayerCommandError?.({
      nativeEvent: {
        command: 'next',
        code: 'invalid_state',
        message: 'Cannot advance the queue: the last item is already playing',
        nativeCode: 'queue_at_end',
      },
    });
  });

  expect(statusText(renderer.root)).toContain('next: queue_at_end');
});

test('an at-end rejection is not shown when a further item exists', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  // On the first item, "next" cannot be at the end. Even if a stale
  // rejection arrives, the sample must not display it.
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemChanged?.({
      nativeEvent: { videoId: '5702148954001', index: 0 },
    });
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPlayerCommandError?.({
      nativeEvent: {
        command: 'next',
        code: 'invalid_state',
        message: 'Cannot advance the queue',
        nativeCode: 'queue_at_end',
      },
    });
  });

  expect(statusText(renderer.root)).not.toContain('queue_at_end');
});

test('turning repeat on clears an at-end rejection', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemChanged?.({
      nativeEvent: { videoId: '5702149062001', index: 2 },
    });
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPlayerCommandError?.({
      nativeEvent: {
        command: 'next',
        code: 'invalid_state',
        message: 'Cannot advance the queue',
        nativeCode: 'queue_at_end',
      },
    });
  });
  expect(statusText(renderer.root)).toContain('queue_at_end');

  // With repeat all, the queue wraps, so the at-end message is no longer true.
  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Repeat').props.onPress(); // off -> one
  });
  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Repeat').props.onPress(); // one -> all
  });

  expect(statusText(renderer.root)).not.toContain('queue_at_end');
});

test('advancing the queue clears an at-end rejection', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemChanged?.({
      nativeEvent: { videoId: '5702149062001', index: 2 },
    });
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onPlayerCommandError?.({
      nativeEvent: {
        command: 'next',
        code: 'invalid_state',
        message: 'Cannot advance the queue',
        nativeCode: 'queue_at_end',
      },
    });
  });
  expect(statusText(renderer.root)).toContain('queue_at_end');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemChanged?.({
      nativeEvent: { videoId: '5702148954001', index: 0 },
    });
  });

  expect(statusText(renderer.root)).not.toContain('queue_at_end');
});

test('a queue item changed event after completion clears the completed state', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueCompleted?.();
  });
  expect(statusText(renderer.root)).toContain('Queue completed');

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onQueueItemChanged?.({
      nativeEvent: { videoId: '5702148954001', index: 0 },
    });
  });
  expect(statusText(renderer.root)).not.toContain('Queue completed');
});

test('the shuffle button toggles the shuffle prop', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps!.shuffle).toBe(false);

  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Shuffle').props.onPress();
  });

  expect(lastPlayerProps!.shuffle).toBe(true);
});

test('the repeat button cycles off -> one -> all -> off', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps!.repeatMode).toBe('off');

  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Repeat').props.onPress();
  });
  expect(lastPlayerProps!.repeatMode).toBe('one');

  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Repeat').props.onPress();
  });
  expect(lastPlayerProps!.repeatMode).toBe('all');

  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Repeat').props.onPress();
  });
  expect(lastPlayerProps!.repeatMode).toBe('off');
});

test('the next and previous buttons dispatch the imperative commands', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Next').props.onPress();
  });
  expect(nextCalls).toHaveLength(1);

  await ReactTestRenderer.act(() => {
    buttonByLabel(renderer.root, 'Previous').props.onPress();
  });
  expect(previousCalls).toHaveLength(1);
});

test('onReady moves the UI to the ready state with the video id', async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: '5702148954001' } });
  });

  expect(statusText(renderer.root)).toContain('Ready video 5702148954001');
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
        message: 'None of the videos in videoIds could be resolved',
        nativeCode: 'playlist_empty_after_resolution',
      },
    });
  });

  const text = statusText(renderer.root);
  expect(text).toContain('not_found');
  expect(text).toContain('None of the videos in videoIds could be resolved');
});
