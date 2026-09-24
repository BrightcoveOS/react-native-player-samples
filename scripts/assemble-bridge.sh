#!/usr/bin/env bash
# Assembles a bridge copy containing core plus a chosen set of features, from
# the canonical reference/brightcove-player. Makes "copy only what you need" a
# command rather than a manual ritual: it copies the right directories AND
# generates the three composition-root files (FeatureRegistry.kt,
# BrightcoveFeatureRegistry.mm, src/index.tsx) so the public prop surface and
# the installed features can never drift out of sync.
#
# Idempotent: re-running with the same --features reproduces byte-identical
# output. This is the single author of the composition-root files; do not
# hand-edit them.
#
# Usage:
#   scripts/assemble-bridge.sh --features ads <dest-module-dir>
#   scripts/assemble-bridge.sh --features captions <dest-module-dir>
#   scripts/assemble-bridge.sh --features drm <dest-module-dir>
#   scripts/assemble-bridge.sh --features pip <dest-module-dir>
#   scripts/assemble-bridge.sh --features ssai <dest-module-dir>
#   scripts/assemble-bridge.sh --features "" <dest>      # core only
#
# <dest-module-dir> is the sample's modules/brightcove-player directory.
set -euo pipefail

# Resolve the caller's working directory before changing into the repository:
# a relative <dest-module-dir> is relative to where the user ran the script, not
# to the repository. Resolving it here (and cd'ing after) keeps a documented
# relative invocation — e.g. run from an exported sample as
# `.../scripts/assemble-bridge.sh --features captions modules/brightcove-player`
# — writing to that sample instead of silently creating a module under the repo.
invocation_dir="$(pwd)"

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
REFERENCE="reference/brightcove-player"

# Feature catalog (props, event types, native class names) is shared with
# check-bridge-copies.sh so adding a feature is a single edit there.
# shellcheck source=scripts/feature-catalog.sh
. "$(dirname "$0")/feature-catalog.sh"

# --- Args --------------------------------------------------------------------
features=""
dest=""
while [ $# -gt 0 ]; do
  case "$1" in
    --features) features="$2"; shift 2 ;;
    *) dest="$1"; shift ;;
  esac
done
[ -n "$dest" ] || { echo "usage: $0 --features a,b <dest-module-dir>" >&2; exit 2; }

