#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/HermesDashboard.app"

cd "$PROJECT_DIR"
swift build --configuration release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/HermesDashboard" "$APP_DIR/Contents/MacOS/HermesDashboard"
cp "$PROJECT_DIR/Sources/HermesDashboard/Resources/dashboard-data.json" "$APP_DIR/Contents/Resources/dashboard-data.json"
cp "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/HermesDashboard"

printf 'macOS 应用已生成：%s\n' "$APP_DIR"
printf '可通过 open "%s" 启动。\n' "$APP_DIR"
