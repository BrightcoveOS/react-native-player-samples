import React from 'react';
import {
  SafeAreaProvider,
  SafeAreaView,
  type NativeSafeAreaViewProps,
} from 'react-native-safe-area-context';
import { ScrollView, StyleSheet } from 'react-native';

export interface SafeAreaRootProps extends NativeSafeAreaViewProps {
  children?: React.ReactNode;
}

// A scrollable content root, mirroring the native SafeAreaRoot: small viewports
// and larger fonts must never push a sample's controls out of reach.
//
// On the web the browser window is the viewport, so the shared screen style
// (full-width, 24px horizontal padding — sized for a phone) would stretch the
// player and controls across a desktop monitor. Constrain the content to a
// centered column the width of a large phone/tablet so the web layout matches
// the native proportions instead of going full-bleed.
//
// react-native-safe-area-context's web build composes insets additively with
// the caller's padding, so the 24px paddingHorizontal a sample passes survives.
// (react-native-web's own SafeAreaView would instead overwrite that padding
// with env(safe-area-inset-*), which resolves to 0 on desktop and dropped the
// padding entirely.)
const MAX_CONTENT_WIDTH = 720;

export function SafeAreaRoot({ children, style, ...rest }: SafeAreaRootProps) {
  return (
    <SafeAreaProvider>
      <SafeAreaView style={[styles.root, style]} {...rest}>
        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}>
          {children}
        </ScrollView>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    alignSelf: 'center',
    flex: 1,
    maxWidth: MAX_CONTENT_WIDTH,
    width: '100%',
  },
  scroll: { flex: 1 },
  scrollContent: { paddingBottom: 40 },
});
