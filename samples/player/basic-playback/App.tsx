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

const PLAYBACK_RATES = [0.5, 1, 1.5, 2];

type PlayerStatus =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'error'; message: string };

type AudioTrackItem = {
  id: string;
  language: string;
  label: string;
};

function App() {
  const playerRef = useRef<ElementRef<typeof BrightcovePlayerView>>(null);
  const [status, setStatus] = useState<PlayerStatus>({
    kind: 'loading',
    message: 'Loading demo video',
  });
  const [fullscreen, setFullscreen] = useState(false);
  const [playbackRate, setPlaybackRate] = useState(1);
  const [audioTracks, setAudioTracks] = useState<AudioTrackItem[]>([]);
  const [selectedAudioTrackId, setSelectedAudioTrackId] = useState<string>('');
  const [activeAudioTrackId, setActiveAudioTrackId] = useState<string>('');
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);

  return (
    <SafeAreaRoot style={styles.screen}>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <View style={styles.header}>
        <Text style={styles.eyebrow}>PLAYER / BASIC PLAYBACK</Text>
        <Text style={styles.title}>Brightcove Player</Text>
        <Text style={styles.description}>
          One React Native component backed by Brightcove's native SDK.
        </Text>
      </View>

      <BrightcovePlayerView
        ref={playerRef}
        accountId={PLAYER_CONFIG.accountId}
        policyKey={PLAYER_CONFIG.policyKey}
        videoId={PLAYER_CONFIG.videoId}
        autoPlay
        playbackRate={playbackRate}
        volume={volume}
        muted={muted}
        onFullscreenChanged={({ nativeEvent }) => {
          setFullscreen(nativeEvent.active);
        }}
        audioTrackId={selectedAudioTrackId}
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
        onAudioTracksAvailable={({ nativeEvent }) => {
          setAudioTracks(nativeEvent.tracks);
        }}
        onAudioTrackChanged={({ nativeEvent }) => {
          setActiveAudioTrackId(nativeEvent.id);
        }}
        style={styles.player}
      />

      <View style={styles.controls}>
        <Text style={styles.controlsLabel}>PLAYBACK CONTROLS</Text>
        <View style={styles.controlRow}>
          {[0, 0.5, 1].map(value => (
            <Pressable
              key={value}
              testID={`volume-${value}`}
              onPress={() => setVolume(value)}
              style={[styles.controlButton, volume === value && styles.controlButtonActive]}
            >
              <Text style={[styles.controlButtonText, volume === value && styles.controlButtonTextActive]}>
                {value * 100}%
              </Text>
            </Pressable>
          ))}
          <Pressable
            testID="fullscreen-toggle"
            onPress={() => {
              if (!playerRef.current) return;
              fullscreen
                ? PlayerCommands.exitFullscreen(playerRef.current)
                : PlayerCommands.enterFullscreen(playerRef.current);
            }}
            style={[styles.controlButton, fullscreen && styles.controlButtonActive]}
          >
            <Text style={[styles.controlButtonText, fullscreen && styles.controlButtonTextActive]}>
              {fullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
            </Text>
          </Pressable>
          <Pressable
            testID="mute-toggle"
            onPress={() => setMuted(value => !value)}
            style={[styles.controlButton, muted && styles.controlButtonActive]}
          >
            <Text style={[styles.controlButtonText, muted && styles.controlButtonTextActive]}>
              {muted ? 'Unmute' : 'Mute'}
            </Text>
          </Pressable>
        </View>
        <Text style={styles.controlStatus}>
          Volume: {Math.round(volume * 100)}%  |  Muted: {muted ? 'Yes' : 'No'}
        </Text>
      </View>

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
      <View style={styles.rateRow}>
        {PLAYBACK_RATES.map((rate) => (
          <Pressable
            key={rate}
            testID={`rate-${rate}`}
            onPress={() => setPlaybackRate(rate)}
            style={[
              styles.rateChip,
              rate === playbackRate && styles.rateChipActive,
            ]}
          >
            <Text
              style={[
                styles.rateChipText,
                rate === playbackRate && styles.rateChipTextActive,
              ]}
            >
              {rate}x
            </Text>
          </Pressable>
        ))}
      </View>

      <View style={styles.audioSection}>
        <Text style={styles.audioSectionTitle}>Audio Tracks</Text>
        <View style={styles.trackList}>
          {audioTracks.length === 0 ? (
            <Text style={styles.noTracksText}>No audio tracks available</Text>
          ) : (
            audioTracks.map(track => {
              const isSelected = track.id === activeAudioTrackId || (selectedAudioTrackId === track.id);
              return (
                <Pressable
                  key={track.id}
                  testID={`audio-track-${track.id}`}
                  style={[
                    styles.trackButton,
                    isSelected && styles.trackButtonActive,
                  ]}
                  onPress={() => setSelectedAudioTrackId(track.id)}
                >
                  <Text
                    style={[
                      styles.trackButtonText,
                      isSelected && styles.trackButtonTextActive,
                    ]}
                  >
                    {track.label || track.id}
                  </Text>
                </Pressable>
              );
            })
          )}
        </View>
        {activeAudioTrackId ? (
          <Text style={styles.activeTrackText}>{`Active: ${activeAudioTrackId}`}</Text>
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
  controlRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 12,
  },
  controlButton: {
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  controlButtonActive: {
    backgroundColor: '#12141a',
    borderColor: '#12141a',
  },
  controlButtonText: {
    color: '#3a414c',
    fontSize: 13,
    fontWeight: '600',
  },
  controlButtonTextActive: {
    color: '#ffffff',
  },
  controlStatus: {
    color: '#5c6470',
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
  rateRow: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 18,
  },
  rateChip: {
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  rateChipActive: {
    backgroundColor: '#12141a',
    borderColor: '#12141a',
  },
  rateChipText: {
    color: '#3a414c',
    fontSize: 13,
    fontWeight: '600',
  },
  rateChipTextActive: {
    color: '#ffffff',
  },
  audioSection: {
    marginTop: 28,
  },
  audioSectionTitle: {
    color: '#12141a',
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 12,
  },
  trackList: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  noTracksText: {
    color: '#8a8f98',
    fontSize: 14,
  },
  trackButton: {
    backgroundColor: '#f4f5f7',
    borderColor: '#e4e6ea',
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 9,
  },
  trackButtonActive: {
    backgroundColor: '#12141a',
    borderColor: '#12141a',
  },
  trackButtonText: {
    color: '#3a414c',
    fontSize: 13,
    fontWeight: '500',
  },
  trackButtonTextActive: {
    color: '#ffffff',
    fontWeight: '600',
  },
  activeTrackText: {
    color: '#5c6470',
    fontSize: 13,
    marginTop: 10,
  },
});

export default App;
