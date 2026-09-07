#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Plugin installs intentionally do not run hooks, so prepare the verified or
# source-built plugin backend once the enabled plugin loads.
"$source_root/scripts/setup.sh" || exit 22
