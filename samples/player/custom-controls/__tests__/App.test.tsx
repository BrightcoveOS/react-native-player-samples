/**
 * @format
 */

import React from "react";
import ReactTestRenderer, { type ReactTestInstance } from "react-test-renderer";
import { Text } from "react-native";

jest.mock("react-native-safe-area-context", () => {
  const ReactModule = require("react");
  const passthrough = ({ children }: { children: React.ReactNode }) =>
    ReactModule.createElement(ReactModule.Fragment, null, children);
  return { SafeAreaProvider: passthrough, SafeAreaView: passthrough };
});

type PlayerProps = {
  accountId: string;
  policyKey: string;
  videoId: string;
  controlsEnabled?: boolean;
  volume?: number;
  muted?: boolean;
  autoPlay?: boolean;
  onFullscreenChanged?: (e: { nativeEvent: { active: boolean } }) => void;
  onReady?: (e: { nativeEvent: { videoId: string } }) => void;
  onError?: (e: {
    nativeEvent: { code: string; message: string; nativeCode: string };
  }) => void;
};

let lastPlayerProps: PlayerProps | undefined;
const mockEnterFullscreen = jest.fn();
const mockExitFullscreen = jest.fn();

jest.mock("@brightcove/react-native-player", () => {
  const ReactModule = require("react");
  return {
    __esModule: true,
    BrightcovePlayerView: ReactModule.forwardRef(
      (props: PlayerProps, ref: React.Ref<unknown>) => {
        lastPlayerProps = props;
        ReactModule.useImperativeHandle(ref, () => ({}));
        return null;
      },
    ),
    PlayerCommands: {
      enterFullscreen: (...args: unknown[]) => mockEnterFullscreen(...args),
      exitFullscreen: (...args: unknown[]) => mockExitFullscreen(...args),
    },
  };
});

import App from "../App";

const statusText = (tree: ReactTestInstance): string => {
  const parts: string[] = [];
  const collect = (child: unknown): void => {
    if (typeof child === "string" || typeof child === "number") {
      parts.push(String(child));
    } else if (Array.isArray(child)) {
      child.forEach(collect);
    } else if (child && typeof child === "object" && "props" in child) {
      collect((child as { props: { children?: unknown } }).props.children);
    }
  };
  tree.findAllByType(Text).forEach(node => collect(node.props.children));
  return parts.join(" ");
};

const pressableByLabel = (
  tree: ReactTestInstance,
  label: string,
): ReactTestInstance =>
  tree
    .findAll(
      node =>
        typeof node.props.onPress === "function" &&
        statusText(node).includes(label),
    )
    .at(-1)!;

beforeEach(() => {
  lastPlayerProps = undefined;
  mockEnterFullscreen.mockClear();
  mockExitFullscreen.mockClear();
});

test("renders initial state with controlsEnabled false", async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps).toBeDefined();
  expect(lastPlayerProps!.accountId).toBe("6415855237001");
  expect(lastPlayerProps!.videoId).toBe("6393164822112");
  expect(lastPlayerProps!.controlsEnabled).toBe(false);
  expect(lastPlayerProps!.volume).toBe(1.0);
  expect(lastPlayerProps!.muted).toBe(false);
  expect(statusText(renderer.root)).toContain("Loading demo video");
});

test("updates volume when volume buttons are pressed", async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    pressableByLabel(renderer.root, "50%").props.onPress();
  });

  expect(lastPlayerProps!.volume).toBe(0.5);
  expect(statusText(renderer.root)).toContain("Vol: 50%");

  await ReactTestRenderer.act(() => {
    pressableByLabel(renderer.root, "Mute (0%)").props.onPress();
  });

  expect(lastPlayerProps!.volume).toBe(0.0);
  expect(statusText(renderer.root)).toContain("Vol: 0%");
});

test("toggles mute when mute button is pressed", async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps!.muted).toBe(false);

  await ReactTestRenderer.act(() => {
    pressableByLabel(renderer.root, "Mute").props.onPress();
  });

  expect(lastPlayerProps!.muted).toBe(true);
  expect(statusText(renderer.root)).toContain("Muted: Yes");

  await ReactTestRenderer.act(() => {
    pressableByLabel(renderer.root, "Unmute").props.onPress();
  });

  expect(lastPlayerProps!.muted).toBe(false);
  expect(statusText(renderer.root)).toContain("Muted: No");
});

test("toggles native controls when toggle button is pressed", async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps!.controlsEnabled).toBe(false);
  await ReactTestRenderer.act(() => {
    pressableByLabel(renderer.root, "Hidden").props.onPress();
  });
  expect(lastPlayerProps!.controlsEnabled).toBe(true);
});

test("fullscreen enables native controls before entering and restores them on exit", async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(lastPlayerProps!.controlsEnabled).toBe(false);
  await ReactTestRenderer.act(() => {
    pressableByLabel(renderer.root, "Fullscreen").props.onPress();
  });

  // The first commit makes the native SDK exit control reachable; the effect
  // then issues fullscreen against that committed player configuration.
  expect(lastPlayerProps!.controlsEnabled).toBe(true);
  expect(mockEnterFullscreen).toHaveBeenCalledTimes(1);

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onFullscreenChanged?.({ nativeEvent: { active: true } });
  });
  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onFullscreenChanged?.({ nativeEvent: { active: false } });
  });

  expect(lastPlayerProps!.controlsEnabled).toBe(false);
});

test("onReady updates status message", async () => {
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(() => {
    lastPlayerProps!.onReady?.({ nativeEvent: { videoId: "6393164822112" } });
  });

  expect(statusText(renderer.root)).toContain("Ready video 6393164822112");
});
