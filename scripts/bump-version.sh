#!/bin/bash
# Raise MARKETING_VERSION from commit messages on stdin.
# major > minor > release (patch). A message with none of these words is a patch bump.
# Without --apply, print the next version and leave the project file unchanged.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$ROOT/VidgetYo.xcodeproj/project.pbxproj"
APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

current="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PBX" | head -1)"
if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: MARKETING_VERSION '$current' is not major.minor.patch" >&2
  exit 1
fi

text="$(cat | tr '[:upper:]' '[:lower:]')"
kind="release"
if printf '%s\n' "$text" | grep -Eq '(^|[^[:alnum:]_])major([^[:alnum:]_]|$)'; then
  kind="major"
elif printf '%s\n' "$text" | grep -Eq '(^|[^[:alnum:]_])minor([^[:alnum:]_]|$)'; then
  kind="minor"
fi

IFS=. read -r major minor patch <<< "$current"
case "$kind" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="${major}.$((minor + 1)).0" ;;
  release) next="${major}.${minor}.$((patch + 1))" ;;
esac

if [[ "$APPLY" -eq 1 ]]; then
  perl -i -pe "s/MARKETING_VERSION = \Q${current}\E;/MARKETING_VERSION = ${next};/g" "$PBX"
fi

echo "$next"