# Make the destination absolute against the caller's directory, then refuse a
# destination that would clobber the repository or its inputs. A relative path
# was previously interpreted against the repository root, so this both fixes the
# documented form and fails loudly on a destination pointed at the reference or
# the repo itself rather than overwriting it.
case "$dest" in
  /*) ;;
  *) dest="$invocation_dir/$dest" ;;
esac
mkdir -p "$(dirname "$dest")"
dest="$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"
case "$dest" in
  ""|"/"|"$REPO_ROOT"|"$REPO_ROOT/"|"$REPO_ROOT/$REFERENCE"|"$REPO_ROOT/$REFERENCE/"*)
    echo "refusing destination '$dest': points at the repository root or the reference bridge" >&2
    exit 2 ;;
esac

# Normalize comma/space separated feature list.
selected="$(echo "$features" | tr ',' ' ')"

is_selected() { case " $selected " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

if [ "$(type -t feature_conflicts 2>/dev/null || true)" = "function" ] || declare -f feature_conflicts >/dev/null 2>&1; then
  for f1 in $selected; do
    for f2 in $selected; do
      if [ "$f1" != "$f2" ] && feature_conflicts "$f1" "$f2"; then
        echo "conflicting features: $f1 and $f2 cannot be installed together" >&2
        exit 2
      fi
    done
  done
fi

ANDROID="android/src/main/java/com/brightcove/reactnativeplayer"
ANDROID_TEST="android/src/test/java/com/brightcove/reactnativeplayer"

# Validate each requested feature: it must be a known catalog entry AND its
# directories must actually exist in this reference. The catalog is
# forward-looking (it can list features not yet present on this branch), so
# check the reference on disk too and fail with a clear message rather than a
# cryptic cp error mid-assembly.
for f in $selected; do
  case " $ALL_FEATURES " in
    *" $f "*) ;;
    *) echo "unknown feature '$f' (known: $ALL_FEATURES)" >&2; exit 2 ;;
  esac
  if feature_supports_android "$f" && [ ! -d "$REFERENCE/$ANDROID/$f" ]; then
    echo "feature '$f' is not present in $REFERENCE (expected $ANDROID/$f)" >&2
    exit 2
  fi
  if feature_supports_ios "$f" && [ ! -d "$REFERENCE/ios/$f" ]; then
    echo "feature '$f' is not present in $REFERENCE (expected ios/$f)" >&2
    exit 2
  fi
done

# Files the script must not copy from the reference into a sample:
#   - README.md is sample-owned (left untouched if present).
#   - src/index.tsx, FeatureRegistry.kt, BrightcoveFeatureRegistry.mm are the
#     generated composition roots, written fresh below.
#   - .eslintrc.js / tsconfig.json are reference-only dev config; samples lint
#     and typecheck through their own root config, so these do not belong in a
#     sample's bridge module at all.
is_reference_only() {
  case "$1" in
    ./.eslintrc.js|./tsconfig.json) return 0 ;;
    ./package-lock.json) return 0 ;;
    ./ios/tests|./ios/tests/*) return 0 ;;
    # The reference gradle/podspec drive the full consumer-gated feature
    # matrix (vendor sets chosen by consumer properties); a sample's bridge
    # copy uses the plain marker-based shape this script generates below, so
    # the reference versions are never copied through.
    ./android/build.gradle|./BrightcovePlayer.podspec) return 0 ;;
    ./src/OfflinePlayback.ts|./src/NativeBrightcoveOfflinePlayback.ts)
      if ! is_selected offline; then return 0; else return 1; fi ;;
    ./src/BrightcovePlayerView.web.tsx|./src/webErrorClassification.ts)
      # Web player runtime files are only needed in samples configured for
      # web: a webpack config (bundler-driven web build) or a direct
      # @brightcove/web-sdk dependency (jest-jsdom coverage without a bundle).
      if [ -f "$dest/../../webpack.config.js" ] || grep -q '"@brightcove/web-sdk"' "$dest/../../package.json" 2>/dev/null; then return 1; else return 0; fi ;;
    *) return 1 ;;
  esac
}
is_sample_owned() {
  case "$1" in
    ./README.md) return 0 ;;
    ./package.json) return 0 ;;
    ./src/index.tsx) return 0 ;;
    ./src/index.ios.tsx) return 0 ;;
    ./src/index.web.tsx) return 0 ;;
    ./android/src/main/java/com/brightcove/reactnativeplayer/FeatureRegistry.kt) return 0 ;;
    ./ios/BrightcoveFeatureRegistry.mm) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Copy core + shared files, then selected feature directories -------------
# Remove only the bridge-managed parts, preserving sample-owned files that
# already exist (README/tsconfig/.eslintrc). Feature dirs and generated
# composition roots are rewritten below. The set of feature directories is
# derived from ALL_FEATURES (the catalog), not hardcoded, so adding a feature
# is a single edit in feature-catalog.sh and never a change to this assembler.
# Offline's TS surface is feature-scoped like a feature dir: a copy without
# the offline feature must not carry it (a customer copies a sample wholesale),
# so a re-assembly purges it from pre-gating compositions as well.
mkdir -p "$dest"
rm -rf "$dest/$ANDROID/core" "$dest/ios/core"
if ! is_selected offline; then
  rm -f "$dest/src/OfflinePlayback.ts" "$dest/src/NativeBrightcoveOfflinePlayback.ts"
fi
for f in $ALL_FEATURES; do
  rm -rf "$dest/$ANDROID/$f" "$dest/$ANDROID_TEST/$f" "$dest/ios/$f"
done

# Everything except the per-feature dirs and sample-owned files. Prune every
# feature directory named in the catalog so the generic copy never traverses a
# feature into a sample; selected features are copied explicitly below. Keep
# arguments in an array: building a shell string then expanding it unquoted
# would preserve quote characters in -path patterns and silently disable
# pruning.
prune_args=()
for f in $ALL_FEATURES; do
  prune_args+=(-path "./$ANDROID/$f" -prune -o -path "./$ANDROID_TEST/$f" -prune -o -path "./ios/$f" -prune -o)
done
prune_args+=(-path "./ios/tests" -prune -o -path "./node_modules" -prune -o)
( cd "$REFERENCE" && find . "${prune_args[@]}" -type f -print ) | while IFS= read -r rel; do
  is_reference_only "$rel" && continue
  if is_sample_owned "$rel"; then
    if [ "$rel" = "./package.json" ] && [ ! -f "$dest/$rel" ]; then
      # Fresh composition (e.g. a CI scratch copy): seed the module with the
      # sample-shape package manifest — source main, lint/typecheck scripts —
      # matching the reference manifest, so a fresh bridge copy is installable
      # as part of the embedding sample.
      cat > "$dest/$rel" <<'PKGJSON'
{
  "name": "@brightcove/react-native-player",
  "version": "0.0.0",
  "private": true,
  "description": "React Native bridge for the Brightcove native player SDKs",
  "main": "src/index",
  "scripts": {
    "lint": "eslint src",
    "typecheck": "tsc --noEmit"
  },
  "codegenConfig": {
    "name": "BrightcovePlayerViewSpec",
    "type": "all",
    "jsSrcsDir": "src",
    "android": {
      "javaPackageName": "com.brightcove.reactnativeplayer"
    },
    "ios": {
      "components": {
        "BrightcovePlayerView": {
          "className": "BrightcovePlayerView"
        }
      }
    }
  },
  "author": "Brightcove",
  "license": "Apache-2.0",
  "homepage": "https://www.brightcove.com/",
  "peerDependencies": {
    "react": "19.2.3",
    "react-native": "0.86.2"
  }
}
PKGJSON
    fi
    continue
  fi
  mkdir -p "$dest/$(dirname "$rel")"
  cp "$REFERENCE/$rel" "$dest/$rel"
done

# Copy each selected feature directory. Remove any existing destination dir
# first: BSD cp -R into an existing directory nests the source inside it
# (dest/ios/captions/captions), so a re-run or a stale dir would silently
# double-nest.
for f in $selected; do
  rm -rf "$dest/$ANDROID/$f" "$dest/$ANDROID_TEST/$f" "$dest/ios/$f"
  mkdir -p "$dest/$ANDROID" "$dest/$ANDROID_TEST" "$dest/ios"
  if feature_supports_android "$f"; then
    cp -R "$REFERENCE/$ANDROID/$f" "$dest/$ANDROID/$f"
    if [ -d "$REFERENCE/$ANDROID_TEST/$f" ]; then
      cp -R "$REFERENCE/$ANDROID_TEST/$f" "$dest/$ANDROID_TEST/$f"
    fi
  fi
  if feature_supports_ios "$f"; then
    cp -R "$REFERENCE/ios/$f" "$dest/ios/$f"
  fi
  if [ "$f" = "offline" ]; then
    cp "$REFERENCE/src/NativeBrightcoveOfflinePlayback.ts" "$dest/src/NativeBrightcoveOfflinePlayback.ts"
    cp "$REFERENCE/src/OfflinePlayback.ts" "$dest/src/OfflinePlayback.ts"
  fi
done

# Android NativeModules are feature-scoped too. Build the selected list once so
# the generated registry, package registration, and Gradle dependency script
# all use exactly the same feature catalog entry.
selected_modules=()
for f in $selected; do
  if feature_supports_android "$f"; then
    module="$(feature_kotlin_module "$f")"
    [ -n "$module" ] && selected_modules+=("$module")
  fi
done

# --- Generate FeatureRegistry.kt --------------------------------------------
android_selected=""
for f in $selected; do
  if feature_supports_android "$f"; then
    android_selected="$android_selected $f"
  fi
done
{
  echo "package com.brightcove.reactnativeplayer"
  echo ""
  for f in $android_selected; do
    echo "import $(feature_kotlin_class "$f")"
  done
  # bash 3.2 (macOS's stock /bin/bash) treats "${empty[@]}" as an unbound variable under
  # `set -u`, and only `offline` contributes a module — so an unguarded expansion here aborts
  # the generator for every other feature set. The two expansions further down sit inside an
  # `-eq 0` else-branch and cannot be empty; this one can.
  for module in ${selected_modules[@]+"${selected_modules[@]}"}; do echo "import $module"; done
  echo "import com.facebook.react.bridge.NativeModule"
  echo "import com.facebook.react.bridge.ReactApplicationContext"
  echo "import com.facebook.react.module.model.ReactModuleInfoProvider"
  if [ "${#selected_modules[@]}" -gt 0 ]; then
    echo "import com.facebook.react.module.annotations.ReactModule"
    echo "import com.facebook.react.module.model.ReactModuleInfo"
  fi
  echo "import com.brightcove.reactnativeplayer.core.PlayerFeature"
  echo ""
  echo "// Generated by scripts/assemble-bridge.sh. Do not edit by hand."
  echo "// Feature instances hold per-player state, so this is a factory (one"
  echo "// registry serves every player view in the app)."
  echo "object FeatureRegistry {"
  if [ -z "$android_selected" ]; then
    echo "  fun createFeatures(): List<PlayerFeature> = emptyList()"
  else
    echo "  fun createFeatures(): List<PlayerFeature> = listOf("
    for f in $android_selected; do
      cls="$(feature_kotlin_class "$f")"; echo "    ${cls##*.}(),"
    done
    echo "  )"
  fi
  echo ""
  if [ "${#selected_modules[@]}" -eq 0 ]; then
    echo "  fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> = emptyList()"
    echo "  fun createReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider { emptyMap() }"
  else
    echo "  fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> = listOf("
    for module in "${selected_modules[@]}"; do echo "    ${module##*.}(reactContext),"; done
    echo "  )"
    echo ""
    echo "  fun createReactModuleInfoProvider(): ReactModuleInfoProvider {"
    echo "    val moduleClasses = arrayOf<Class<out NativeModule>>("
    for module in "${selected_modules[@]}"; do echo "      ${module##*.}::class.java,"; done
    echo "    )"
    echo "    val moduleInfo = mutableMapOf<String, ReactModuleInfo>()"
    echo "    for (moduleClass in moduleClasses) {"
    echo "      val annotation = moduleClass.getAnnotation(ReactModule::class.java) ?: continue"
    echo "      moduleInfo[annotation.name] = ReactModuleInfo("
    echo "        annotation.name,"
    echo "        moduleClass.name,"
    echo "        true,"
    echo "        annotation.needsEagerInit,"
    echo "        annotation.isCxxModule,"
    echo "        true,"
    echo "      )"
    echo "    }"
    echo "    return ReactModuleInfoProvider { moduleInfo }"
    echo "  }"
  fi
  echo "}"
} > "$dest/$ANDROID/FeatureRegistry.kt"

# --- Generate BrightcoveFeatureRegistry.mm ----------------------------------
{
  echo "#import \"BrightcoveFeatureRegistry.h\""
  for f in $selected; do
    if feature_supports_ios "$f"; then
      echo "#import \"$(feature_objc "$f" | cut -d: -f1)\""
    fi
  done
  echo ""
  echo "// Generated by scripts/assemble-bridge.sh. Do not edit by hand."
  echo "@implementation BrightcoveFeatureRegistry"
  echo ""
  echo "+ (NSArray<id<BrightcovePlayerFeature>> *)installedFeatures"
  echo "{"
  if [ -z "$selected" ]; then
    echo "  return @[];"
  else
    echo "  return @["
    for f in $selected; do
      if feature_supports_ios "$f"; then
        echo "    [$(feature_objc "$f" | cut -d: -f2) new],"
      fi
    done
    echo "  ];"
  fi
  echo "}"
  echo ""
  echo "@end"
} > "$dest/ios/BrightcoveFeatureRegistry.mm"

# Imperative command surface: the core bridge always owns play/pause/seekTo/
# reload; every other command is advertised only when the feature that
# implements it is installed. A copy that exports the full NativeCommands
# surface without the feature sells a crash (feature_not_installed) through
# its own public API, so the command surface is narrowed like the props.
core_commands="play pause seekTo reload"
installed_commands=" $core_commands "
for f in $selected; do
  for c in $(feature_commands "$f"); do
    case " $installed_commands " in *" $c "*) continue ;; esac
    installed_commands="$installed_commands $c"
  done
done
installed_command_names=""
first=1
for c in $installed_commands; do
  if [ "$first" -eq 1 ]; then installed_command_names="'$c'"; first=0
  else installed_command_names="$installed_command_names | '$c'"; fi
done

# --- Generate src/index.tsx (Omit non-installed feature props) --------------
# A prop is omitted only if NO installed feature owns it. Features can share a
# prop (ads and ssai both own the onAd* events), so a prop owned by a
# non-selected feature must still be kept when a selected feature also owns it —
# otherwise the public type would hide a prop the copy actually services.
selected_props=" "
for f in $selected; do
  if feature_supports_android "$f"; then
    for p in $(feature_props "$f"); do selected_props="$selected_props$p "; done
  fi
done
omit_props=""
for f in $ALL_FEATURES; do
  if ! is_selected "$f" || ! feature_supports_android "$f"; then
    for p in $(feature_props "$f"); do
      # keep if a selected feature also owns it, or if already queued to omit
      case "$selected_props" in *" $p "*) continue ;; esac
      case " $omit_props " in *" $p "*) continue ;; esac
      omit_props="$omit_props $p"
    done
  fi
done
{
  echo "import type { HostComponent } from 'react-native';"
  echo "import { BrightcovePlayerView as FullBrightcovePlayerView } from './BrightcovePlayerView';"
  echo "import type { NativeProps, NativeCommands } from './BrightcovePlayerViewNativeComponent';"
  echo "import { Commands as PlayerCommandsImpl } from './BrightcovePlayerViewNativeComponent';"
  echo ""
  echo "// Generated by scripts/assemble-bridge.sh. Do not edit by hand."
  echo "// The Codegen spec and native ViewManager always declare every feature's"
  echo "// props; this copy narrows the public surface to the features it installs,"
  echo "// so an unavailable prop is a compile error, not a runtime throw."
  if [ -z "$omit_props" ]; then
    echo "export type BrightcovePlayerViewProps = NativeProps;"
  else
    echo "export type BrightcovePlayerViewProps = Omit<"
    echo "  NativeProps,"
    for p in $omit_props; do echo "  | '$p'"; done
    if is_selected offline || is_selected playlists || is_selected sourceloadingmodes; then
      echo ">;"
    else
      # The canonical Codegen spec makes videoId optional so offlineSourceId /
      # videoIds / alternate sourceloadingmodes props can be a complete source
      # on their own. A bridge copy with none of these installed must restore
      # the online-single-video invariant in its public type; otherwise a
      # customer gets a deterministic native invalid_configuration at runtime
      # for something TypeScript permitted.
      echo "> & {"
      echo "  videoId: string;"
      echo "};"
    fi
  fi
  echo ""
  echo "export const BrightcovePlayerView ="
  echo "  FullBrightcovePlayerView as unknown as HostComponent<BrightcovePlayerViewProps>;"
  echo ""
  echo "// Only the commands this copy can service (core + installed features)."
  echo "export type InstalledCommands = Pick<NativeCommands, $installed_command_names>;"
  echo "const InstalledCommandsImpl = PlayerCommandsImpl as InstalledCommands;"
  echo "export { InstalledCommandsImpl as PlayerCommands, InstalledCommandsImpl as Commands };"
  echo "export const {"
  for c in $installed_commands; do echo "  $c,"; done
  echo "} = InstalledCommandsImpl;"
  echo ""
  echo "export type {"
  echo "  PlayerCommandErrorCode,"
  echo "  PlayerCommandErrorEventData,"
  echo "  PlayerErrorCode,"
  echo "  PlayerErrorEventData,"
  echo "  ReadyEventData,"
  echo "  VideoScalingMode,"
  for f in $selected; do
    if feature_supports_android "$f"; then
      for t in $(feature_event_types "$f"); do echo "  $t,"; done
    fi
  done
  echo "} from './BrightcovePlayerViewNativeComponent';"
  if is_selected offline; then
    echo ""
    echo "export { OfflinePlayback } from './OfflinePlayback';"
    echo "export type {"
    echo "  OfflineDownload,"
    echo "  OfflineDownloadRequest,"
    echo "  OfflineDownloadState,"
    echo "} from './OfflinePlayback';"
  fi
} > "$dest/src/index.tsx"

# Generate an iOS-specific public entry point when an iOS-only feature is
# selected, or when a selected feature declares a prop its iOS SDK cannot back.
# Metro resolves index.ios.tsx on iOS and index.tsx on Android, so a prop that
# only one platform can service is omitted from the other platform's public
# types instead of advertising an input or event that can never fire there.
rm -f "$dest/src/index.ios.tsx"
ios_only_selected=0
for f in $selected; do
  if ! feature_supports_android "$f" && feature_supports_ios "$f"; then
    ios_only_selected=1
  fi
done

# Props a selected feature declares cross-platform but cannot service on iOS
# (feature_ios_unsupported_props). A prop stays exposed on iOS if a *selected*
# iOS feature that does not disown it also owns it, so a shared prop is not
# dropped because one owner cannot back it.
ios_unsupported_selected=""
for f in $selected; do
  feature_supports_ios "$f" || continue
  for p in $(feature_ios_unsupported_props "$f"); do
    case " $ios_unsupported_selected " in *" $p "*) continue ;; esac
    backed_elsewhere=0
    for g in $selected; do
      [ "$g" = "$f" ] && continue
      feature_supports_ios "$g" || continue
      case " $(feature_props "$g") " in *" $p "*) ;; *) continue ;; esac
      case " $(feature_ios_unsupported_props "$g") " in *" $p "*) continue ;; esac
      backed_elsewhere=1
    done
    [ "$backed_elsewhere" -eq 0 ] && ios_unsupported_selected="$ios_unsupported_selected $p"
  done
done

if [ "$ios_only_selected" -eq 1 ] || [ -n "$ios_unsupported_selected" ]; then
  ios_selected_props=" "
  for f in $selected; do
    if feature_supports_ios "$f"; then
      for p in $(feature_props "$f"); do ios_selected_props="$ios_selected_props$p "; done
    fi
  done
  ios_omit_props=""
  for f in $ALL_FEATURES; do
    if ! is_selected "$f" || ! feature_supports_ios "$f"; then
      for p in $(feature_props "$f"); do
        case "$ios_selected_props" in *" $p "*) continue ;; esac
        case " $ios_omit_props " in *" $p "*) continue ;; esac
        ios_omit_props="$ios_omit_props $p"
      done
    fi
  done
  for p in $ios_unsupported_selected; do
    case " $ios_omit_props " in *" $p "*) continue ;; esac
    ios_omit_props="$ios_omit_props $p"
  done
  {
    echo "import type { HostComponent } from 'react-native';"
    echo "import { BrightcovePlayerView as FullBrightcovePlayerView } from './BrightcovePlayerView';"
    echo "import type { NativeProps, NativeCommands } from './BrightcovePlayerViewNativeComponent';"
    echo "import { Commands as PlayerCommandsImpl } from './BrightcovePlayerViewNativeComponent';"
    echo ""
    echo "// Generated by scripts/assemble-bridge.sh. Do not edit by hand."
    echo "// iOS-only features are available from this platform-specific entry point."
    if [ -z "$ios_omit_props" ]; then
      echo "export type BrightcovePlayerViewProps = NativeProps;"
    else
      echo "export type BrightcovePlayerViewProps = Omit<"
      echo "  NativeProps,"
      for p in $ios_omit_props; do echo "  | '$p'"; done
      if is_selected offline || is_selected playlists || is_selected sourceloadingmodes; then
        echo ">;"
      else
        echo "> & {"
        echo "  videoId: string;"
        echo "};"
      fi
    fi
    echo ""
    echo "export const BrightcovePlayerView ="
    echo "  FullBrightcovePlayerView as unknown as HostComponent<BrightcovePlayerViewProps>;"
    echo ""
    echo "// Only the commands this copy can service (core + installed features)."
    echo "export type InstalledCommands = Pick<NativeCommands, $installed_command_names>;"
    echo "const InstalledCommandsImpl = PlayerCommandsImpl as InstalledCommands;"
    echo "export { InstalledCommandsImpl as PlayerCommands, InstalledCommandsImpl as Commands };"
    echo "export const {"
    for c in $installed_commands; do echo "  $c,"; done
    echo "} = InstalledCommandsImpl;"
    echo ""
    echo "export type {"
    echo "  PlayerCommandErrorCode,"
    echo "  PlayerCommandErrorEventData,"
    echo "  PlayerErrorCode,"
    echo "  PlayerErrorEventData,"
    echo "  ReadyEventData,"
    echo "  VideoScalingMode,"
    for f in $selected; do
      if feature_supports_ios "$f"; then
        for t in $(feature_event_types "$f"); do echo "  $t,"; done
      fi
    done
    echo "} from './BrightcovePlayerViewNativeComponent';"
    if is_selected offline; then
      echo ""
      echo "export { OfflinePlayback } from './OfflinePlayback';"
      echo "export type {"
      echo "  OfflineDownload,"
      echo "  OfflineDownloadRequest,"
      echo "  OfflineDownloadState,"
      echo "} from './OfflinePlayback';"
    fi
  } > "$dest/src/index.ios.tsx"
fi

# --- Generate src/index.web.tsx ---------------------------------------------
rm -f "$dest/src/index.web.tsx"
if [ -f "$dest/../../webpack.config.js" ]; then
web_selected_props=" "
for f in $selected; do
  for p in $(web_feature_props "$f"); do web_selected_props="$web_selected_props$p "; done
done
web_omit_props=""
for f in $ALL_WEB_FEATURES; do
  if ! is_selected "$f"; then
    for p in $(web_feature_props "$f"); do
      case "$web_selected_props" in *" $p "*) continue ;; esac
      case " $web_omit_props " in *" $p "*) continue ;; esac
      web_omit_props="$web_omit_props $p"
    done
  fi
done

web_control_bar_components="PlayToggle VolumePanel CurrentTimeDisplay TimeDivider DurationDisplay ProgressControl CustomControlSpacer PlaybackRateMenuButton"
for f in $selected; do
  for c in $(feature_web_control_bar_components "$f"); do
    case " $web_control_bar_components " in *" $c "*) continue ;; esac
    web_control_bar_components="$web_control_bar_components $c"
  done
done

web_integrations=""
for f in $selected; do
  for integration in $(feature_web_integrations "$f"); do
    case " $web_integrations " in
      *" $integration "*) ;;
      *) web_integrations="$web_integrations $integration" ;;
    esac
  done
done
{
  echo "import { forwardRef } from 'react';"
  for integration in $web_integrations; do
    module="$(feature_web_integration_import "$integration")"
    echo "import * as ${integration}IntegrationModule from '$module';"
    style_module="$(feature_web_integration_style_import "$integration")"
    echo "import '$style_module';"
  done
  echo "import {"
  echo "  BrightcovePlayerView as FullBrightcovePlayerView,"
  echo "  createWebSdkPlayer,"
  echo "  type BrightcovePlayerWebHandle,"
  echo "  type BrightcovePlayerViewWebProps,"
  echo "  type WebSdkIntegrationFactories,"
  echo "  type WebSdkPlayerOptions,"
  echo "} from './BrightcovePlayerView.web';"
  echo ""
  echo "// Generated by scripts/assemble-bridge.sh. Do not edit by hand."
  echo "// The web implementation provides a truthful browser path and narrows"
  echo "// its public props to the installed features of this sample."
  echo "// webControlBarComponents is always omitted here too: it is this"
  echo "// generated wrapper's own fixed list below, not something the"
  echo "// consuming App.tsx may override."
  echo "const WEB_INTEGRATION_FACTORIES: WebSdkIntegrationFactories = {};"
  for integration in $web_integrations; do
    factory="$(feature_web_integration_factory "$integration")"
    echo "WEB_INTEGRATION_FACTORIES.$integration = ("
    echo "  ${integration}IntegrationModule as unknown as { $factory: unknown }"
    echo ").$factory;"
  done
  echo "const playerFactory = (options: WebSdkPlayerOptions) =>"
  echo "  createWebSdkPlayer(options, WEB_INTEGRATION_FACTORIES);"
  echo ""
  echo "export type BrightcovePlayerViewProps = Omit<"
  echo "  BrightcovePlayerViewWebProps,"
  echo "  | 'webControlBarComponents'"
  echo "  | 'playerFactory'"
  for p in $web_omit_props; do echo "  | '$p'"; done
  echo ">;"
  echo ""
  echo "// The @brightcove/web-sdk/ui control-bar buttons this bridge copy"
  echo "// backs, computed from its installed features"
  echo "// (scripts/feature-catalog.sh feature_web_control_bar_components) so"
  echo "// the control bar never shows a button (e.g. Picture-in-Picture) for"
  echo "// a feature this copy never installed."
  echo "const WEB_CONTROL_BAR_COMPONENTS = ["
  for c in $web_control_bar_components; do echo "  '$c',"; done
  echo "];"
  echo ""
  echo "export const BrightcovePlayerView = forwardRef<"
  echo "  BrightcovePlayerWebHandle,"
  echo "  BrightcovePlayerViewProps"
  echo ">(function BrightcovePlayerViewWrapper(props, ref) {"
  echo "  return ("
  echo "    <FullBrightcovePlayerView"
  echo "      {...props}"
  echo "      ref={ref}"
  echo "      playerFactory={playerFactory}"
  echo "      webControlBarComponents={WEB_CONTROL_BAR_COMPONENTS}"
  echo "    />"
  echo "  );"
  echo "});"
  echo ""
  echo "// Only the commands this copy's installed features service on web."
  echo "export const PlayerCommands = {"
  for c in $installed_commands; do
    case "$c" in
      play)
        echo "  play(ref: BrightcovePlayerWebHandle | null | undefined): void {"
        echo "    if (!ref || typeof ref.play !== 'function') return;"
        echo "    try {"
        echo "      const res = ref.play();"
        echo "      if (res && typeof res.catch === 'function') {"
        echo "        res.catch(error => {"
        echo "          console.error('[BrightcovePlayerCommands] play failed', error);"
        echo "        });"
        echo "      }"
        echo "    } catch (error) {"
        echo "      console.error('[BrightcovePlayerCommands] play failed', error);"
        echo "    }"
        echo "  }," ;;
      pause)
        echo "  pause(ref: BrightcovePlayerWebHandle | null | undefined): void {"
        echo "    if (!ref || typeof ref.pause !== 'function') return;"
        echo "    try {"
        echo "      ref.pause();"
        echo "    } catch (error) {"
        echo "      console.error('[BrightcovePlayerCommands] pause failed', error);"
        echo "    }"
        echo "  }," ;;
      seekTo)
        echo "  seekTo("
        echo "    ref: BrightcovePlayerWebHandle | null | undefined,"
        echo "    positionSeconds: number,"
        echo "  ): void {"
        echo "    if (!ref || typeof ref.seekTo !== 'function') return;"
        echo "    try {"
        echo "      ref.seekTo(positionSeconds);"
        echo "    } catch (error) {"
        echo "      console.error('[BrightcovePlayerCommands] seekTo failed', error);"
        echo "    }"
        echo "  }," ;;
      reload)
        echo "  reload(ref: BrightcovePlayerWebHandle | null | undefined): void {"
        echo "    if (!ref || typeof ref.reload !== 'function') return;"
        echo "    try {"
        echo "      ref.reload();"
        echo "    } catch (error) {"
        echo "      console.error('[BrightcovePlayerCommands] reload failed', error);"
        echo "    }"
        echo "  }," ;;
      enterFullscreen|exitFullscreen|enterPictureInPicture)
        echo "  $c(ref: BrightcovePlayerWebHandle | null | undefined): void {"
        echo "    if (!ref || typeof ref.$c !== 'function') return;"
        echo "    try {"
        echo "      const res = ref.$c();"
        echo "      if (res && typeof res.catch === 'function') {"
        echo "        res.catch(error => {"
        echo "          console.error('[BrightcovePlayerCommands] $c failed', error);"
        echo "        });"
        echo "      }"
        echo "    } catch (error) {"
        echo "      console.error('[BrightcovePlayerCommands] $c failed', error);"
        echo "    }"
        echo "  }," ;;
      seekToLiveEdge|next)
        echo "  $c(ref: BrightcovePlayerWebHandle | null | undefined): void {"
        echo "    if (!ref || typeof ref.$c !== 'function') return;"
        echo "    try {"
        echo "      ref.$c();"
        echo "    } catch (error) {"
        echo "      console.error('[BrightcovePlayerCommands] $c failed', error);"
        echo "    }"
        echo "  }," ;;
      previous)
        # The web SDK handle exposes no previous(); playlists' web next() covers
        # queue advancement and previous is native-only.
        continue ;;
    esac
  done
  echo "};"
  echo ""
  echo "export const Commands = PlayerCommands;"
  echo ""
  echo "export type {"
  echo "  PlayerCommandErrorCode,"
  echo "  PlayerCommandErrorEventData,"
  echo "  PlayerErrorCode,"
  echo "  PlayerErrorEventData,"
  echo "  ReadyEventData,"
  echo "  VideoScalingMode,"
  for f in $selected; do
    for t in $(web_feature_event_types "$f"); do echo "  $t,"; done
  done
  echo "} from './webErrorClassification';"
  echo ""
  echo "export interface NativeCommands {"
  for c in $installed_commands; do
    case "$c" in
      seekTo) echo "  seekTo: (viewRef: unknown, positionSeconds: number) => void;" ;;
      previous) continue ;;
      *) echo "  $c: (viewRef: unknown) => void;" ;;
    esac
  done
  echo "}"
} > "$dest/src/index.web.tsx"
fi
# --- Generate native dependency files from the installed feature set ---------
# The sample build.gradle and BrightcovePlayer.podspec are generated composition
# roots, like FeatureRegistry.kt: a feature that needs an extra native SDK (ads
# -> android-ima-plugin / BrightcoveIMA) contributes its dependency ONLY when it
# is installed, so a core-only sample never ships an ad SDK. check-bridge-copies
# .sh validates these against the installed feature set instead of
# byte-comparing. (The reference's own gradle/podspec drive its full
# consumer-gated feature matrix and are never copied into a sample.)

spm_products="\"BrightcovePlayerSDK\""
for f in $selected; do
  for p in $(feature_spm_products "$f"); do spm_products="$spm_products, \"$p\""; done
done
{
  echo "require \"json\""
  echo ""
  echo "package = JSON.parse(File.read(File.join(__dir__, \"package.json\")))"
  echo ""
  echo "Pod::Spec.new do |s|"
  echo "  s.name         = \"BrightcovePlayer\""
  echo "  s.version      = package[\"version\"]"
  echo "  s.summary      = package[\"description\"]"
  echo "  s.homepage     = package[\"homepage\"]"
  echo "  s.license      = package[\"license\"]"
  echo "  s.authors      = package[\"author\"]"
  echo ""
  echo "  s.platforms    = { :ios => min_ios_version_supported }"
  echo "  s.source       = { :git => \".git\", :tag => \"#{s.version}\" }"
  echo ""
  echo "  s.source_files = \"ios/**/*.{h,m,mm,swift,cpp}\""
  echo "  s.private_header_files = \"ios/**/*.h\""
  echo ""
  echo "  # AVFoundation for playback errors and CoreMedia for CMTime progress values."
  echo "  s.frameworks = \"AVFoundation\", \"CoreMedia\""
  echo ""
  echo "  # BrightcoveIMA's public headers use \`@import BrightcovePlayerSDK;\` (an"
  echo "  # Objective-C module import). Files that include them are compiled as"
  echo "  # Objective-C++ here (the Fabric event emitter is C++), and a module import in"
  echo "  # that context needs C++ modules enabled — otherwise clang errors with \"use of"
  echo "  # '@import' when C++ modules are disabled\"."
  echo "  #"
  echo "  # pod_target_xcconfig applies only to this pod's own compilation, not to the"
  echo "  # app or other pods, so the blast radius is contained to BrightcovePlayer. The"
  echo "  # OTHER_CPLUSPLUSFLAGS value prepends \$(inherited) so it augments — never"
  echo "  # replaces — flags React Native already sets (e.g. the VFS overlay). A core /"
  echo "  # captions / pip bridge copy that never imports BrightcoveIMA is unaffected by"
  echo "  # the flag being present; only the ads sources actually exercise it."
  echo "  s.pod_target_xcconfig = {"
  echo "    \"CLANG_ENABLE_MODULES\" => \"YES\","
  echo "    \"OTHER_CPLUSPLUSFLAGS\" => \"\$(inherited) -fcxx-modules\","
  echo "  }"
  echo ""
  echo "  unless defined?(spm_dependency)"
  echo "    raise \"BrightcovePlayer requires React Native's SwiftPM CocoaPods integration.\""
  echo "  end"
  echo ""
  echo "  spm_dependency("
  echo "    s,"
  echo "    url: \"https://github.com/brightcove/brightcove-player-sdk-ios.git\","
  echo "    requirement: {"
  echo "      kind: \"upToNextMajorVersion\","
  echo "      minimumVersion: \"7.2.16\","
  echo "    },"
  echo "    # BRIDGE:SPM_PRODUCTS — the SwiftPM products this bridge copy needs. The core"
  echo "    # needs BrightcovePlayerSDK; features add their own (ads -> BrightcoveIMA)."
  echo "    # scripts/assemble-bridge.sh regenerates this line from the installed feature"
  echo "    # set, so it is a generated composition root — do not hand-edit."
  echo "    products: [$spm_products],"
  echo "  )"
  echo ""
  echo "  install_modules_dependencies(s)"
  echo "end"
} > "$dest/BrightcovePlayer.podspec"

