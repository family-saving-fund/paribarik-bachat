#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [[ "$(git branch --show-current)" != "master" ]]; then
  echo "त्रुटि: master branch मा जानुहोस्।"
  exit 1
fi

if ! git diff --cached --quiet; then
  echo "त्रुटि: Git मा staged परिवर्तन छन्। पहिले तिनलाई सुरक्षित गर्नुहोस्।"
  git diff --cached --stat
  exit 1
fi

if ! git diff --quiet -- pubspec.yaml; then
  echo "त्रुटि: pubspec.yaml मा पहिले नै परिवर्तन छन्।"
  exit 1
fi

git pull --ff-only origin master

CURRENT=$(grep '^version:' pubspec.yaml | awk '{print $2}')
if [[ ! "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
  echo "त्रुटि: pubspec.yaml को version ढाँचा मिलेन: $CURRENT"
  exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"
CODE="${BASH_REMATCH[4]}"

NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))+$((CODE + 1))"
TAG="v$NEW_VERSION"

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "त्रुटि: GitHub मा यो tag पहिल्यै छ: $TAG"
  exit 1
fi

sed -i "s/^version: $CURRENT$/version: $NEW_VERSION/" pubspec.yaml

git add pubspec.yaml scripts/release.sh
git commit -m "Release $NEW_VERSION"
git push origin master

git tag "$TAG"
git push origin "$TAG"

echo "Release सुरु भयो: $TAG"
