#!/usr/bin/env bash
# Verifies every sample's embedded bridge against the canonical implementation
# in reference/brightcove-player.
#
# The model: reference/ is the developer-only superset (core + every feature)
# and is never shipped — a customer copies a *sample* directory. Each sample
# therefore embeds only the subset of the bridge it actually uses. The contract
# this script enforces is:
#
#   * every bridge file a sample DOES contain must be byte-identical to the
#     reference (so a fix in the reference is never silently missed);
#   * a sample MAY omit reference files it does not need (a subset is allowed —
#     samples are not forced to carry the whole bridge);
#   * a sample MUST NOT contain a bridge file that has no reference counterpart
#     (an extra / drifted file is caught, unlike the old check).
#
# Composition-root files are sample-owned: each sample legitimately differs
# here because this is where it declares which features it contains. Everything
# else must be byte-identical to the reference. The composition root is:
#   - src/index.tsx            the public prop surface, narrowed per sample
#   - FeatureRegistry.kt       (Android) the installed-feature list
#   - BrightcoveFeatureRegistry.mm  (iOS) the installed-feature list
#   - tsconfig.json, .eslintrc.js   per-sample tool config
#   - README.md                describes the copy's embedded role
#
# Beyond byte-identity, this script also checks consistency: the feature props a
# sample's index.tsx exposes must match the features its registry installs, so
# the public type can never advertise a prop the copy cannot actually service.
set -euo pipefail

cd "$(dirname "$0")/.."

REFERENCE="reference/brightcove-player"
EXCLUDED="README.md .eslintrc.js tsconfig.json package.json src/index.tsx src/index.ios.tsx src/index.web.tsx android/src/main/java/com/brightcove/reactnativeplayer/FeatureRegistry.kt ios/BrightcoveFeatureRegistry.mm BrightcovePlayer.podspec android/build.gradle"


is_excluded() {
  case " $EXCLUDED " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

failed=0
checked_any=0

# List a module's files. `git ls-files` includes untracked files, so a freshly assembled bridge is
# checked before staging — but it errors outright when there is no repository, which is exactly the
# case for an exported or zipped copy of this tree, and the process substitution below would swallow
# that error and read zero lines. Outside a repository, walk the tree instead, pruning what
# .gitignore would hide — build output and OS/tool litter appear as soon as an unzipped sample is
# opened or built.
list_module_files() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard "$1"
  else
    find "$1" \( -name build -o -name .gradle -o -name .cxx -o -name node_modules \
                 -o -name Pods -o -name xcuserdata \) -prune \
      -o -type f ! -name .DS_Store ! -name '*.log' ! -name local.properties -print
  fi
}

# --- Mandatory composition-root manifest -------------------------------------
# The byte-identity loop below tolerates a *subset* of reference files, which is
# intended for optional bridge content but means a whole missing bridge, or a
# deleted generated root, is indistinguishable from a legitimate subset and
# passes silently. A sample a customer can build must carry these roots (the
# registry files declare its installed features; the native component spec is
# what Codegen compiles). A sample directory with a package manifest is treated
# as a buildable sample and must satisfy the manifest, fail closed.
REQUIRED_BRIDGE_FILES="
src/index.tsx
src/BrightcovePlayerView.tsx
src/BrightcovePlayerViewNativeComponent.ts
android/src/main/java/com/brightcove/reactnativeplayer/FeatureRegistry.kt
ios/BrightcoveFeatureRegistry.mm
"
missing_roots=0
for sample in samples/*/*; do
  [ -d "$sample" ] || continue
  if [ ! -f "$sample/package.json" ]; then
    echo "MISSING: $sample has no package.json (discovery would silently skip it)"
    missing_roots=1
    continue
  fi
  module="$sample/modules/brightcove-player"
  if [ ! -d "$module" ]; then
    echo "MISSING: $sample has package.json but no $module"
    missing_roots=1
    continue
  fi
  for rel in $REQUIRED_BRIDGE_FILES; do
    if [ ! -f "$module/$rel" ]; then
      echo "MISSING: $module/$rel (required for $sample)"
      missing_roots=1
    fi
  done
done

if [ "$missing_roots" -ne 0 ]; then
  echo ""
  echo "A sample is missing a required bridge composition root. These files are"
  echo "what make the embedded bridge buildable and feature-consistent; restore"
  echo "them (re-run scripts/assemble-bridge.sh for the sample's feature set)."
  exit 1
fi
echo "Every sample carries its mandatory bridge roots."

for module in samples/*/*/modules/brightcove-player; do
  [ -d "$module" ] || continue
  checked_any=1
  module_files=0

  # Every file the sample carries must match the reference (or be an allowed
  # sample-owned file); anything with no reference counterpart is drift.
  while IFS= read -r path; do
    file="${path#"$module"/}"
    is_excluded "$file" && continue
    module_files=$((module_files + 1))
    if [ ! -f "$REFERENCE/$file" ]; then
      echo "EXTRA:   $path (no counterpart in $REFERENCE)"
      failed=1
    elif ! cmp -s "$REFERENCE/$file" "$path"; then
      echo "DIFFERS: $path"
      failed=1
    fi
  done < <(list_module_files "$module")

  # Every bridge copy carries reference files, so a copy that yields none means its listing failed
  # — and a failed listing is indistinguishable from a clean copy unless it is caught here, per
  # module, where one broken listing cannot hide behind the others.
  if [ "$module_files" -eq 0 ]; then
    echo "EMPTY:   $module (listed no bridge files to compare — the listing failed)"
    failed=1
  fi
