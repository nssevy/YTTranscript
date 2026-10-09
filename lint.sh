#!/bin/zsh
# Lance SwiftLint. DYLD_FRAMEWORK_PATH pointe vers sourcekitdInProc des CLT :
# sans Xcode installé, SwiftLint ne le trouve pas tout seul (dlopen échoue).
set -euo pipefail
cd "$(dirname "$0")"

export DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/usr/lib"
swiftlint "$@"
