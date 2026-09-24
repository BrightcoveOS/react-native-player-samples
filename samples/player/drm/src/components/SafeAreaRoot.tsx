import React from 'react';
import {
  SafeAreaProvider,
  SafeAreaView,
  type NativeSafeAreaViewProps,
} from 'react-native-safe-area-context';
import { ScrollView } from 'react-native';

export interface SafeAreaRootProps extends NativeSafeAreaViewProps {
  children?: React.ReactNode;
}

// A scrollable content root: Fast Refresh, smaller devices, landscape, and
// larger accessibility font sizes can push a sample's controls past the
// viewport. Without this the controls become unreachable.
export function SafeAreaRoot({ children, style, ...rest }: SafeAreaRootProps) {
  return (
    <SafeAreaProvider>
      <SafeAreaView style={style} {...rest}>
        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}>
          {children}
        </ScrollView>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = {
  scroll: { flex: 1 },
  scrollContent: { paddingBottom: 40 },
} as const;
