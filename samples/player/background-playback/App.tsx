import { useEffect, useState } from 'react';
import { BrightcovePlayerView } from '@brightcove/react-native-player';
import {
  PermissionsAndroid,
  Platform,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaRoot } from './src/components/SafeAreaRoot';
import { PLAYER_CONFIG } from './src/playerConfig';

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'error'; message: string };

type PlaybackState = 'idle' | 'playing' | 'paused' | 'ended';

type NotificationPermissionState = 'checking' | 'granted' | 'denied';

function formatSeconds(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${minutes}:${remainder.toString().padStart(2, '0')}`;
}

function App() {
  const [status, setStatus] = useState<PlayerStatus>({
    kind: 'loading',
    message: 'Loading demo video',
  });
  const [playbackState, setPlaybackState] = useState<PlaybackState>('idle');
  const [progress, setProgress] = useState({ currentTime: 0, duration: 0 });
  const [notificationPermission, setNotificationPermission] =
    useState<NotificationPermissionState>(
      Platform.OS === 'android' && Platform.Version >= 33 ? 'checking' : 'granted',
    );

  useEffect(() => {
    if (Platform.OS !== 'android' || Platform.Version < 33) return;

    PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS).then(
      result => {
        if (result === PermissionsAndroid.RESULTS.GRANTED) {
          setNotificationPermission('granted');
          return;
        }
        setNotificationPermission('denied');
        setStatus({
          kind: 'error',
          message: 'Notification permission denied — lock-screen controls unavailable',
        });
      },
      error => {
        setNotificationPermission('denied');
        setStatus({ kind: 'error', message: `Notification permission failed: ${error}` });
      },
    );
  }, []);

  return (
    <SafeAreaRoot style={styles.screen}>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <View style={styles.header}>
        <Text style={styles.eyebrow}>PLAYER / BACKGROUND PLAYBACK</Text>
        <Text style={styles.title}>Listen beyond the screen</Text>
        <Text style={styles.description}>
          Native media sessions keep long-form playback alive while the app is
          backgrounded and expose lock-screen controls and media notifications.
        </Text>
      </View>

      <BrightcovePlayerView
        accountId={PLAYER_CONFIG.accountId}
        policyKey={PLAYER_CONFIG.policyKey}
        videoId={PLAYER_CONFIG.videoId}
        autoPlay
        backgroundPlaybackEnabled={notificationPermission === 'granted'}
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

      <View style={styles.chipRow}>
        <View style={[styles.chip, playbackState === 'playing' && styles.chipActive]}>
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
      </View>

      <View style={styles.note}>
        <Text style={styles.noteTitle}>Test the host integration</Text>
        <Text style={styles.noteText}>
          Start playback, press Home or lock the device, then use the Android
          notification or iOS lock-screen controls. The bridge opt-in does not
          replace the native manifest, audio capability, or audio-session setup.
        </Text>
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
    maxWidth: 420,
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
  note: {
    borderLeftColor: '#12141a',
    borderLeftWidth: 2,
    marginTop: 28,
    paddingLeft: 14,
  },
  noteTitle: {
    color: '#12141a',
    fontSize: 14,
    fontWeight: '700',
  },
  noteText: {
    color: '#5c6470',
    fontSize: 13,
    lineHeight: 20,
    marginTop: 6,
  },
});

export default App;
