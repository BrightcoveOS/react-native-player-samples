import { useRef, useState, type ElementRef } from 'react';
import {
  BrightcovePlayerView,
  PlayerCommands,
  type RepeatMode,
} from '@brightcove/react-native-player';
import { Pressable, StatusBar, StyleSheet, Text, View } from 'react-native';
import { PLAYER_CONFIG } from './src/playerConfig';
import { SafeAreaRoot } from './src/components/SafeAreaRoot';

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'error'; message: string };

const nextRepeatMode = (mode: RepeatMode): RepeatMode => {
  if (mode === 'off') return 'one';
  if (mode === 'one') return 'all';
  return 'off';
};

function App() {
  const [status, setStatus] = useState<PlayerStatus>({
    kind: 'loading',
    message: 'Loading queue',
  });
  const [currentIndex, setCurrentIndex] = useState<number | null>(null);
  const [failedIndexes, setFailedIndexes] = useState<Set<number>>(new Set());
  const [completed, setCompleted] = useState(false);
  const [repeatMode, setRepeatMode] = useState<RepeatMode>('off');
  const [fullscreen, setFullscreen] = useState(false);
  const [shuffle, setShuffle] = useState(false);
  const [commandError, setCommandError] = useState<string | null>(null);
  const playerRef = useRef<ElementRef<typeof BrightcovePlayerView>>(null);
  // The queue is genuinely at its end only when the last item is playing and
  // repeat is not wrapping. "next" is a valid rejection in exactly that
  // state, and in no other; the sample uses this to keep the message
  // truthful rather than show a stale "at end".
  const atEnd = currentIndex === PLAYER_CONFIG.queue.length - 1 && repeatMode === 'off';

  return (
    <SafeAreaRoot style={styles.screen}>
    <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <View style={styles.header}>
        <Text style={styles.eyebrow}>PLAYER / PLAYLISTS</Text>
        <Text style={styles.title}>Queue playback.</Text>
        <Text style={styles.description}>
          videoIds loads a queue instead of a single video; the native SDK's
          own queue owns end-of-item advancement. repeatMode and shuffle
          layer on top, and next/previous are manual skips.
        </Text>
      </View>

      <BrightcovePlayerView
        ref={playerRef}
        accountId={PLAYER_CONFIG.accountId}
        policyKey={PLAYER_CONFIG.policyKey}
        videoIds={PLAYER_CONFIG.queue.map(item => item.videoId)}
        repeatMode={repeatMode}
        shuffle={shuffle}
        autoPlay
        onReady={({ nativeEvent }) => {
          setStatus({
            kind: 'ready',
            message: `Ready video ${nativeEvent.videoId}`,
          });
        }}
        onError={({ nativeEvent }) => {
          setStatus({
            kind: 'error',
            message: `${nativeEvent.code}: ${nativeEvent.message}`,
          });
        }}
        onQueueItemChanged={({ nativeEvent }) => {
          setCurrentIndex(nativeEvent.index);
          setFailedIndexes(previous => {
            if (!previous.has(nativeEvent.index)) return previous;
            const next = new Set(previous);
            next.delete(nativeEvent.index);
            return next;
          });
          setCompleted(false);
          // The queue moved, so a previous "at end" (or "not loaded")
          // rejection no longer describes the current state. Clear it here
          // and below whenever the condition it reported changes; a stale
          // error must not outlive the state that produced it.
          setCommandError(null);
        }}
        onFullscreenChanged={({ nativeEvent }) => {
          setFullscreen(nativeEvent.active);
        }}
        onQueueItemFailed={({ nativeEvent }) => {
          setFailedIndexes(previous => new Set(previous).add(nativeEvent.index));
        }}
        onPlayerCommandError={({ nativeEvent }) => {
          // A rejected next/previous is a typed command outcome, not a
          // playback failure. Show it only while it is still true: the
          // at-end rejection must not appear when a further item exists or
          // repeat wraps the queue, and it must clear as soon as the queue
          // moves. A stale message outliving its condition is the bug a
          // user sees as "end of playlist" on a queue that is not at its
          // end.
          if (nativeEvent.nativeCode === 'queue_at_end' && !atEnd) {
            return;
          }
          setCommandError(`${nativeEvent.command}: ${nativeEvent.nativeCode}`);
        }}
        onQueueCompleted={() => {
          setCompleted(true);
          // Completion is the authoritative end state; the imperative
          // rejection message is redundant once the queue itself says so.
          setCommandError(null);
        }}
        style={styles.player}
      />

      <View style={styles.status}>
        <View
          style={[
            styles.statusDot,
            status.kind === 'ready' && styles.readyDot,
            status.kind === 'error' && styles.errorDot,
          ]}
        />
        <Text style={styles.statusText}>{status.message}</Text>
      </View>

      <View style={styles.controls}>
        <Pressable
          style={styles.button}
          onPress={() => {
            if (!playerRef.current) return;
            fullscreen
              ? PlayerCommands.exitFullscreen(playerRef.current)
              : PlayerCommands.enterFullscreen(playerRef.current);
          }}>
          <Text style={styles.buttonText}>
            {fullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
          </Text>
        </Pressable>
        <Pressable
          style={styles.button}
          onPress={() => PlayerCommands.previous(playerRef.current!)}>
          <Text style={styles.buttonText}>Previous</Text>
        </Pressable>
        <Pressable
          style={styles.button}
          onPress={() => {
            setShuffle(current => !current);
            setCommandError(null);
          }}>
          <Text style={styles.buttonText}>
            Shuffle: {shuffle ? 'On' : 'Off'}
          </Text>
        </Pressable>
        <Pressable
          style={styles.button}
          onPress={() => {
            setRepeatMode(nextRepeatMode);
            // Changing repeat can remove the at-end condition (e.g. off ->
            // all), so the previous rejection no longer applies.
            setCommandError(null);
          }}>
          <Text style={styles.buttonText}>Repeat: {repeatMode}</Text>
        </Pressable>
        <Pressable
          style={styles.button}
          onPress={() => PlayerCommands.next(playerRef.current!)}>
          <Text style={styles.buttonText}>Next</Text>
        </Pressable>
      </View>

      <View style={styles.queueCard}>
        <Text style={styles.cardEyebrow}>QUEUE</Text>
        {PLAYER_CONFIG.queue.map((item, index) => {
          const isCurrent = currentIndex === index;
          const isFailed = failedIndexes.has(index);
          return (
            <View key={`${item.videoId}-${index}`} style={styles.queueRow}>
              <View
                style={[
                  styles.queueDot,
                  isCurrent && styles.queueDotCurrent,
                  isFailed && styles.queueDotFailed,
                ]}
              />
              <Text
                style={[
                  styles.queueItemTitle,
                  isCurrent && styles.queueItemTitleCurrent,
                ]}>
                {item.title}
              </Text>
              {isFailed ? (
                <Text style={styles.queueItemFailed}>failed</Text>
              ) : null}
            </View>
          );
        })}
        {completed ? (
          <Text style={styles.completedText}>Queue completed</Text>
        ) : null}
        {commandError ? (
          <Text style={styles.queueItemFailed} testID="command-error">
            {commandError}
          </Text>
        ) : null}
      </View>
    </SafeAreaRoot>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: '#ffffff',
    paddingHorizontal: 24,
  },
  header: {
    paddingBottom: 24,
    paddingTop: 32,
  },
  eyebrow: {
    color: '#8a8f98',
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 1.2,
  },
  title: {
    color: '#12141a',
    fontSize: 30,
    fontWeight: '700',
    letterSpacing: -0.6,
    marginTop: 8,
  },
  description: {
    color: '#5c6470',
    fontSize: 16,
    lineHeight: 24,
    marginTop: 10,
    maxWidth: 440,
  },
  player: {
    aspectRatio: 16 / 9,
    backgroundColor: '#000000',
    borderRadius: 12,
    overflow: 'hidden',
    width: '100%',
  },
  status: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
    marginTop: 18,
  },
  statusDot: {
    backgroundColor: '#d59a2e',
    borderRadius: 4,
    height: 8,
    width: 8,
  },
  readyDot: {
    backgroundColor: '#2aa889',
  },
  errorDot: {
    backgroundColor: '#d4574e',
  },
  statusText: {
    color: '#5c6470',
    flex: 1,
    fontSize: 14,
  },
  controls: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 20,
  },
  button: {
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 10,
    borderWidth: 1,
    flex: 1,
    paddingVertical: 10,
  },
  buttonText: {
    color: '#3a414c',
    fontSize: 12,
    fontWeight: '600',
    textAlign: 'center',
  },
  queueCard: {
    backgroundColor: '#f7f8fa',
    borderColor: '#e4e6ea',
    borderRadius: 12,
    borderWidth: 1,
    marginTop: 22,
    padding: 18,
  },
  cardEyebrow: {
    color: '#8a8f98',
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 1.1,
  },
  queueRow: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
    marginTop: 14,
  },
  queueDot: {
    backgroundColor: '#c9ced6',
    borderRadius: 5,
    height: 10,
    width: 10,
  },
  queueDotCurrent: {
    backgroundColor: '#2aa889',
  },
  queueDotFailed: {
    backgroundColor: '#d4574e',
  },
  queueItemTitle: {
    color: '#5c6470',
    flex: 1,
    fontSize: 14,
  },
  queueItemTitleCurrent: {
    color: '#12141a',
    fontWeight: '700',
  },
  queueItemFailed: {
    color: '#d4574e',
    fontSize: 11,
    fontWeight: '700',
  },
  completedText: {
    color: '#2aa889',
    fontSize: 13,
    fontWeight: '600',
    marginTop: 18,
  },
});

export default App;
