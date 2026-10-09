#!/bin/zsh
# Build YTTranscript.app (sans Xcode, via swiftc des Command Line Tools).
#
# Compilation en deux étapes, pour refléter la séparation en deux modules
# SwiftPM (Package.swift) :
#   1. YTTranscriptCore (logique pure, testée via `swift test`) → module +
#      objet.
#   2. YTTranscript (SwiftUI/AppKit/Translation) → lié contre le module Core.
# SwiftPM lui-même ne peut pas construire l'app (bug de liaison du manifeste
# sur les CLT 26.x bêta, et incompatibilités de framework avec le toolchain
# Swift autonome utilisé pour `swift test` — voir Package.swift) ; on reste
# donc sur swiftc direct ici, comme avant la migration.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/YTTranscript.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/modules

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

COMMON_FLAGS=(-target arm64-apple-macos15.0 -Xcc -ivfsoverlay -Xcc "$OVERLAY" -vfsoverlay "$OVERLAY")

# 1. YTTranscriptCore : module + objet (-wmo requis pour un seul fichier
#    objet en sortie avec -emit-object sur plusieurs sources).
swiftc -O -wmo -parse-as-library "${COMMON_FLAGS[@]}" \
  -emit-module -emit-module-path build/modules/YTTranscriptCore.swiftmodule \
  -emit-object -o build/YTTranscriptCore.o \
  -module-name YTTranscriptCore \
  Sources/YTTranscriptCore/*.swift

# 2. YTTranscript : lié contre le module Core.
swiftc -O -parse-as-library "${COMMON_FLAGS[@]}" \
  -I build/modules \
  Sources/YTTranscript/*.swift build/YTTranscriptCore.o \
  -o "$APP/Contents/MacOS/YTTranscript"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signature ad hoc : suffisante pour un usage local, aucune notarisation.
codesign --force --sign - "$APP"

echo "OK → $PWD/$APP"
