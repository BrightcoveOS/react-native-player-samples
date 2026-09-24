import { useRef, useState } from 'react';
import { BrightcovePlayerView, PlayerCommands } from '@brightcove/react-native-player';
import type { ElementRef } from 'react';
import {
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaRoot } from './src/components/SafeAreaRoot';
import { PLAYER_CONFIG } from './src/playerConfig';

type CaptionTrack = { id: string; language: string; label: string };

function App() {
  const playerRef = useRef<ElementRef<typeof BrightcovePlayerView>>(null);
  const [status, setStatus] = useState('Loading demo video');
  const [fullscreen, setFullscreen] = useState(false);
  // Tracks the SDK reports for this video; empty until onCaptionsAvailable.
  const [tracks, setTracks] = useState<CaptionTrack[]>([]);
  // The two props that drive the native caption state. Selecting "Off" sets
  // enabled=false; selecting a track sets enabled=true + that track id.
  const [captionsEnabled, setCaptionsEnabled] = useState(false);
  const [captionTrackId, setCaptionTrackId] = useState('');

  const selectOff = () => {
    setCaptionsEnabled(false);
    setCaptionTrackId('');
  };
  const selectTrack = (id: string) => {
    setCaptionsEnabled(true);
    setCaptionTrackId(id);
  };

  return (
    <SafeAreaRoot style={styles.screen}>
    <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <View style={styles.header}>
        <Text style={styles.eyebrow}>PLAYER / CLOSED CAPTIONS</Text>
        <Text style={styles.title}>Captions</Text>
        <Text style={styles.description}>
          Enable, disable, and switch caption tracks from React Native — the
          native SDK renders them.
        </Text>
      </View>

      <BrightcovePlayerView
        ref={playerRef}
        accountId={PLAYER_CONFIG.accountId}
        policyKey={PLAYER_CONFIG.policyKey}
        videoId={PLAYER_CONFIG.videoId}
        autoPlay
        captionsEnabled={captionsEnabled}
        captionTrackId={captionTrackId}
        onFullscreenChanged={({ nativeEvent }) => {
          setFullscreen(nativeEvent.active);
        }}
        onReady={({ nativeEvent }) => {
          setStatus(`Ready video ${nativeEvent.videoId}`);
        }}
        onError={({ nativeEvent }) => {
          setStatus(`${nativeEvent.code}: ${nativeEvent.message}`);
        }}
        onCaptionsAvailable={({ nativeEvent }) => {
          setTracks(nativeEvent.tracks);
        }}
        onCaptionTrackChanged={({ nativeEvent }) => {
          // The native callback is authoritative (it also fires for changes
          // made through the player's own caption menu or AirPlay), so drive
          // the controlled state from it — this keeps the chips in sync no
          // matter who changed the track. Empty id means captions are off.
          const activeId = nativeEvent.id;
          setCaptionsEnabled(activeId.length > 0);
          setCaptionTrackId(activeId);
        }}
        style={styles.player}
      />

      <View style={styles.controls}>
        <Text style={styles.controlsLabel}>PLAYBACK CONTROLS</Text>
        <View style={styles.chips}>
          <Chip
            label={fullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
            active={fullscreen}
            onPress={() => {
              if (!playerRef.current) return;
              fullscreen
                ? PlayerCommands.exitFullscreen(playerRef.current)
                : PlayerCommands.enterFullscreen(playerRef.current);
            }}
          />
        </View>
        <Text style={styles.controlsLabel}>CAPTION TRACK</Text>
        <View style={styles.chips}>
          <Chip label="Off" active={!captionsEnabled} onPress={selectOff} />
          {tracks.map(track => (
            <Chip
              key={track.id}
              label={track.label}
              active={captionsEnabled && captionTrackId === track.id}
              onPress={() => selectTrack(track.id)}
            />
          ))}
        </View>
        {tracks.length === 0 && (
          <Text style={styles.hint}>No caption tracks on this video.</Text>
        )}
      </View>

      <View style={styles.status}>
        <View style={styles.statusDot} />
        <Text style={styles.statusText}>
          {status}
          {captionsEnabled && captionTrackId
            ? `  ·  captions: ${
                tracks.find(t => t.id === captionTrackId)?.label ?? captionTrackId
              }`
            : ''}
        </Text>
      </View>
    </SafeAreaRoot>
  );
}

function Chip({
  label,
  active,
  onPress,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.chip, active && styles.chipActive]}
    >
      <Text style={[styles.chipText, active && styles.chipTextActive]}>
        {label}
      </Text>
    </Pressable>
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
  controls: {
    marginTop: 24,
  },
  controlsLabel: {
    color: '#8a8f98',
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 1.1,
  },
  chips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 12,
  },
  chip: {
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 16,
    paddingVertical: 9,
  },
  chipActive: {
    backgroundColor: '#12141a',
    borderColor: '#12141a',
  },
  chipText: {
    color: '#3a414c',
    fontSize: 14,
    fontWeight: '600',
  },
  chipTextActive: {
    color: '#ffffff',
  },
  hint: {
    color: '#8a8f98',
    fontSize: 13,
    marginTop: 10,
  },
  status: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
    marginTop: 20,
  },
  statusDot: {
    backgroundColor: '#2aa889',
    borderRadius: 4,
    height: 8,
    width: 8,
  },
  statusText: {
    color: '#5c6470',
    flex: 1,
    fontSize: 14,
  },
});

export default App;
