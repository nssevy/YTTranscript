#!/bin/zsh
# Build YTTranscript.app (sans Xcode, via swiftc des Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/YTTranscript.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -ivfsoverlay : masque /Library/.../swift/module.modulemap, doublon de
# bridging.modulemap dans les CLT 26.x ("redefinition of module 'SwiftBridging'").
swiftc -O -parse-as-library \
  -target arm64-apple-macos13.0 \
  -Xcc -ivfsoverlay -Xcc vfs-overlay.yaml \
  -vfsoverlay vfs-overlay.yaml \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/YTTranscript"

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signature ad hoc : suffisante pour un usage local, aucune notarisation.
codesign --force --sign - "$APP"

echo "OK → $PWD/$APP"