{
  echo "buildscript {"
  echo "  ext.BrightcovePlayer = ["
  echo "    kotlinVersion: \"2.0.21\","
  echo "    minSdkVersion: 24,"
  echo "    compileSdkVersion: 36,"
  echo "    brightcoveSdkVersion: \"10.4.25\","
  echo "    lifecycleVersion: \"2.8.7\""
  echo "  ]"
  echo ""
  echo "  ext.getExtOrDefault = { prop ->"
  echo "    if (rootProject.ext.has(prop)) {"
  echo "      return rootProject.ext.get(prop)"
  echo "    }"
  echo ""
  echo "    return BrightcovePlayer[prop]"
  echo "  }"
  echo ""
  echo "  repositories {"
  echo "    google()"
  echo "    mavenCentral()"
  echo "  }"
  echo ""
  echo "  dependencies {"
  echo "    classpath \"com.android.tools.build:gradle:8.7.2\""
  echo "    // noinspection DifferentKotlinGradleVersion"
  echo "    classpath \"org.jetbrains.kotlin:kotlin-gradle-plugin:\${getExtOrDefault('kotlinVersion')}\""
  echo "  }"
  echo ""
  echo "  // AGP 8.7.2's own APK-signing tooling (apksig/apkzlib) transitively pulls"
  echo "  // bcprov/bcpkix/bcutil-jdk18on:1.77, which carries several CVEs (including"
  echo "  // two the CVE feed rates critical) fixed in later releases. This is a"
  echo "  // buildscript-only classpath dependency of the Android Gradle Plugin"
  echo "  // itself — never a runtime dependency of the app or the Brightcove SDK —"
  echo "  // so forcing it here has no effect on anything the app ships or links"
  echo "  // against; it only changes which bouncycastle jar android.jar signing"
  echo "  // uses at build time."
  echo "  configurations.classpath {"
  echo "    resolutionStrategy {"
  echo "      force \"org.bouncycastle:bcprov-jdk18on:1.85\""
  echo "      force \"org.bouncycastle:bcpkix-jdk18on:1.85\""
  echo "      force \"org.bouncycastle:bcutil-jdk18on:1.85\""
  echo "    }"
  echo "  }"
  echo "}"
  echo ""
  echo ""
  echo "apply plugin: \"com.android.library\""
  echo "apply plugin: \"kotlin-android\""
  echo ""
  echo "apply plugin: \"com.facebook.react\""
  echo ""
  echo "repositories {"
  echo "  google()"
  echo "  mavenCentral()"
  echo "  maven { url \"https://repo.brightcove.com/releases\" }"
  echo "}"
  echo ""
  echo "android {"
  echo "  namespace \"com.brightcove.reactnativeplayer\""
  echo ""
  echo "  compileSdkVersion getExtOrDefault(\"compileSdkVersion\")"
  echo ""
  echo "  defaultConfig {"
  echo "    minSdkVersion getExtOrDefault(\"minSdkVersion\")"
  echo "  }"
  echo ""
  echo "  compileOptions {"
  echo "    sourceCompatibility JavaVersion.VERSION_17"
  echo "    targetCompatibility JavaVersion.VERSION_17"
  echo "    coreLibraryDesugaringEnabled true"
  echo "  }"
  echo "}"
  echo ""
  echo "dependencies {"
  echo "  implementation \"com.facebook.react:react-android\""
  echo "  implementation \"com.brightcove.player:android-sdk:\${getExtOrDefault('brightcoveSdkVersion')}\""
  echo "  implementation \"com.brightcove.player:exoplayer2:\${getExtOrDefault('brightcoveSdkVersion')}\""
  echo "  implementation \"androidx.lifecycle:lifecycle-common-java8:\${getExtOrDefault('lifecycleVersion')}\""
  echo "  testImplementation \"junit:junit:4.13.2\""
  echo "  coreLibraryDesugaring \"com.android.tools:desugar_jdk_libs:2.1.3\""
  echo "  testImplementation \"junit:junit:4.13.2\""
  echo "  // BRIDGE:FEATURE_DEPS — extra dependencies required by installed features"
  echo "  // (ads -> android-ima-plugin). scripts/assemble-bridge.sh regenerates the"
  echo "  // lines below this marker from the installed feature set, so this dependency"
  echo "  // block is a generated composition root — do not hand-edit feature deps."
  for f in $selected; do
    for d in $(feature_gradle_deps "$f"); do
      echo "  implementation \"$d:\${getExtOrDefault('brightcoveSdkVersion')}\""
    done
    if [ "$(type -t feature_gradle_extra 2>/dev/null || true)" = "function" ] || declare -f feature_gradle_extra >/dev/null 2>&1; then
      extra="$(feature_gradle_extra "$f")"
      if [ -n "$extra" ]; then
        printf '%s\n' "$extra"
      fi
    fi
  done
  echo "}"
} > "$dest/android/build.gradle"

echo "Assembled bridge into $dest (features: ${selected:-none})."
