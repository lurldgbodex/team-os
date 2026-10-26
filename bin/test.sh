#!/usr/bin/env bash
# Run the hygiene check and every bats test. Needs bats (https://bats-core.readthedocs.io).
#   macOS: brew install bats-core      Linux: apt install bats      any: npm i -g bats
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/bin/hygiene.sh" || exit 1

if ! command -v bats >/dev/null 2>&1; then
  echo "bats is not installed, see the header of this script." >&2
  exit 1
fi
exec bats "$ROOT"/tests/*.bats
