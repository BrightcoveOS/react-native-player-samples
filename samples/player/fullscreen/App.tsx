import { useRef, useState } from 'react';
import { BrightcovePlayerView, PlayerCommands } from '@brightcove/react-native-player';
import type { ElementRef } from 'react';
import { Button, StatusBar, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

const DEMO_ACCOUNT_ID = '6415855237001';
const DEMO_POLICY_KEY =
  'BCpkADawqM3dtPuWvSDSrMwpq0TWhZ0pnpPuEEWNrfyb2L0wNPs_333JY8J5IE8vMNhgF92EBV0GL_5HTyeWxndxw1qO0L0ksdJPE33LLESUiRwf65CR6P8gzmeIxrK7NrTn2gPUv2ZkeYiXEG-3-yvjMkLbFmiO8y3-Wg';
const DEMO_VIDEO_ID = '6393164822112';

function App() {
  const [fullscreen, setFullscreen] = useState(false);
  const [status, setStatus] = useState('Loading demo video');
  const playerRef = useRef<ElementRef<typeof BrightcovePlayerView>>(null);
  const { width, height } = useWindowDimensions();
  const fullscreenWidth = Math.min(width, height * (16 / 9));
  const fullscreenHeight = Math.min(height, width * (9 / 16));

  return (
    <SafeAreaProvider>
      <View style={styles.root}>
        <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
        <SafeAreaView style={[styles.screen, fullscreen && styles.fullscreenScreen]}>
          {!fullscreen ? (
            <View style={styles.header}>
              <Text style={styles.eyebrow}>PLAYER / FULLSCREEN</Text>
              <Text style={styles.title}>Know the player mode</Text>
              <Text style={styles.description}>
                The native Brightcove controls own the transition. React Native only
                reports the completed player screen mode; the host app still owns
                orientation and host navigation policy. The native SDK may manage
                its own window bars during the transition.
              </Text>
            </View>
          ) : null}

          <View style={[styles.playerHost, fullscreen && styles.fullscreenPlayerHost]}>
            <BrightcovePlayerView
              ref={playerRef}
              accountId={DEMO_ACCOUNT_ID}
              policyKey={DEMO_POLICY_KEY}
              videoId={DEMO_VIDEO_ID}
              autoPlay
              onReady={({ nativeEvent }) => {
                setStatus(`Ready video ${nativeEvent.videoId}`);
              }}
              onError={({ nativeEvent }) => {
                setStatus(`${nativeEvent.code}: ${nativeEvent.message}`);
              }}
              onFullscreenChanged={({ nativeEvent }) => {
                setFullscreen(nativeEvent.active);
              }}
              style={[
                styles.player,
                fullscreen && styles.fullscreenPlayer,
                fullscreen && { width: fullscreenWidth, height: fullscreenHeight },
              ]}
            />
          </View>

          {!fullscreen ? (
            <>
              <View style={styles.modeCard}>
                <View style={styles.modeDot} />
                <View style={styles.modeCopy}>
                  <Text style={styles.modeLabel}>Windowed</Text>
                  <Text style={styles.modeDescription}>Brightcove player screen mode</Text>
                </View>
              </View>

              <Text style={styles.status}>{status}</Text>
              <View style={styles.commandRow}>
                <Button
                  title="Enter fullscreen"
                  onPress={() => {
                    if (playerRef.current) {
                      PlayerCommands.enterFullscreen(playerRef.current);
                    }
                  }}
                />
              </View>
              <Text style={styles.note}>No orientation is changed by this bridge.</Text>
            </>
          ) : null}
        </SafeAreaView>

        {fullscreen ? (
          <View style={styles.fullscreenControls}>
            <Button
              title="Exit fullscreen"
              onPress={() => {
                if (playerRef.current) {
                  PlayerCommands.exitFullscreen(playerRef.current);
                }
              }}
            />
          </View>
        ) : null}
      </View>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  screen: {
    flex: 1,
    backgroundColor: '#ffffff',
    paddingHorizontal: 24,
  },
  fullscreenScreen: {
    alignItems: 'center',
    backgroundColor: '#000000',
    bottom: 0,
    justifyContent: 'center',
    left: 0,
    paddingHorizontal: 0,
    position: 'absolute',
    right: 0,
    top: 0,
    zIndex: 10,
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
  },
  playerHost: {
    alignItems: 'center',
  },
  fullscreenPlayerHost: {
    flex: 1,
    width: '100%',
  },
  player: {
    aspectRatio: 16 / 9,
    backgroundColor: '#000000',
    borderRadius: 12,
    overflow: 'hidden',
    width: '100%',
  },
  fullscreenPlayer: {
    borderRadius: 0,
    borderWidth: 0,
  },
  modeCard: {
    alignItems: 'center',
    borderColor: '#e4e6ea',
    borderRadius: 12,
    borderWidth: 1,
    flexDirection: 'row',
    gap: 12,
    marginTop: 20,
    padding: 16,
  },
  modeDot: {
    backgroundColor: '#d59a2e',
    borderRadius: 6,
    height: 12,
    width: 12,
  },
  modeCopy: { flex: 1 },
  modeLabel: { color: '#12141a', fontSize: 18, fontWeight: '700' },
  modeDescription: { color: '#8a8f98', fontSize: 13, marginTop: 3 },
  status: { color: '#5c6470', fontSize: 14, marginTop: 20 },
  commandRow: { marginTop: 18 },
  fullscreenControls: {
    position: 'absolute',
    right: 16,
    top: 16,
    zIndex: 20,
  },
  note: { color: '#8a8f98', fontSize: 13, marginTop: 12 },
});

export default App;