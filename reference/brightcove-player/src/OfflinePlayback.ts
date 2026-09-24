import type { EventSubscription } from 'react-native';

import NativeBrightcoveOfflinePlayback, {
  type NativeOfflineDownload,
} from './NativeBrightcoveOfflinePlayback';

/** The normalized state of one durable native download. */
export type OfflineDownloadState =
  | 'queued'
  | 'downloading'
  | 'paused'
  | 'completed'
  | 'failed'
  | 'cancelled'
  | 'cancelling'
  | 'deleting'
  | 'removed';

/** Identifiers needed to resolve an online Video Cloud asset for download. */
export type OfflineDownloadRequest = Readonly<{
  accountId: string;
  policyKey: string;
  videoId: string;
}>;

/**
 * A native-SDK-persisted download. `localId` is opaque: Android currently uses
 * the Video Cloud video ID while iOS uses BCOVOfflineVideoToken. Persist and
 * pass it back unchanged; do not derive meaning from its format.
 */
export type OfflineDownload = Readonly<{
  localId: string;
  videoId: string;
  state: OfflineDownloadState;
  progress?: number;
  bytesDownloaded: number;
  totalBytes?: number;
  licenseExpiresAt?: string;
  error?: Readonly<{
    code: string;
    message: string;
    nativeCode: string;
  }>;
}>;

function asOfflineDownload(value: NativeOfflineDownload): OfflineDownload {
  const hasError = value.code.length > 0;
  return {
    localId: value.localId,
    videoId: value.videoId,
    state: value.state as OfflineDownloadState,
    progress: value.progress < 0 ? undefined : value.progress,
    bytesDownloaded: value.bytesDownloaded,
    totalBytes: value.totalBytes < 0 ? undefined : value.totalBytes,
    licenseExpiresAt:
      value.licenseExpiresAt.length === 0 ? undefined : value.licenseExpiresAt,
    error: hasError
      ? {
          code: value.code,
          message: value.message,
          nativeCode: value.nativeCode,
        }
      : undefined,
  };
}

/**
 * Durable native offline-download operations. `requestDownload` accepts one
 * item because neither shipped SDK exposes an atomic batch/scheduling API.
 * `requestDownloads` is a convenience that accepts each item serially; it only
 * means each request was accepted, not that their transfers will complete in
 * order or survive force-quit.
 */
export const OfflinePlayback = {
  requestDownload: async (
    request: OfflineDownloadRequest,
  ): Promise<OfflineDownload> =>
    asOfflineDownload(
      await NativeBrightcoveOfflinePlayback.requestDownload(
        request.accountId,
        request.policyKey,
        request.videoId,
      ),
    ),

  requestDownloads: async (
    requests: readonly OfflineDownloadRequest[],
  ): Promise<OfflineDownload[]> => {
    const accepted: OfflineDownload[] = [];
    for (const request of requests) {
      accepted.push(await OfflinePlayback.requestDownload(request));
    }
    return accepted;
  },

  listDownloads: async (): Promise<OfflineDownload[]> =>
    (await NativeBrightcoveOfflinePlayback.listDownloads()).map(asOfflineDownload),

  pauseDownload: (localId: string): Promise<void> =>
    NativeBrightcoveOfflinePlayback.pauseDownload(localId),

  resumeDownload: (localId: string): Promise<void> =>
    NativeBrightcoveOfflinePlayback.resumeDownload(localId),

  cancelDownload: (localId: string): Promise<void> =>
    NativeBrightcoveOfflinePlayback.cancelDownload(localId),

  removeDownload: (localId: string): Promise<void> =>
    NativeBrightcoveOfflinePlayback.removeDownload(localId),

  addDownloadChangedListener: (
    listener: (download: OfflineDownload) => void,
  ): EventSubscription =>
    NativeBrightcoveOfflinePlayback.onOfflineDownloadChanged((download) => {
      listener(asOfflineDownload(download));
    }),
};
