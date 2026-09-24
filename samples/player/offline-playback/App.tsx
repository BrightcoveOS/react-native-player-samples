import { useEffect, useState } from 'react';
import {
  BrightcovePlayerView,
  OfflinePlayback,
  type OfflineDownload,
} from '@brightcove/react-native-player';
import {
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

// Native SDK test assets with offline_enabled=true and both HTTPS HLS (iOS)
// and DASH (Android) sources. The generic player demos are not downloadable.
const DEMO_ACCOUNT_ID = '4800266849001';
const DEMO_POLICY_KEY =
  'BCpkADawqM3n0ImwKortQqSZCgJMcyVbb8lJVwt0z16UD0a_h8MpEYcHyKbM8CGOPxBRp0nfSVdfokXBrUu3Sso7Nujv3dnLo0JxC_lNXCl88O7NJ0PR0z2AprnJ_Lwnq7nTcy1GBUrQPr5e';

const DEMO_QUEUE = [
  { videoId: '1823870923251322266', title: 'Punisher' },
  { videoId: '1767327231984365476', title: 'Redpoll with captions' },
] as const;

type Status =
  | { kind: 'loading'; message: string }
  | { kind: 'ready'; message: string }
  | { kind: 'error'; message: string };

function replaceDownload(
  downloads: readonly OfflineDownload[],
  next: OfflineDownload,
): OfflineDownload[] {
  if (next.state === 'removed') {
    return downloads.filter(item => item.localId !== next.localId);
  }
  const index = downloads.findIndex(item => item.localId === next.localId);
  if (index < 0) return [...downloads, next];
  return downloads.map(item => (item.localId === next.localId ? next : item));
}

function progressLabel(download: OfflineDownload): string {
  if (download.state === 'completed') return 'Downloaded';
  if (download.progress === undefined) return download.state;
  return `${download.state} ${Math.round(download.progress)}%`;
}

function App() {
  const [downloads, setDownloads] = useState<OfflineDownload[]>([]);
  const [selectedOfflineId, setSelectedOfflineId] = useState<string | null>(null);
  const [status, setStatus] = useState<Status>({
    kind: 'loading',
    message: 'Restoring persisted downloads',
  });

  useEffect(() => {
    let mounted = true;
    OfflinePlayback.listDownloads()
      .then(items => {
        if (!mounted) return;
        setDownloads(items);
        setStatus({
          kind: 'ready',
          message: items.length === 0 ? 'No local downloads yet' : 'Downloads restored',
        });
      })
      .catch((error: Error) => {
        if (mounted) {
          setStatus({ kind: 'error', message: error.message });
        }
      });

    const subscription = OfflinePlayback.addDownloadChangedListener(download => {
      if (!mounted) return;
      setDownloads(items => replaceDownload(items, download));
      if (download.state === 'failed' && download.error !== undefined) {
        setStatus({
          kind: 'error',
          message: `${download.error.code}: ${download.error.message}`,
        });
      }
      if (download.state === 'removed') {
        setSelectedOfflineId(current =>
          current === download.localId ? null : current,
        );
      }
    });

    return () => {
      mounted = false;
      subscription.remove();
    };
  }, []);

  const requestOne = async () => {
    try {
      const accepted = await OfflinePlayback.requestDownload({
        accountId: DEMO_ACCOUNT_ID,
        policyKey: DEMO_POLICY_KEY,
        videoId: DEMO_QUEUE[0].videoId,
      });
      setDownloads(items => replaceDownload(items, accepted));
      setStatus({ kind: 'ready', message: 'Download request accepted' });
    } catch (error) {
      setStatus({ kind: 'error', message: (error as Error).message });
    }
  };

  const requestQueue = async () => {
    try {
      const accepted = await OfflinePlayback.requestDownloads(
        DEMO_QUEUE.map(item => ({
          accountId: DEMO_ACCOUNT_ID,
          policyKey: DEMO_POLICY_KEY,
          videoId: item.videoId,
        })),
      );
      setDownloads(items => accepted.reduce(replaceDownload, items));
      setStatus({
        kind: 'ready',
        message: `${accepted.length} download requests accepted`,
      });
    } catch (error) {
      setStatus({ kind: 'error', message: (error as Error).message });
    }
  };

  const removeDownload = async (download: OfflineDownload) => {
    try {
      await OfflinePlayback.removeDownload(download.localId);
      setDownloads(items => items.filter(item => item.localId !== download.localId));
      if (selectedOfflineId === download.localId) setSelectedOfflineId(null);
    } catch (error) {
      setStatus({ kind: 'error', message: (error as Error).message });
    }
  };

  const sourceIsOffline = selectedOfflineId !== null;

  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <SafeAreaView style={styles.screen}>
        <ScrollView contentContainerStyle={styles.content}>
          <View style={styles.header}>
          <Text style={styles.eyebrow}>PLAYER / OFFLINE PLAYBACK</Text>
          <Text style={styles.title}>Downloads that persist</Text>
          <Text style={styles.description}>
            Queue individual Video Cloud downloads while connected, restore their
            native status after relaunch, then play a completed item without the
            catalog or network.
          </Text>
          </View>

          <BrightcovePlayerView
          accountId={DEMO_ACCOUNT_ID}
          policyKey={DEMO_POLICY_KEY}
          videoId={sourceIsOffline ? '' : DEMO_QUEUE[0].videoId}
          offlineSourceId={selectedOfflineId ?? ''}
          autoPlay
          onReady={({ nativeEvent }) => {
            setStatus({
              kind: 'ready',
              message: `${sourceIsOffline ? 'Offline' : 'Online'} video ready: ${nativeEvent.videoId}`,
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

          <View style={styles.actions}>
          <Pressable onPress={requestOne} style={styles.primaryButton}>
            <Text style={styles.primaryButtonText}>Download selected</Text>
          </Pressable>
          <Pressable onPress={requestQueue} style={styles.secondaryButton}>
            <Text style={styles.secondaryButtonText}>Queue 2 downloads</Text>
          </Pressable>
          {sourceIsOffline ? (
            <Pressable
              onPress={() => setSelectedOfflineId(null)}
              style={styles.secondaryButton}
            >
              <Text style={styles.secondaryButtonText}>Play online</Text>
            </Pressable>
          ) : null}
          </View>

          <View style={styles.list}>
          <Text style={styles.listTitle}>On this device</Text>
          {downloads.length === 0 ? (
            <Text style={styles.empty}>No persisted downloads</Text>
          ) : (
            downloads.map(download => (
              <View key={download.localId} style={styles.downloadRow}>
                <View style={styles.downloadCopy}>
                  <Text style={styles.downloadId}>{download.videoId || download.localId}</Text>
                  <Text style={styles.downloadState}>{progressLabel(download)}</Text>
                  {download.licenseExpiresAt !== undefined ? (
                    <Text style={styles.expiry}>
                      Licence expires {new Date(download.licenseExpiresAt).toLocaleString()}
                    </Text>
                  ) : null}
                </View>
                {download.state === 'completed' ? (
                  <Pressable
                    onPress={() => setSelectedOfflineId(download.localId)}
                    style={styles.playButton}
                  >
                    <Text style={styles.playButtonText}>Play offline</Text>
                  </Pressable>
                ) : null}
                <Pressable
                  onPress={() => {
                    removeDownload(download);
                  }}
                  style={styles.removeButton}
                >
                  <Text style={styles.removeButtonText}>Remove</Text>
                </Pressable>
              </View>
            ))
          )}
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
    paddingHorizontal: 24,
  },
  content: {
    paddingBottom: 32,
  },
  header: {
    paddingBottom: 22,
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
  readyDot: { backgroundColor: '#2aa889' },
  errorDot: { backgroundColor: '#d4574e' },
  statusText: { color: '#5c6470', flex: 1, fontSize: 14 },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, marginTop: 20 },
  primaryButton: {
    backgroundColor: '#12141a',
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 11,
  },
  primaryButtonText: { color: '#ffffff', fontWeight: '700' },
  secondaryButton: {
    borderColor: '#d5d9df',
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 11,
  },
  secondaryButtonText: { color: '#3a414c', fontWeight: '700' },
  list: { marginTop: 26, paddingBottom: 24 },
  listTitle: { color: '#12141a', fontSize: 18, fontWeight: '700' },
  empty: { color: '#8a8f98', marginTop: 10 },
  downloadRow: {
    alignItems: 'center',
    borderBottomColor: '#eceef1',
    borderBottomWidth: 1,
    flexDirection: 'row',
    gap: 10,
    paddingVertical: 14,
  },
  downloadCopy: { flex: 1 },
  downloadId: { color: '#12141a', fontSize: 14, fontWeight: '600' },
  downloadState: { color: '#2aa889', fontSize: 13, marginTop: 3 },
  expiry: { color: '#d59a2e', fontSize: 12, marginTop: 3 },
  playButton: {
    borderColor: '#12141a',
    borderRadius: 9,
    borderWidth: 1,
    padding: 8,
  },
  playButtonText: { color: '#12141a', fontSize: 12, fontWeight: '700' },
  removeButton: { padding: 8 },
  removeButtonText: { color: '#d4574e', fontSize: 12, fontWeight: '700' },
});

export default App;