done

# The script cd's to the repository root above, so an empty glob means the tree genuinely carries no
# embedded bridge copies. That is still not a pass: this guard is the only thing keeping the copies
# from drifting, so "nothing to check" is a failure.
if [ "$checked_any" -eq 0 ]; then
  echo "No sample bridge copies found under samples/*/*/modules/brightcove-player."
  exit 1
fi

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "A sample's embedded bridge has drifted from $REFERENCE."
  echo "Each file a sample keeps must match the reference; propagate the fix"
  echo "from the reference, or remove the extra file."
  exit 1
fi
echo "All embedded bridge files match $REFERENCE (subsets allowed)."

# --- Consistency: public prop surface must match installed features ----------
#
# Each feature owns a fixed set of props. A sample must expose (not Omit) a
# feature's props exactly when its FeatureRegistry installs that feature.
# Otherwise index.tsx could advertise a prop the native copy cannot service
# (Omit is a denylist — a newly added feature would leak into every sample that
# forgot to exclude it), or hide a prop the copy does implement. Keyed off the
# feature directory name so adding a feature needs one line here.
#
# Feature catalog (which props each feature owns) is shared with
# assemble-bridge.sh — one source of truth for the shell tooling.
# shellcheck source=scripts/feature-catalog.sh
. "$(dirname "$0")/feature-catalog.sh"

# A dependency counts as present only when it appears as an actual declaration,
# not merely mentioned in a comment. The generated build.gradle documents the
# feature->artifact mapping in comments right above the real line
# ("(ads -> android-ima-plugin)"), so a plain substring grep stays green even
# after the declaration itself is deleted. Match the declaration form the
# assembler emits ("implementation \"group:artifact:...") and the products array
# in the podspec.
gradle_has_dep() {
  grep -qE "^[[:space:]]*implementation \"$2:" "$1"
}
podspec_has_product() {
  grep -E "^[[:space:]]*products:" "$1" | grep -q "\"$2\""
}

