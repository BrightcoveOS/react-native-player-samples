import { forwardRef, useMemo } from 'react';
import * as ImaClientSideIntegrationModule from '@brightcove/web-sdk/integrations/imaClientSide';
import * as ImaDaiIntegrationModule from '@brightcove/web-sdk/integrations/imaDai';
import * as SsaiIntegrationModule from '@brightcove/web-sdk/integrations/ssai';
import * as ThumbnailsIntegrationModule from '@brightcove/web-sdk/integrations/thumbnails';
import '@brightcove/web-sdk/integrations/imaClientSide/styles';
import '@brightcove/web-sdk/integrations/imaDai/styles';
import '@brightcove/web-sdk/integrations/ssai/styles';
import '@brightcove/web-sdk/integrations/thumbnails/styles';

import {
  BrightcovePlayerView as BrightcovePlayerViewWeb,
  createWebSdkPlayer,
  type BrightcovePlayerWebHandle,
  type BrightcovePlayerViewWebProps,
  type SidecarTrackInput,
  type WebSdkIntegrationFactories,
  type WebSdkPlayerOptions,
} from './BrightcovePlayerView.web';

const integrationFactories: WebSdkIntegrationFactories = {
  thumbnails: (
    ThumbnailsIntegrationModule as unknown as {
      ThumbnailsIntegrationFactory: unknown;
    }
  ).ThumbnailsIntegrationFactory,
  imaClientSide: (
    ImaClientSideIntegrationModule as unknown as {
      ImaClientSideIntegrationFactory: unknown;
    }
  ).ImaClientSideIntegrationFactory,
  imaDai: (ImaDaiIntegrationModule as unknown as {
    ImaDaiIntegrationFactory: unknown;
  }).ImaDaiIntegrationFactory,
  ssai: (SsaiIntegrationModule as unknown as {
    SsaiIntegrationFactory: unknown;
  }).SsaiIntegrationFactory,
};

const playerFactory = (options: WebSdkPlayerOptions) =>
  createWebSdkPlayer(options, integrationFactories);

export type BrightcovePlayerViewProps = Omit<
  BrightcovePlayerViewWebProps,
  'playerFactory'
>;

export type { SidecarTrackInput };

const WEB_CONTROL_BAR_COMPONENTS = [
  'PlayToggle',
  'VolumePanel',
  'CurrentTimeDisplay',
  'TimeDivider',
  'DurationDisplay',
  'ProgressControl',
  'CustomControlSpacer',
  'PlaybackRateMenuButton',
  'DescriptionsButton',
  'AudioTrackButton',
  'SubsCapsButton',
  'ChaptersButton',
  'FullscreenToggle',
  'LiveDisplay',
  'SeekToLive',
  'RemainingTimeDisplay',
];

export const BrightcovePlayerView = forwardRef<
  BrightcovePlayerWebHandle,
  BrightcovePlayerViewProps
>(function BrightcovePlayerViewWrapper(props, ref) {
  // A fresh array per render would be a new identity in the player's
  // mount-effect deps and dispose/recreate the player on every parent
  // re-render — memoize on the only input that changes the list.
  const webControlBarComponents = useMemo(
    () =>
      props.pictureInPictureEnabled
        ? [...WEB_CONTROL_BAR_COMPONENTS, 'PictureInPictureToggle']
        : WEB_CONTROL_BAR_COMPONENTS,
    [props.pictureInPictureEnabled],
  );
  return (
    <BrightcovePlayerViewWeb
      {...props}
      ref={ref}
      playerFactory={playerFactory}
      webControlBarComponents={webControlBarComponents}
    />
  );
});

