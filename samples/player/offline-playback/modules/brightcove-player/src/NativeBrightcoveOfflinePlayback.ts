import { TurboModuleRegistry, type TurboModule } from 'react-native';
import type {
  Double,
  EventEmitter,
} from 'react-native/Libraries/Types/CodegenTypes';

/**
 * Raw, codegen-friendly representation of a persisted native download. Values
 * that a platform cannot determine use documented sentinels rather than
 * pretending they are known: progress/totalBytes use -1, and strings use "".
 * OfflinePlayback maps those to ergonomic optional JS fields before exporting
 * them to consumers.
 */
export type NativeOfflineDownload = Readonly<{
  localId: string;
  videoId: string;
  state: string;
  progress: Double;
  bytesDownloaded: Double;
  totalBytes: Double;
  licenseExpiresAt: string;
  code: string;
  message: string;
  nativeCode: string;
}>;

/**
 * App-scoped, durable offline-download manager. This is intentionally a
 * TurboModule rather than a prop on BrightcovePlayerView: native downloads
 * survive any one view, React reload, and app process recreation, and their
 * persisted state is the native SDK's source of truth.
 */
export interface Spec extends TurboModule {
  readonly onOfflineDownloadChanged: EventEmitter<NativeOfflineDownload>;

  requestDownload(
    accountId: string,
    policyKey: string,
    videoId: string,
  ): Promise<NativeOfflineDownload>;
  listDownloads(): Promise<NativeOfflineDownload[]>;
  pauseDownload(localId: string): Promise<void>;
  resumeDownload(localId: string): Promise<void>;
  cancelDownload(localId: string): Promise<void>;
  removeDownload(localId: string): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>(
  'BrightcoveOfflinePlayback',
);