consistency_failed=0
for module in samples/*/*/modules/brightcove-player; do
  [ -d "$module" ] || continue
  index="$module/src/index.tsx"
  kotlin_registry="$module/android/src/main/java/com/brightcove/reactnativeplayer/FeatureRegistry.kt"
  objc_registry="$module/ios/BrightcoveFeatureRegistry.mm"
  [ -f "$index" ] || continue
  [ -f "$kotlin_registry" ] || continue
  [ -f "$objc_registry" ] || continue

  android_dir="$module/android/src/main/java/com/brightcove/reactnativeplayer"
  ios_dir="$module/ios"

  installed_features=""
  for feature in $ALL_FEATURES; do
    kotlin_class="$(feature_kotlin_class "$feature")"; kotlin_class="${kotlin_class##*.}"
    if [ -n "$kotlin_class" ] && grep -q "${kotlin_class}()" "$kotlin_registry"; then
      installed_features="$installed_features $feature"
    fi
  done
  has_installed_feature() {
    case " $installed_features " in *" $1 "*) return 0 ;; *) return 1 ;; esac
  }
  # feature_conflicts is defined in feature-catalog.sh, which this script
  # sources unconditionally; the guard only needs one probe.
  if declare -f feature_conflicts >/dev/null 2>&1; then
    for f1 in $installed_features; do
      for f2 in $installed_features; do
        if [ "$f1" != "$f2" ] && feature_conflicts "$f1" "$f2"; then
          echo "INCONSISTENT: $module installs mutually exclusive $f1 and $f2 features"
          consistency_failed=1
        fi
      done
    done
  fi

  # Props owned by an INSTALLED feature on Android. Built first because features
  # can share a prop (ads and ssai both own the onAd* events): a prop must be
  # exposed if ANY installed feature owns it, and omitted only if NONE does.
  installed_android_props=" "
  for feature in $ALL_FEATURES; do
    kclass="$(feature_kotlin_class "$feature")"; kclass="${kclass##*.}"
    if [ -n "$kclass" ] && grep -q "${kclass}()" "$kotlin_registry"; then
      for p in $(feature_props "$feature"); do installed_android_props="$installed_android_props$p "; done
    fi
  done

  # Event types contributed by an INSTALLED feature on Android.
  installed_android_event_types=" "
  for feature in $ALL_FEATURES; do
    kclass="$(feature_kotlin_class "$feature")"; kclass="${kclass##*.}"
    if [ -n "$kclass" ] && grep -q "${kclass}()" "$kotlin_registry"; then
      for t in $(feature_event_types "$feature"); do installed_android_event_types="$installed_android_event_types$t "; done
    fi
  done

  # Props and event types contributed by an INSTALLED feature on iOS. A prop a
  # feature declares cross-platform but its iOS SDK cannot back
  # (feature_ios_unsupported_props, e.g. ssai's onAdError) is excluded from the
  # iOS surface unless another installed iOS feature that does back it also owns
  # it — otherwise the generated index.ios.tsx would be wrongly flagged for
  # hiding a prop iOS genuinely cannot service.
  installed_ios_props=" "
  installed_ios_event_types=" "
  for feature in $ALL_FEATURES; do
    oclass="$(feature_objc "$feature" | cut -d: -f2)"
    if [ -n "$oclass" ] && grep -q "\[$oclass new\]" "$objc_registry"; then
      for t in $(feature_event_types "$feature"); do installed_ios_event_types="$installed_ios_event_types$t "; done
      for p in $(feature_props "$feature"); do
        backed_elsewhere=0
        case " $(feature_ios_unsupported_props "$feature") " in
          *" $p "*)
            for g in $ALL_FEATURES; do
              [ "$g" = "$feature" ] && continue
              gclass="$(feature_objc "$g" | cut -d: -f2)"
              [ -n "$gclass" ] && grep -q "\[$gclass new\]" "$objc_registry" || continue
              case " $(feature_props "$g") " in
                *" $p "*)
                  case " $(feature_ios_unsupported_props "$g") " in
                    *" $p "*) ;;
                    *) backed_elsewhere=1 ;;
                  esac ;;
              esac
            done
            [ "$backed_elsewhere" -eq 1 ] && installed_ios_props="$installed_ios_props$p "
            ;;
          *) installed_ios_props="$installed_ios_props$p " ;;
        esac
      done
    fi
  done

  # Native dependencies contributed by an INSTALLED feature. Built first for
  # the same reason as props/event types above: a dep can belong to more than
  # one feature (ssai and thumbnail both need android-thumbnail-plugin), so it
  # must be present if ANY installed feature needs it, and absent only if NONE
  # does — checking a single feature's installed state would wrongly flag the
  # dep as extra when a different installed feature also needs it.
  installed_gradle_deps=" "
  installed_spm_products=" "
  for feature in $ALL_FEATURES; do
    kclass="$(feature_kotlin_class "$feature")"; kclass="${kclass##*.}"
    if [ -n "$kclass" ] && grep -q "${kclass}()" "$kotlin_registry"; then
      for d in $(feature_gradle_deps "$feature"); do installed_gradle_deps="$installed_gradle_deps$d "; done
      for p in $(feature_spm_products "$feature"); do installed_spm_products="$installed_spm_products$p "; done
    fi
  done

  for feature in $ALL_FEATURES; do
    # "Installed" is what the generated registries actually instantiate — that
    # is what compiles into the app and services props at runtime — not merely
    # what directory is present. Checking the directory alone let a copy keep a
    # feature dir and its public props while the registry returned an empty
    # list: it compiled, passed this guard, then threw at runtime when the prop
    # had no owning feature. Derive installed-ness from every surface and
    # require them to agree.
    kotlin_class="$(feature_kotlin_class "$feature")"; kotlin_class="${kotlin_class##*.}"
    objc_class="$(feature_objc "$feature" | cut -d: -f2)"

    android_dir_present=0; [ -d "$android_dir/$feature" ] && android_dir_present=1
    ios_dir_present=0;     [ -d "$ios_dir/$feature" ] && ios_dir_present=1
    kotlin_installed=0
    if feature_supports_android "$feature" && [ -n "$kotlin_class" ] && grep -q "${kotlin_class}()" "$kotlin_registry"; then
      kotlin_installed=1
    fi
    objc_installed=0
    if feature_supports_ios "$feature" && [ -n "$objc_class" ] && grep -q "\[$objc_class new\]" "$objc_registry"; then
      objc_installed=1
    fi

    # Platform support is catalog-owned. An iOS-only feature must not acquire an
    # Android directory, and a cross-platform feature must be present on both
    # platforms or neither: shipping it on one platform only produces a copy
    # that behaves differently per platform, which is exactly the divergence
    # this script exists to prevent.
    if ! feature_supports_android "$feature" && [ "$android_dir_present" -ne 0 ]; then
      echo "INCONSISTENT: $module feature '$feature' is iOS-only but has an Android directory"
      consistency_failed=1
    fi
    if feature_supports_android "$feature" && feature_supports_ios "$feature" &&
       [ "$android_dir_present" != "$ios_dir_present" ]; then
      echo "INCONSISTENT: $module cross-platform feature '$feature' present on one platform only (android=$android_dir_present ios=$ios_dir_present)"
      consistency_failed=1
    fi
    if [ "$kotlin_installed" != "$android_dir_present" ]; then
      echo "INCONSISTENT: $module has android '$feature' dir=$android_dir_present but FeatureRegistry.kt installs=$kotlin_installed"
      consistency_failed=1
    fi
    if [ "$objc_installed" != "$ios_dir_present" ]; then
      echo "INCONSISTENT: $module has ios '$feature' dir=$ios_dir_present but BrightcoveFeatureRegistry.mm installs=$objc_installed"
      consistency_failed=1
    fi

    # The public prop surface must match what is actually installed. A prop is
    # "owned" if any installed feature owns it (shared props stay exposed as
    # long as one owner is installed), so check each of this feature's props
    # against the installed-props union rather than this one feature's state.
    for prop in $(feature_props "$feature"); do
      # Does the public type expose this prop? Omit-listed => hidden.
      if grep -qE "'$prop'" "$index"; then
        exposed=0   # appears in the Omit<> list, so it is hidden
      else
        exposed=1
      fi
      owned_by_installed=0
      case "$installed_android_props" in *" $prop "*) owned_by_installed=1 ;; esac
      if [ "$owned_by_installed" -eq 1 ] && [ "$exposed" -eq 0 ]; then
        echo "INCONSISTENT: $module installs a feature owning '$prop' but index.tsx hides it"
        consistency_failed=1
      elif [ "$owned_by_installed" -eq 0 ] && [ "$exposed" -eq 1 ]; then
        echo "INCONSISTENT: $module installs no feature owning '$prop' but index.tsx exposes it"
        consistency_failed=1
      fi

      # iOS-only features are exposed through the platform-specific entry point
      # only. A selected iOS feature must never leak into Android's index.tsx.
      ios_index="$module/src/index.ios.tsx"
      if [ -f "$ios_index" ]; then
        ios_exposed=0
        if ! grep -qE "'$prop'" "$ios_index"; then
          ios_exposed=1
        fi
        owned_by_ios_installed=0
        case "$installed_ios_props" in *" $prop "*) owned_by_ios_installed=1 ;; esac
        if [ "$owned_by_ios_installed" -eq 1 ] && [ "$ios_exposed" -eq 0 ]; then
          echo "INCONSISTENT: $module installs a feature owning '$prop' but index.ios.tsx hides it"
          consistency_failed=1
        elif [ "$owned_by_ios_installed" -eq 0 ] && [ "$ios_exposed" -eq 1 ]; then
          echo "INCONSISTENT: $module installs no feature owning '$prop' but index.ios.tsx exposes it"
          consistency_failed=1
        fi
      fi
    done

    # An event payload type must be re-exported exactly when its feature is
    # installed. A generated index that keeps an event handler prop (checked
    # above) but drops its payload type export still compiles (the handler is
    # typed with the omitted-elsewhere generic NativeProps shape) and only
    # fails at the consumer's own type-check, far from this guard — so check
    # the export explicitly rather than relying on the prop check to imply it.
    for event_type in $(feature_event_types "$feature"); do
      [ -z "$event_type" ] && continue
      android_type_exported=0
      grep -qE "^\s*${event_type},?\s*$" "$index" && android_type_exported=1
      owned_by_android=0
      case "$installed_android_event_types" in *" $event_type "*) owned_by_android=1 ;; esac
      if [ "$owned_by_android" -eq 1 ] && [ "$android_type_exported" -eq 0 ]; then
        echo "INCONSISTENT: $module installs a feature exporting '$event_type' but index.tsx does not export it"
        consistency_failed=1
      elif [ "$owned_by_android" -eq 0 ] && [ "$android_type_exported" -eq 1 ]; then
        echo "INCONSISTENT: $module installs no feature exporting '$event_type' but index.tsx exports it"
        consistency_failed=1
      fi

      ios_index="$module/src/index.ios.tsx"
      if [ -f "$ios_index" ]; then
        ios_type_exported=0
        grep -qE "^\s*${event_type},?\s*$" "$ios_index" && ios_type_exported=1
        owned_by_ios=0
        case "$installed_ios_event_types" in *" $event_type "*) owned_by_ios=1 ;; esac
        if [ "$owned_by_ios" -eq 1 ] && [ "$ios_type_exported" -eq 0 ]; then
          echo "INCONSISTENT: $module installs a feature exporting '$event_type' but index.ios.tsx does not export it"
          consistency_failed=1
        elif [ "$owned_by_ios" -eq 0 ] && [ "$ios_type_exported" -eq 1 ]; then
          echo "INCONSISTENT: $module installs no feature exporting '$event_type' but index.ios.tsx exports it"
          consistency_failed=1
        fi
      fi
    done

    # Native dependencies must match installed-ness too: a feature that needs an
    # extra native SDK (ads -> android-ima-plugin / BrightcoveIMA) must have its
    # dependency present in the generated build.gradle / podspec exactly when
    # ANY installed feature needs it (see installed_gradle_deps/
    # installed_spm_products above — a dep can be shared, e.g. ssai and
    # thumbnail both need android-thumbnail-plugin), and absent otherwise.
    # Otherwise a sample would fail to compile the feature (missing dep) or
    # ship a native SDK it never uses.
    buildgradle="$module/android/build.gradle"
    podspec="$module/BrightcovePlayer.podspec"
    for dep in $(feature_gradle_deps "$feature"); do
      present=0; [ -f "$buildgradle" ] && gradle_has_dep "$buildgradle" "$dep" && present=1
      owned_by_installed=0
      case "$installed_gradle_deps" in *" $dep "*) owned_by_installed=1 ;; esac
      if [ "$owned_by_installed" -eq 1 ] && [ "$present" -eq 0 ]; then
        echo "INCONSISTENT: $module installs a feature needing gradle dep '$dep' but build.gradle is missing it"
        consistency_failed=1
      elif [ "$owned_by_installed" -eq 0 ] && [ "$present" -eq 1 ]; then
        echo "INCONSISTENT: $module installs no feature needing gradle dep '$dep' but build.gradle has it"
        consistency_failed=1
      fi
    done
    for product in $(feature_spm_products "$feature"); do
      present=0; [ -f "$podspec" ] && podspec_has_product "$podspec" "$product" && present=1
      owned_by_installed=0
      case "$installed_spm_products" in *" $product "*) owned_by_installed=1 ;; esac
      if [ "$owned_by_installed" -eq 1 ] && [ "$present" -eq 0 ]; then
        echo "INCONSISTENT: $module installs a feature needing SPM product '$product' but the podspec is missing it"
        consistency_failed=1
      elif [ "$owned_by_installed" -eq 0 ] && [ "$present" -eq 1 ]; then
        echo "INCONSISTENT: $module installs no feature needing SPM product '$product' but the podspec has it"
        consistency_failed=1
      fi
    done
  done
