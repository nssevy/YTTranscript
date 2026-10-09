#!/bin/zsh
# Lance les tests (Swift Testing) de YTTranscriptCore via SwiftPM.
#
# Pas d'Xcode installé sur cette machine → XCTest n'est pas disponible.
# On utilise Swift Testing (import Testing, @Test), livré avec le toolchain.
# `swift test` des Command Line Tools casse sur un bug de liaison du
# manifeste SwiftPM (CLT 26.x bêta) : on passe donc par le toolchain Swift
# autonome installé via `brew install swift` (keg-only, n'affecte pas le
# compilateur système utilisé par build.sh).
set -euo pipefail
cd "$(dirname "$0")"

SWIFT_BIN="${YTTRANSCRIPT_SWIFT_BIN:-/opt/homebrew/opt/swift/bin/swift}"
if [[ ! -x "$SWIFT_BIN" ]]; then
  echo "Toolchain Swift introuvable : $SWIFT_BIN" >&2
  echo "Installez-le avec : brew install swift" >&2
  exit 1
fi

"$SWIFT_BIN" test
