import { useState } from 'react';
import { BrightcovePlayerView } from '@brightcove/react-native-player';
import { StatusBar, StyleSheet, Text, View } from 'react-native';
import { SafeAreaRoot } from './src/components/SafeAreaRoot';
import { PLAYER_CONFIG } from './src/playerConfig';

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
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
        <Text style={styles.eyebrow}>PLAYER / DRM</Text>
        <Text style={styles.title}>DRM</Text>
        <Text style={styles.description}>
          Play DRM-protected video (Widevine on Android, FairPlay on iOS). FairPlay plays on a physical device only, not the Simulator.
        </Text>
      </View>

      <BrightcovePlayerView
        accountId={PLAYER_CONFIG.accountId}
        policyKey={PLAYER_CONFIG.policyKey}
        videoId={PLAYER_CONFIG.videoId}
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
});
export default App;
