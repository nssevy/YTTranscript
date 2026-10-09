#!/bin/bash
# Hook PostToolUse : après chaque Write/Edit/MultiEdit sur un .swift sous
# Sources/ ou Tests/, relance la suite de tests (test.sh). Si elle échoue,
# bloque le tour en renvoyant la sortie à Claude — TDD strict, pas de
# régression silencieuse.
set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')

if [[ ! "$file" =~ (Sources|Tests)/.*\.swift$ ]]; then
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 0

output=$(./test.sh 2>&1)
code=$?

if [ "$code" -ne 0 ]; then
  reason=$(printf 'Les tests ont échoué après modification de %s :\n\n%s' "$file" "$output")
  jq -n --arg reason "$reason" '{"decision":"block","reason":$reason}'
fi

exit 0