done

if [ "$consistency_failed" -ne 0 ]; then
  echo ""
  echo "A sample's public prop surface (src/index.tsx) does not match the"
  echo "features its FeatureRegistry installs. Omit exactly the props of the"
  echo "features the copy does not contain."
  exit 1
fi
echo "Public prop surfaces are consistent with installed features."

# --- Reference re-export completeness: event payload types -------------------
#
# Every event payload type the Codegen spec (the shared TS contract) declares
# must be re-exported from the reference index, so a TypeScript consumer can
# type a handler without importing internals. The per-sample index copies
# narrow to their installed features (assemble-bridge generates those), so a
# missing reference export is invisible to every sample's own typecheck —
# this text-level diff catches it without compiling.
SPEC="$REFERENCE/src/BrightcovePlayerViewNativeComponent.ts"
REF_INDEX="$REFERENCE/src/index.tsx"
spec_types=$(grep -E '^export (type|interface) ' "$SPEC" | sed -E 's/^export (type|interface) ([A-Za-z0-9_]+).*/\2/' | sort -u)
missing=""
for t in $spec_types; do
  # NativeProps is the component props surface (not a consumer-facing event
  # payload); everything else the spec exports must be re-exported.
  if [ "$t" = "NativeProps" ]; then continue; fi
  if ! grep -qE "(^|[ ,{])$t(,|[ }])" "$REF_INDEX" && ! grep -qE "^\s*$t,$" "$REF_INDEX"; then
    missing="$missing $t"
  fi
