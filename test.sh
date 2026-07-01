#!/bin/zsh
# Compile et exécute les tests unitaires (VTTParser, Extractor.sanitizeFilename).
# Même contournement VFS que build.sh (bug SwiftBridging des CLT 26.x).
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
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
        { "name": "module.modulemap", "type": "file",
          "external-contents": "$PWD/build/empty.modulemap" }
      ]
    }
  ]
}
EOF

swiftc -parse-as-library \
  -target arm64-apple-macos15.0 \
  -Xcc -ivfsoverlay -Xcc "$OVERLAY" \
  -vfsoverlay "$OVERLAY" \
  Sources/VTTParser.swift Sources/Extractor.swift Tests/Tests.swift \
  -o build/run-tests

./build/run-tests
