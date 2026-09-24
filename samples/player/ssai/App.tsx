import { useState } from 'react';
import { BrightcovePlayerView } from '@brightcove/react-native-player';
import { StatusBar, StyleSheet, Text, View } from 'react-native';
import { SafeAreaRoot } from './src/components/SafeAreaRoot';
import { PLAYER_CONFIG } from './src/playerConfig';

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'ad'; message: string }
  | { kind: 'error'; message: string };

function App() {
  const [status, setStatus] = useState<PlayerStatus>({
    kind: 'loading',
    message: 'Loading demo video',
  });

  return (
    <SafeAreaRoot style={styles.screen}>
    <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <View style={styles.header}>
        <Text style={styles.eyebrow}>PLAYER / SSAI</Text>
        <Text style={styles.title}>Brightcove Player</Text>
        <Text style={styles.description}>
          Server-side ad insertion. A VideoCloud ad-config stitches ads into a
          single stream — content and ads play as one.
        </Text>
      </View>

      <BrightcovePlayerView
        accountId={PLAYER_CONFIG.accountId}
        policyKey={PLAYER_CONFIG.policyKey}
        videoId={PLAYER_CONFIG.videoId}
        adConfigId={PLAYER_CONFIG.adConfigId}
        autoPlay
        onReady={({ nativeEvent }) => {
          setStatus({
            kind: 'ready',
            message: `Ready video ${nativeEvent.videoId}`,
          });
        }}
        onAdStarted={({ nativeEvent }) => {
          setStatus({
            kind: 'ad',
            message: nativeEvent.adTitle
              ? `Ad playing: ${nativeEvent.adTitle}`
              : 'Ad playing',
          });
        }}
        onAdCompleted={() => {
          setStatus({ kind: 'ad', message: 'Ad completed' });
        }}
        onAdBreakStarted={() => {
          setStatus({ kind: 'ad', message: 'Ad break started' });
        }}
        onAdBreakEnded={() => {
          setStatus({ kind: 'ready', message: 'Content resumed' });
        }}
        onAdError={({ nativeEvent }) => {
          setStatus({
            kind: 'error',
            message: `Ad error (${nativeEvent.code}): ${nativeEvent.message}`,
          });
        }}
        onError={({ nativeEvent }) => {
          setStatus({
            kind: 'error',
            message: `${nativeEvent.code}: ${nativeEvent.message}`,
          });
        }}
        style={styles.player}
      />

      <View style={styles.status}>
        <View
          style={[
            styles.statusDot,
            status.kind === 'ready' && styles.readyDot,
            status.kind === 'ad' && styles.adDot,
            status.kind === 'error' && styles.errorDot,
          ]}
        />
        <Text style={styles.statusText}>{status.message}</Text>
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
  adDot: {
    backgroundColor: '#7a5af5',
  },
  errorDot: {
    backgroundColor: '#d4574e',
  },
  statusText: {
    color: '#5c6470',
    flex: 1,
    fontSize: 14,
  },
});

export default App;
