#!/bin/zsh
# Build YTTranscript.app (sans Xcode, via swiftc des Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/YTTranscript.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Contournement d'un bug des CLT 26.x : module.modulemap et bridging.modulemap
# définissent tous deux le module 'SwiftBridging' ("redefinition of module").
# On masque le doublon via un overlay VFS généré ici (clang exige des chemins
# absolus dans "external-contents", donc on les calcule au build).
OVERLAY=build/vfs-overlay.yaml
printf '// vide : masque le doublon SwiftBridging de module.modulemap\n' > build/empty.modulemap
cat > "$OVERLAY" <<EOF
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "type": "directory",
      "contents": [
        {
          "name": "module.modulemap",
          "type": "file",
          "external-contents": "$PWD/build/empty.modulemap"
        }
      ]
    }
  ]
}
EOF

swiftc -O -parse-as-library \
  -target arm64-apple-macos13.0 \
  -Xcc -ivfsoverlay -Xcc "$OVERLAY" \
  -vfsoverlay "$OVERLAY" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/YTTranscript"

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signature ad hoc : suffisante pour un usage local, aucune notarisation.
codesign --force --sign - "$APP"

echo "OK → $PWD/$APP"
