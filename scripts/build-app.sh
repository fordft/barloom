#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BARLOOM_CONFIGURATION="release"
BARLOOM_LAUNCH=false
# Set this to an Apple Development certificate to keep the app's privacy
# permission identity stable across local rebuilds. The portable default is ad hoc.
BARLOOM_SIGNING_IDENTITY="${BARLOOM_SIGNING_IDENTITY:--}"
for argument in "$@"; do
    case "$argument" in
        --debug) BARLOOM_CONFIGURATION="debug" ;;
        --launch) BARLOOM_LAUNCH=true ;;
        *) printf 'Unknown option: %s\nUsage: scripts/build-app.sh [--debug] [--launch]\n' "$argument" >&2; exit 1 ;;
    esac
done

cd "$PROJECT_ROOT"
swift build --configuration "$BARLOOM_CONFIGURATION" --product Barloom
BARLOOM_BIN_PATH="$(swift build --configuration "$BARLOOM_CONFIGURATION" --show-bin-path)"
BARLOOM_APP_PATH="$PROJECT_ROOT/.build/Barloom.app"
BARLOOM_STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/.build/barloom-bundle.XXXXXX")"
trap 'rm -rf "$BARLOOM_STAGING_DIR"' EXIT
BARLOOM_STAGED_APP="$BARLOOM_STAGING_DIR/Barloom.app"
mkdir -p "$BARLOOM_STAGED_APP/Contents/MacOS" "$BARLOOM_STAGED_APP/Contents/Resources"
cp "$BARLOOM_BIN_PATH/Barloom" "$BARLOOM_STAGED_APP/Contents/MacOS/Barloom"
cp "$PROJECT_ROOT/Resources/Info.plist" "$BARLOOM_STAGED_APP/Contents/Info.plist"

if [[ ! -f "$PROJECT_ROOT/.build/Barloom.icns" || "$PROJECT_ROOT/tools/CreateIcon.swift" -nt "$PROJECT_ROOT/.build/Barloom.icns" ]]; then
    swift "$PROJECT_ROOT/tools/CreateIcon.swift" "$PROJECT_ROOT/.build/Barloom.iconset"
    iconutil --convert icns "$PROJECT_ROOT/.build/Barloom.iconset" --output "$PROJECT_ROOT/.build/Barloom.icns"
fi
cp "$PROJECT_ROOT/.build/Barloom.icns" "$BARLOOM_STAGED_APP/Contents/Resources/Barloom.icns"
codesign --force --sign "$BARLOOM_SIGNING_IDENTITY" --timestamp=none "$BARLOOM_STAGED_APP"
if [[ -e "$BARLOOM_APP_PATH" ]]; then
    mv "$BARLOOM_APP_PATH" "$BARLOOM_STAGING_DIR/previous.app"
fi
mv "$BARLOOM_STAGED_APP" "$BARLOOM_APP_PATH"
printf '\nBuilt: %s\n' "$BARLOOM_APP_PATH"

if [[ "$BARLOOM_LAUNCH" == true ]]; then
    open "$BARLOOM_APP_PATH" --args --show-dashboard
fi
