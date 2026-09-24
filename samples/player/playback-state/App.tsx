import { useRef, useState, type ElementRef } from 'react';
import {
  BrightcovePlayerView,
  PlayerCommands,
} from '@brightcove/react-native-player';
import { Pressable, StatusBar, StyleSheet, Text, View } from 'react-native';
import { SafeAreaRoot } from './src/components/SafeAreaRoot';
import { DEMO_SOURCES, PLAYER_CONFIG, isConfigured } from './src/playerConfig';

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'error'; message: string };

type PlaybackState = 'idle' | 'playing' | 'paused' | 'ended';

function formatSeconds(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${minutes}:${remainder.toString().padStart(2, '0')}`;
}

function App() {
  const [sourceKey, setSourceKey] = useState<'vod' | 'live'>('vod');
  const [status, setStatus] = useState<PlayerStatus>({
    kind: 'loading',
    message: 'Loading demo video',
  });
  const [playbackState, setPlaybackState] = useState<PlaybackState>('idle');
  const [progress, setProgress] = useState({ currentTime: 0, duration: 0 });
  const [liveStatus, setLiveStatus] = useState<{
    isLive: boolean;
    hasDvr: boolean;
  } | null>(null);
  const [seekableRanges, setSeekableRanges] = useState<
    { startTime: number; endTime: number }[]
  >([]);
  const [liveEdge, setLiveEdge] = useState(0);
  const playerRef = useRef<ElementRef<typeof BrightcovePlayerView>>(null);

  const source =
    DEMO_SOURCES.find(candidate => candidate.key === sourceKey) ?? DEMO_SOURCES[0];
  const sourceConfigured = isConfigured(source.videoId);

  // A source change reloads the player; clear the per-source observations so a
  // stale live window, progress, or lifecycle state never describes the new
  // source.
  const selectSource = (key: 'vod' | 'live') => {
    if (key === sourceKey) return;
    setSourceKey(key);
    setStatus({ kind: 'loading', message: 'Loading demo video' });
    setPlaybackState('idle');
    setProgress({ currentTime: 0, duration: 0 });
    setLiveStatus(null);
    setSeekableRanges([]);
    setLiveEdge(0);
  };

  return (
    <SafeAreaRoot style={styles.screen}>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <View style={styles.header}>
        <Text style={styles.eyebrow}>PLAYER / PLAYBACK STATE</Text>
        <Text style={styles.title}>Playback State</Text>
        <Text style={styles.description}>
          Playback lifecycle and progress report the current state to JS; live
          status and seekable ranges describe live-DVR content. The Go live
          command seeks to the current live edge when DVR is available.
        </Text>
      </View>

      <View style={styles.sourceRow}>
        {DEMO_SOURCES.map(candidate => (
          <Pressable
            key={candidate.key}
            testID={`source-${candidate.key}`}
            onPress={() => selectSource(candidate.key)}
            style={[
              styles.sourceButton,
              candidate.key === sourceKey && styles.sourceButtonActive,
            ]}>
            <Text
              style={[
                styles.sourceButtonText,
                candidate.key === sourceKey && styles.sourceButtonTextActive,
              ]}>
              {candidate.label}
            </Text>
          </Pressable>
        ))}
      </View>

      {sourceConfigured ? (
        <BrightcovePlayerView
          ref={playerRef}
          key={source.videoId}
          accountId={PLAYER_CONFIG.accountId}
          policyKey={PLAYER_CONFIG.policyKey}
          videoId={source.videoId}
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
          onPlay={() => setPlaybackState('playing')}
          onPause={() => setPlaybackState('paused')}
          onEnded={() => setPlaybackState('ended')}
          onProgress={({ nativeEvent }) => {
            setProgress({
              currentTime: nativeEvent.currentTime,
              duration: nativeEvent.duration,
            });
          }}
          onLiveStatus={({ nativeEvent }) => {
            setLiveStatus({
              isLive: nativeEvent.isLive,
              hasDvr: nativeEvent.hasDvr,
            });
          }}
          onSeekableRangesChanged={({ nativeEvent }) => {
            setSeekableRanges(nativeEvent.ranges);
            setLiveEdge(nativeEvent.liveEdge);
          }}
          style={styles.player}
        />
      ) : (
        <View style={styles.unconfigured}>
          <Text style={styles.unconfiguredText}>
            This source is a live-DVR placeholder. Set `YOUR_LIVE_DVR_VIDEO_ID`
            in `src/playerConfig.ts` to a live-DVR asset id from an account that
            owns one.
          </Text>
        </View>
      )}

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

      <View style={styles.chipRow}>
        <View
          style={[styles.chip, playbackState === 'playing' && styles.chipActive]}>
          <Text
            style={[
              styles.chipText,
              playbackState === 'playing' && styles.chipTextActive,
            ]}>
            {playbackState === 'idle' ? 'Not started' : playbackState}
          </Text>
        </View>

        <View style={styles.chip}>
          <Text style={styles.chipText}>
            {formatSeconds(progress.currentTime)} /{' '}
            {formatSeconds(progress.duration)}
          </Text>
        </View>

        <View style={[styles.chip, liveStatus?.isLive && styles.chipActive]}>
          <Text
            style={[
              styles.chipText,
              liveStatus?.isLive && styles.chipTextActive,
            ]}>
            {liveStatus == null
              ? 'Live status pending'
              : liveStatus.isLive
                ? liveStatus.hasDvr
                  ? 'Live (DVR)'
                  : 'Live'
                : 'On-demand'}
          </Text>
        </View>
      </View>

      <View style={styles.liveWindow}>
        <Text style={styles.liveWindowText}>
          {seekableRanges.length > 0
            ? `Seekable: ${formatSeconds(seekableRanges[0].startTime)}–${formatSeconds(seekableRanges[0].endTime)} · Live edge: ${formatSeconds(liveEdge)}`
            : 'Seekable window unavailable'}
        </Text>
        {liveStatus?.hasDvr &&
        seekableRanges.length > 0 &&
        liveEdge > 0 &&
        seekableRanges[0].startTime >= 0 &&
        seekableRanges[0].endTime > seekableRanges[0].startTime ? (
          <Pressable
            testID="go-live"
            style={styles.goLiveButton}
            onPress={() => {
              if (playerRef.current) {
                PlayerCommands.seekToLiveEdge(playerRef.current);
              }
            }}>
            <Text style={styles.goLiveText}>Go live</Text>
          </Pressable>
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
    paddingBottom: 20,
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
    maxWidth: 420,
  },
  sourceRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginBottom: 16,
  },
  sourceButton: {
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  sourceButtonActive: {
    backgroundColor: '#12141a',
    borderColor: '#12141a',
  },
  sourceButtonText: {
    color: '#3a414c',
    fontSize: 13,
    fontWeight: '600',
  },
  sourceButtonTextActive: {
    color: '#ffffff',
  },
  player: {
    aspectRatio: 16 / 9,
    backgroundColor: '#000000',
    borderRadius: 12,
    overflow: 'hidden',
    width: '100%',
  },
  unconfigured: {
    alignItems: 'center',
    aspectRatio: 16 / 9,
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 12,
    borderWidth: 1,
    justifyContent: 'center',
    paddingHorizontal: 24,
    width: '100%',
  },
  unconfiguredText: {
    color: '#5c6470',
    fontSize: 14,
    lineHeight: 21,
    textAlign: 'center',
  },
  status: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
    marginTop: 20,
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
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
    marginTop: 18,
  },
  chip: {
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  chipActive: {
    backgroundColor: '#12141a',
    borderColor: '#12141a',
  },
  chipText: {
    color: '#3a414c',
    fontSize: 13,
    fontWeight: '600',
  },
  chipTextActive: {
    color: '#ffffff',
  },
  liveWindow: {
    gap: 12,
    marginTop: 20,
  },
  liveWindowText: {
    color: '#5c6470',
    fontSize: 13,
  },
  goLiveButton: {
    alignSelf: 'flex-start',
    backgroundColor: '#12141a',
    borderRadius: 10,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  goLiveText: {
    color: '#ffffff',
    fontSize: 13,
    fontWeight: '700',
  },
});

export default App;
