#!/bin/bash
# Builds PresenterMode via swift build, then wraps the binary into a .app bundle so macOS
# treats it as a proper menu-bar application (LSUIElement=true, code-signed locally, etc.)
#
# Output: ./build/PresenterMode.app
#
# After running, drag PresenterMode.app into /Applications and grant Accessibility permission
# in System Settings → Privacy & Security → Accessibility.

set -euo pipefail

cd "$(dirname "$0")"

echo "▸ Building release binary…"
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
APP_PATH="./build/PresenterMode.app"
CONTENTS="$APP_PATH/Contents"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BIN_PATH/PresenterMode" "$CONTENTS/MacOS/PresenterMode"
cp Resources/Info.plist "$CONTENTS/Info.plist"

echo "▸ Ad-hoc code signing (sufficient for local use)…"
codesign --force --deep --sign - "$APP_PATH"

echo "✅ Built $APP_PATH"
echo ""
echo "Next steps:"
echo "  1. open ./build  (drag PresenterMode.app to /Applications)"
echo "  2. Launch it once — you'll get an Accessibility prompt"
echo "  3. System Settings → Privacy & Security → Accessibility → enable Presenter Mode"
echo "  4. (Optional) Create Shortcuts named 'Presenter Mode DND On' and 'Presenter Mode DND Off' to wire DND"
