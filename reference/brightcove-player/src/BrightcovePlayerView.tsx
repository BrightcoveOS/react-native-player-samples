import type { NativeProps } from './BrightcovePlayerViewNativeComponent';
import type { HostComponent } from 'react-native';
import type * as React from 'react';

export type BrightcovePlayerViewProps = NativeProps;

export type { RepeatMode } from './BrightcovePlayerViewNativeComponent';

export const BrightcovePlayerView = (function (
  _props: BrightcovePlayerViewProps,
): never {
  throw new Error(
    "'@brightcove/react-native-player' is only supported on native platforms."
  );
}) as unknown as HostComponent<BrightcovePlayerViewProps>;

const unsupportedPlatform = (): never => {
  throw new Error(
    "'@brightcove/react-native-player' commands are only supported on native platforms.",
  );
};

const FallbackCommands = {
  play(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  pause(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  seekTo(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
    _positionSeconds: number,
  ): void {
    unsupportedPlatform();
  },
  reload(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  enterFullscreen(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  exitFullscreen(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  enterPictureInPicture(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  seekToLiveEdge(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  next(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
  previous(
    _ref: React.ElementRef<HostComponent<BrightcovePlayerViewProps>>,
  ): void {
    unsupportedPlatform();
  },
};

export {
  FallbackCommands as Commands,
  FallbackCommands as PlayerCommands,
};
