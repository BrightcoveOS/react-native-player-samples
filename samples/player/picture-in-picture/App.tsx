import { useRef, useState } from 'react';
import { BrightcovePlayerView, PlayerCommands } from '@brightcove/react-native-player';
import type { ElementRef } from 'react';
import { Pressable, StatusBar, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { PLAYER_CONFIG } from './src/playerConfig';

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'error'; message: string };

// The player fills the whole screen. Android and iOS both scale the entire
// player surface into the Picture-in-Picture window, so a full-bleed player is
// what makes the PiP window show the video (and nothing else). The sample's
// text sits in a translucent overlay above the video rather than pushing it
// into a smaller box.
function App() {
  const [status, setStatus] = useState<PlayerStatus>({
    kind: 'loading',
    message: 'Loading demo video',
  });
  const [pipActive, setPipActive] = useState(false);
  const playerRef = useRef<ElementRef<typeof BrightcovePlayerView>>(null);
  const [fullscreen, setFullscreen] = useState(false);

  return (
    <SafeAreaProvider>
      <StatusBar barStyle="light-content" backgroundColor="#000000" />
      <View style={styles.root}>
        <BrightcovePlayerView
          ref={playerRef}
          accountId={PLAYER_CONFIG.accountId}
          policyKey={PLAYER_CONFIG.policyKey}
          videoId={PLAYER_CONFIG.videoId}
          autoPlay
          pictureInPictureEnabled
          onFullscreenChanged={({ nativeEvent }) => {
            setFullscreen(nativeEvent.active);
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
          onPictureInPictureModeChanged={({ nativeEvent }) => {
            setPipActive(nativeEvent.active);
          }}
          style={styles.player}
        />

        <View style={styles.fullscreenRow}>
          <Pressable
            onPress={() => {
              if (!playerRef.current) return;
              fullscreen
                ? PlayerCommands.exitFullscreen(playerRef.current)
                : PlayerCommands.enterFullscreen(playerRef.current);
            }}
            style={[styles.fullscreenButton, fullscreen && styles.fullscreenButtonActive]}
          >
            <Text style={styles.fullscreenButtonText}>
              {fullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
            </Text>
          </Pressable>
        </View>

        <SafeAreaView style={styles.overlay} pointerEvents="none">
          <View style={styles.header}>
            <Text style={styles.eyebrow}>PLAYER / PICTURE-IN-PICTURE</Text>
            <Text style={styles.title}>Picture-in-Picture</Text>
            <Text style={styles.description}>
              Tap the Picture-in-Picture control, or send the app to the
              background, to keep the video playing in a floating window.
            </Text>
          </View>

          <View style={styles.footer}>
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

            <View style={[styles.pipChip, pipActive && styles.pipChipActive]}>
              <Text
                style={[
                  styles.pipChipText,
                  pipActive && styles.pipChipTextActive,
                ]}>
                {pipActive
                  ? 'Picture-in-Picture active'
                  : 'Picture-in-Picture inactive'}
              </Text>
            </View>
          </View>
        </SafeAreaView>
      </View>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#000000',
  },
  player: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: '#000000',
  },
  overlay: {
    flex: 1,
    justifyContent: 'space-between',
    paddingHorizontal: 24,
  },
  header: {
    paddingTop: 24,
  },
  eyebrow: {
    color: '#9dd9c9',
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 1.2,
    textShadowColor: '#000000',
    textShadowRadius: 6,
  },
  title: {
    color: '#ffffff',
    fontSize: 30,
    fontWeight: '700',
    letterSpacing: -0.6,
    marginTop: 8,
    textShadowColor: '#000000',
    textShadowRadius: 8,
  },
  description: {
    color: '#e7edf4',
    fontSize: 15,
    lineHeight: 22,
    marginTop: 10,
    maxWidth: 420,
    textShadowColor: '#000000',
    textShadowRadius: 8,
  },
  footer: {
    paddingBottom: 24,
  },
  status: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
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
    color: '#e7edf4',
    flex: 1,
    fontSize: 14,
    textShadowColor: '#000000',
    textShadowRadius: 6,
  },
  pipChip: {
    alignSelf: 'flex-start',
    backgroundColor: 'rgba(18, 20, 26, 0.78)',
    borderColor: 'rgba(255, 255, 255, 0.28)',
    borderRadius: 999,
    borderWidth: 1,
    marginTop: 14,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  pipChipActive: {
    backgroundColor: 'rgba(42, 168, 137, 0.9)',
    borderColor: '#2aa889',
  },
  pipChipText: {
    color: '#dfe7ef',
    fontSize: 13,
    fontWeight: '600',
    letterSpacing: 0.3,
  },
  pipChipTextActive: {
    color: '#ffffff',
  },
  fullscreenRow: {
    alignItems: 'center',
    marginTop: 18,
  },
  fullscreenButton: {
    backgroundColor: 'rgba(18, 20, 26, 0.78)',
    borderColor: 'rgba(255, 255, 255, 0.28)',
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 18,
    paddingVertical: 10,
  },
  fullscreenButtonActive: {
    backgroundColor: 'rgba(42, 168, 137, 0.9)',
    borderColor: '#2aa889',
  },
  fullscreenButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
});

export default App;