export const PlayerCommands = {
  play(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.play !== 'function') return;
    try {
      const res = ref.play();
      if (res && typeof res.catch === 'function') {
        res.catch(error => {
          console.error('[BrightcovePlayerCommands] play failed', error);
        });
      }
    } catch (error) {
      console.error('[BrightcovePlayerCommands] play failed', error);
    }
  },
  pause(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.pause !== 'function') return;
    try {
      ref.pause();
    } catch (error) {
      console.error('[BrightcovePlayerCommands] pause failed', error);
    }
  },
  seekTo(
    ref: BrightcovePlayerWebHandle | null | undefined,
    positionSeconds: number,
  ): void {
    if (!ref || typeof ref.seekTo !== 'function') return;
    try {
      ref.seekTo(positionSeconds);
    } catch (error) {
      console.error('[BrightcovePlayerCommands] seekTo failed', error);
    }
  },
  enterFullscreen(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.enterFullscreen !== 'function') return;
    try {
      const res = ref.enterFullscreen();
      if (res && typeof res.catch === 'function') {
        res.catch(error => {
          console.error('[BrightcovePlayerCommands] enterFullscreen failed', error);
        });
      }
    } catch (error) {
      console.error('[BrightcovePlayerCommands] enterFullscreen failed', error);
    }
  },
  exitFullscreen(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.exitFullscreen !== 'function') return;
    try {
      const res = ref.exitFullscreen();
      if (res && typeof res.catch === 'function') {
        res.catch(error => {
          console.error('[BrightcovePlayerCommands] exitFullscreen failed', error);
        });
      }
    } catch (error) {
      console.error('[BrightcovePlayerCommands] exitFullscreen failed', error);
    }
  },
  enterPictureInPicture(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.enterPictureInPicture !== 'function') return;
    try {
      const res = ref.enterPictureInPicture();
      if (res && typeof res.catch === 'function') {
        res.catch(error => {
          console.error('[BrightcovePlayerCommands] enterPictureInPicture failed', error);
        });
      }
    } catch (error) {
      console.error('[BrightcovePlayerCommands] enterPictureInPicture failed', error);
    }
  },
  seekToLiveEdge(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.seekToLiveEdge !== 'function') return;
    try {
      ref.seekToLiveEdge();
    } catch (error) {
      console.error('[BrightcovePlayerCommands] seekToLiveEdge failed', error);
    }
  },
  next(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.next !== 'function') return;
    try {
      ref.next();
    } catch (error) {
      console.error('[BrightcovePlayerCommands] next failed', error);
    }
  },
  previous(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.previous !== 'function') return;
    try {
      ref.previous();
    } catch (error) {
      console.error('[BrightcovePlayerCommands] previous failed', error);
    }
  },
  reload(ref: BrightcovePlayerWebHandle | null | undefined): void {
    if (!ref || typeof ref.reload !== 'function') return;
    try {
      ref.reload();
    } catch (error) {
      console.error('[BrightcovePlayerCommands] reload failed', error);
    }
  },
};

export const Commands = PlayerCommands;
export const BrightcovePlayerCommands = PlayerCommands;
export const BrightcovePlayerViewCommands = PlayerCommands;

export type {
  PlayerCommandErrorCode,
  PlayerCommandErrorEventData,
  PlayerErrorCode,
  PlayerErrorEventData,
  ReadyEventData,
  SourceLoadingEventData,
  FirstFrameEventData,
  SeekStartedEventData,
  SeekCompletedEventData,
  DurationChangedEventData,
  VideoSizeChangedEventData,
  PlaybackProgressEventData,
  LiveStatusEventData,
  SeekableRangesChangedEventData,
  RepeatMode,
  VideoScalingMode,
  QueueItemChangedEventData,
  QueueItemFailedEventData,
  AudioDescriptionAvailableEventData,
  AudioDescriptionChangedEventData,
  RenditionChangedEventData,
  ChapterSeekCompletedEventData,
  CaptionsAvailableEventData,
  CaptionTrackChangedEventData,
  PictureInPictureModeChangedEventData,
  FullscreenChangedEventData,
  AdEventData,
  AdBreakEventData,
  AllAdsCompletedEventData,
  AudioTracksAvailableEventData,
  AudioTrackChangedEventData,
  TimedMetadataEventData,
  PreloadQueuedEventData,
  PreloadHandoffEventData,
  PreloadErrorEventData,
  AdPausedEventData,
  AdResumedEventData,
  AdProgressEventData,
  AdQuartileEventData,
  AdSkippedEventData,
  AdInteractionEventData,
  AdMetadataEventData,
  AdOverlayStateChangedEventData,
  AdErrorEventData,
  SidecarTrackStatusEventData,
  CaptionCueEventData,
} from './webErrorClassification';

export interface NativeCommands {
  play: (viewRef: unknown) => void;
  pause: (viewRef: unknown) => void;
  seekTo: (viewRef: unknown, positionSeconds: number) => void;
  enterFullscreen?: (viewRef: unknown) => void;
  exitFullscreen?: (viewRef: unknown) => void;
  enterPictureInPicture?: (viewRef: unknown) => void;
  seekToLiveEdge?: (viewRef: unknown) => void;
  next?: (viewRef: unknown) => void;
  previous?: (viewRef: unknown) => void;
  reload?: (viewRef: unknown) => void;
}