done
if [ -n "$missing" ]; then
  echo "MISSING RE-EXPORTS: the reference index does not re-export:$missing"
  echo "Add them to reference/brightcove-player/src/index.tsx's export list"
  echo "from './BrightcovePlayerViewNativeComponent'."
  exit 1
fi
echo "Reference index re-exports every spec event payload type."

# --- Sample hygiene: baseline every sample must meet -------------------------
#
# The product is a set of samples a customer copies, so whichever one they pick
# must be lintable and actually tested. These were fixed by hand per sample and
# kept being missed on new ones; enforce them instead:
#   * .eslintignore exists (else `eslint .` drowns in ios/Pods + build output
#     the moment the sample is built locally);
#   * the test suite makes at least one assertion (a test with no expect() —
#     e.g. a bare "renders correctly" under SafeAreaProvider, which renders
#     nothing under react-test-renderer — passes even if the app is gutted).
hygiene_failed=0
for sample in samples/*/*; do
  [ -f "$sample/package.json" ] || continue

  if [ ! -f "$sample/.eslintignore" ]; then
    echo "MISSING: $sample/.eslintignore (lint breaks after a local build)"
    hygiene_failed=1
  fi

  if [ -d "$sample/__tests__" ]; then
    if ! grep -rq 'expect(' "$sample/__tests__"; then
      echo "VACUOUS TESTS: $sample/__tests__ makes no expect() assertion"
      hygiene_failed=1
    fi
  elif [ -d "$sample/src" ] && grep -rq 'expect(' "$sample/src"; then
    : # Web samples place tests under src/ (e.g. src/App.test.tsx)
  else
    echo "MISSING: $sample/__tests__ (no tests)"
    hygiene_failed=1
  fi

  # A web-enabled sample must have tsconfig.web.json + a typecheck:web script,
  # or `tsc --noEmit`'s bundler resolution silently validates App.tsx against
  # index.tsx (native) instead of index.web.tsx even when building for the
  # browser: a native-only prop this sample's web bridge Omits then compiles
  # clean and is only discovered by a human noticing the feature does nothing
  # in the browser. See samples/player/*/tsconfig.web.json for the pattern.
  if [ -f "$sample/webpack.config.js" ]; then
    if [ ! -f "$sample/tsconfig.web.json" ]; then
      echo "MISSING: $sample/tsconfig.web.json (web build has no type-checked browser prop surface)"
      hygiene_failed=1
    fi
    if ! grep -q '"typecheck:web"' "$sample/package.json" 2>/dev/null; then
      echo "MISSING: $sample/package.json 'typecheck:web' script"
      hygiene_failed=1
    fi
    if ! grep -q 'ForkTsCheckerWebpackPlugin' "$sample/webpack.config.js" 2>/dev/null; then
      echo "MISSING: $sample/webpack.config.js does not type-check the web build (no ForkTsCheckerWebpackPlugin)"
      hygiene_failed=1
    fi
    # Metro defines __DEV__ for native builds; webpack does not. A sample whose
    # source reads __DEV__ (playerConfig's placeholder guard) renders a blank
    # page on web with "ReferenceError: __DEV__ is not defined" unless the
    # webpack config defines it. Require the define whenever the sample's source
    # mentions __DEV__ and it has a web build, so the blank-page class cannot
    # ship again.
    if grep -rq '__DEV__' "$sample/App.tsx" "$sample/src" "$sample/index.web.js" 2>/dev/null \
      && ! grep -q 'DefinePlugin' "$sample/webpack.config.js" 2>/dev/null; then
      echo "MISSING: $sample reads __DEV__ but its webpack config never defines it (web renders blank)"
      hygiene_failed=1
    fi
  fi

  # A sample that installs the iOS Picture-in-Picture feature must also carry
  # the host-app prerequisites PiP needs — the Playback AVAudioSession category
  # and UIBackgroundModes: audio. The bridge never sets these, so a sample that
  # enables PiP without them builds clean and then fails to stay alive in the
  # PiP window when backgrounded on a device (CI only compiles iOS).
  if grep -q 'BrightcovePictureInPictureFeature new' \
       "$sample/modules/brightcove-player/ios/BrightcoveFeatureRegistry.mm" 2>/dev/null; then
    pip_appdelegate="$(ls "$sample"/ios/*/AppDelegate.swift 2>/dev/null | head -1)"
    if [ -z "$pip_appdelegate" ] || ! grep -q 'setCategory(.playback' "$pip_appdelegate"; then
      echo "MISSING: $sample installs Picture-in-Picture but its AppDelegate never sets the AVAudioSession playback category"
      hygiene_failed=1
    fi
    if ! grep -rq 'UIBackgroundModes' "$sample"/ios/*/Info.plist 2>/dev/null; then
      echo "MISSING: $sample installs Picture-in-Picture but its Info.plist has no UIBackgroundModes: audio"
      hygiene_failed=1
    fi
  fi
done

# The web bridge suite is carried per sample (samples stay self-contained, the same reason the
# bridge itself is copied), and it tests code that byte-identity already keeps identical everywhere
# — so the copies must agree too. Otherwise a regression test added in one sample silently covers
# only that sample while CI keeps running the older suite everywhere else.
web_suite_reference=""
web_suite_failed=0
for suite in samples/*/*/src/__tests__/BrightcovePlayerView.web.test.tsx; do
  [ -f "$suite" ] || continue
  if [ -z "$web_suite_reference" ]; then
    web_suite_reference="$suite"
  elif ! cmp -s "$web_suite_reference" "$suite"; then
    echo "DIFFERS: $suite (web bridge suite must match $web_suite_reference)"
    web_suite_failed=1
  fi
done

if [ "$web_suite_failed" -ne 0 ]; then
  echo ""
  echo "The per-sample web bridge test suites have drifted. They all exercise the same embedded"
  echo "BrightcovePlayerView.web.tsx, so a test added in one sample belongs in all of them:"
  echo "  cp $web_suite_reference samples/player/<sample>/src/__tests__/"
  exit 1
fi

if [ "$hygiene_failed" -ne 0 ]; then
  echo ""
  echo "A sample is missing baseline hygiene (see above). Every sample must"
  echo "carry an .eslintignore and a test suite that actually asserts."
  exit 1
fi
echo "Sample hygiene (eslintignore + non-vacuous tests) present."
