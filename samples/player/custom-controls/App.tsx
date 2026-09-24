import { useEffect, useRef, useState } from 'react';
import { BrightcovePlayerView, PlayerCommands } from '@brightcove/react-native-player';
import type { ElementRef } from 'react';
import {
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { PLAYER_CONFIG } from './src/playerConfig';

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'error'; message: string };

function App() {
  const playerRef = useRef<ElementRef<typeof BrightcovePlayerView>>(null);
  const [status, setStatus] = useState<PlayerStatus>({
    kind: 'loading',
    message: 'Loading demo video',
  });
  const [controlsEnabled, setControlsEnabled] = useState(false);
  const [volume, setVolume] = useState(1.0);
  const [muted, setMuted] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [fullscreenEnterPending, setFullscreenEnterPending] = useState(false);
  const restoreHiddenControlsAfterFullscreen = useRef(false);

  // A React Native exit button remains behind iOS's fullscreen modal and
  // Android's Activity-root overlay. When native controls are hidden, enable
  // them first and request fullscreen only after that prop commit so the
  // presented player always contains the SDK's own exit control.
  useEffect(() => {
    if (!fullscreenEnterPending || !controlsEnabled || !playerRef.current) return;
    setFullscreenEnterPending(false);
    PlayerCommands.enterFullscreen(playerRef.current);
  }, [controlsEnabled, fullscreenEnterPending]);

  const toggleFullscreen = () => {
    if (!playerRef.current) return;
    if (fullscreen) {
      PlayerCommands.exitFullscreen(playerRef.current);
      return;
    }
    if (!controlsEnabled) {
      restoreHiddenControlsAfterFullscreen.current = true;
      setControlsEnabled(true);
      setFullscreenEnterPending(true);
      return;
    }
    PlayerCommands.enterFullscreen(playerRef.current);
  };

  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <SafeAreaView style={styles.screen}>
        <ScrollView contentContainerStyle={styles.scrollContent}>
          <View style={styles.header}>
            <Text style={styles.eyebrow}>PLAYER / CUSTOM CONTROLS</Text>
            <Text style={styles.title}>Custom Controls</Text>
            <Text style={styles.description}>
              Drive playback through React Native controls while hiding native SDK controls via controlsEnabled.
            </Text>
          </View>

          <BrightcovePlayerView
            ref={playerRef}
            accountId={PLAYER_CONFIG.accountId}
            policyKey={PLAYER_CONFIG.policyKey}
            videoId={PLAYER_CONFIG.videoId}
            controlsEnabled={controlsEnabled}
            volume={volume}
            muted={muted}
            autoPlay
            onFullscreenChanged={({ nativeEvent }) => {
              setFullscreen(nativeEvent.active);
              if (!nativeEvent.active && restoreHiddenControlsAfterFullscreen.current) {
                restoreHiddenControlsAfterFullscreen.current = false;
                setControlsEnabled(false);
              }
            }}
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
            testID="brightcove-player"
          />

          <View style={styles.status}>
            <View
              style={[
                styles.statusDot,
                status.kind === 'ready' && styles.readyDot,
                status.kind === 'error' && styles.errorDot,
              ]}
            />
            <Text style={styles.statusText} testID="status-text">
              {status.message}
            </Text>
          </View>

          <View style={styles.controlsPanel}>
            <Text style={styles.sectionHeader}>NATIVE CONTROLS VISIBILITY</Text>
            <View style={styles.toggleRow}>
              <Text style={styles.infoLabel}>Native Controls:</Text>
              <Pressable
                style={[
                  styles.toggleButton,
                  controlsEnabled ? styles.toggleOn : styles.toggleOff,
                ]}
                onPress={() => setControlsEnabled(!controlsEnabled)}
                testID="btn-toggle-controls"
              >
                <Text style={styles.toggleButtonText}>
                  {controlsEnabled ? 'Enabled' : 'Hidden'}
                </Text>
              </Pressable>
            </View>

            <Text style={styles.sectionHeaderSpacing}>FULLSCREEN</Text>
            <View style={styles.buttonRow}>
              <Pressable
                style={[styles.button, fullscreen && styles.buttonActive]}
                onPress={toggleFullscreen}
                testID="btn-fullscreen"
              >
                <Text style={styles.buttonText}>
                  {fullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
                </Text>
              </Pressable>
            </View>

            <Text style={styles.sectionHeaderSpacing}>CUSTOM AUDIO CONTROLS</Text>
            <View style={styles.buttonRow}>
              {[0, 0.5, 1].map((vol) => (
                <Pressable
                  key={vol}
                  style={[styles.button, volume === vol && styles.buttonActive]}
                  onPress={() => setVolume(vol)}
                  testID={`btn-volume-${vol * 100}`}
                >
                  <Text style={styles.buttonText}>{vol === 0 ? 'Mute (0%)' : `${vol * 100}%`}</Text>
                </Pressable>
              ))}
              <Pressable
                style={[styles.button, muted && styles.buttonActive]}
                onPress={() => setMuted(!muted)}
                testID="btn-mute"
              >
                <Text style={styles.buttonText}>{muted ? 'Unmute' : 'Mute'}</Text>
              </Pressable>
            </View>

            <View style={styles.actionInfo}>
              <Text style={styles.infoLabel}>Current Audio State:</Text>
              <Text style={styles.actionText} testID="audio-state">
                {`Vol: ${Math.round(volume * 100)}% | Muted: ${muted ? 'Yes' : 'No'}`}
              </Text>
            </View>
          </View>
        </ScrollView>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  scrollContent: {
    paddingHorizontal: 24,
    paddingBottom: 40,
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
  controlsPanel: {
    backgroundColor: '#f7f8fa',
    borderColor: '#e4e6ea',
    borderRadius: 12,
    borderWidth: 1,
    marginTop: 24,
    padding: 16,
  },
  sectionHeader: {
    color: '#8a8f98',
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 1.1,
    marginBottom: 12,
  },
  sectionHeaderSpacing: {
    color: '#8a8f98',
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 1.1,
    marginBottom: 12,
    marginTop: 18,
  },
  buttonRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginBottom: 16,
  },
  button: {
    backgroundColor: '#eef0f3',
    borderColor: '#e0e3e8',
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  buttonActive: {
    backgroundColor: '#12141a',
    borderColor: '#12141a',
  },
  buttonText: {
    color: '#3a414c',
    fontSize: 14,
    fontWeight: '600',
  },
  toggleRow: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
  },
  infoLabel: {
    color: '#5c6470',
    fontSize: 14,
  },
  toggleButton: {
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 7,
  },
  toggleOn: {
    backgroundColor: '#12141a',
  },
  toggleOff: {
    backgroundColor: '#c9ced6',
  },
  toggleButtonText: {
    color: '#ffffff',
    fontSize: 13,
    fontWeight: '600',
  },
  actionInfo: {
    alignItems: 'center',
    borderTopColor: '#e4e6ea',
    borderTopWidth: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 12,
    paddingTop: 12,
  },
  actionText: {
    color: '#12141a',
    fontFamily: 'monospace',
    fontSize: 14,
    fontWeight: '600',
  },
});

export default App;
