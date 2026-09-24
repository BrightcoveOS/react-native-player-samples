#!/usr/bin/env bash
# Assert that backticked repository paths mentioned in docs/*.md and README
# still exist. Only tokens that look like repository paths (containing a slash)
# are checked; identifiers, commands, URLs, and placeholders are ignored.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
# Docs and the root README resolve a path against the repository root or the
# reference bridge; a sample README additionally resolves against its own sample
# directory and that sample's embedded bridge. Sample READMEs are included so a
# path a customer is told to open cannot rot silently.
check_doc() {
  local doc="$1" sample_dir="${2:-}"
  [[ -e "$doc" ]] || return 0
  while IFS= read -r path; do
    case "$path" in
      http*|*:*|*'<'*|*'>'*) continue ;;
    esac
    [[ "$path" == *" "* || "$path" == *"'"* || "$path" == *'"'* ]] && continue
    if [[ -e "$path" ]] || [[ -e "reference/brightcove-player/$path" ]]; then
      continue
    fi
    if [[ -n "$sample_dir" ]] &&
       { [[ -e "${sample_dir}${path%/}" ]] ||
         [[ -e "${sample_dir}modules/brightcove-player/${path%/}" ]]; }; then
      continue
    fi

    found=false
    for sample_path in samples/player/*/; do
      [[ -e "${sample_path}${path%/}" ]] ||
        [[ -e "${sample_path}modules/brightcove-player/${path%/}" ]] && {
        found=true
        break
      }
    done
    if [[ "$found" == false ]]; then
      echo "ERROR: $doc references '$path' but it does not exist."
      status=1
    fi
  done < <(grep -oE '`[a-zA-Z0-9_.][^`]*[/][^` ]*`' "$doc" | tr -d '`' | sort -u)
}

for doc in docs/*.md README.md; do
  check_doc "$doc"
done
for readme in samples/player/*/README.md; do
  check_doc "$readme" "$(dirname "$readme")/"
done

# docs/supported-samples.md states the supported set for people;
# scripts/supported-samples.sh states it for the tooling. They must name the same
# samples, or the documentation and the shipped set disagree about what the
# repository contains.
# shellcheck source=scripts/supported-samples.sh
. scripts/supported-samples.sh
documented="$(sed -n '/^## Supported set/,/^## /p' docs/supported-samples.md |
  grep -oE '^\| `[a-z0-9-]+` \|' | tr -d '|` ' | sort)"
manifested="$(printf '%s\n' $SUPPORTED_SAMPLES | sort)"
if [[ "$documented" != "$manifested" ]]; then
  echo "ERROR: docs/supported-samples.md and scripts/supported-samples.sh name different supported samples."
  diff <(echo "$documented") <(echo "$manifested") | sed -e 's/^</  only in docs\/supported-samples.md:/' -e 's/^>/  only in scripts\/supported-samples.sh:/' | grep -E '^  only' || true
  status=1
fi
for sample in $SUPPORTED_SAMPLES; do
  [[ -d "samples/player/$sample" ]] || {
    echo "ERROR: scripts/supported-samples.sh names '$sample', but samples/player/$sample does not exist."
    status=1
  }
done

exit "$status"
