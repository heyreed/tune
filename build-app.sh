#!/bin/bash
# Builds Tune via swift build, then wraps the binary into a .app bundle so macOS
# treats it as a proper menu-bar application (LSUIElement=true, code-signed locally, etc.)
#
# Output: ./build/Tune.app
#
# After running, drag Tune.app into /Applications and grant Accessibility permission
# in System Settings → Privacy & Security → Accessibility.

set -euo pipefail

cd "$(dirname "$0")"

echo "▸ Building release binary…"
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
APP_PATH="./build/Tune.app"
CONTENTS="$APP_PATH/Contents"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BIN_PATH/Tune" "$CONTENTS/MacOS/Tune"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/Tune.icns "$CONTENTS/Resources/Tune.icns"

# SwiftPM emits resource bundles next to the binary; copy them in so
# Bundle.module can find MenuBarIcon at runtime.
for bundle in "$BIN_PATH"/*_*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$CONTENTS/Resources/"
done

echo "▸ Ad-hoc code signing (sufficient for local use)…"
codesign --force --deep --sign - "$APP_PATH"

echo "✅ Built $APP_PATH"
echo ""
echo "Next steps:"
echo "  1. open ./build  (drag Tune.app to /Applications)"
echo "  2. Launch it once — you'll get an Accessibility prompt"
echo "  3. System Settings → Privacy & Security → Accessibility → enable Tune"
echo "  4. (Optional) Create Shortcuts named 'Tune DND On' and 'Tune DND Off' to wire DND"
