#!/usr/bin/env bash
# Generate the Xcode project, build the app, and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen tidak ditemukan. Install: brew install xcodegen" >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild (Debug)"
xcodebuild \
  -project Wijaya.xcodeproj \
  -scheme Wijaya \
  -configuration Debug \
  -derivedDataPath build \
  build

APP_PATH="build/Build/Products/Debug/Wijaya.app"
echo "==> open $APP_PATH"
open "$APP_PATH"
