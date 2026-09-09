#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$source_root"

for command_name in qmllint omarchy; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "test.sh: missing test command: $command_name" >&2
    exit 1
  }
done

if command -v cargo >/dev/null 2>&1; then
  cargo fmt --manifest-path backend/Cargo.toml --all -- --check
  cargo test --manifest-path backend/Cargo.toml --quiet
  cargo clippy --manifest-path backend/Cargo.toml --all-targets -- -D warnings
fi

qml_test_runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $qml_test_runner ]] || {
  echo "test.sh: Qt 6 qmltestrunner is missing: $qml_test_runner" >&2
  exit 1
}

omarchy plugin validate .
# Lint every source file so a new one is never missed.
qmllint -I /usr/share/omarchy/shell ./*.js ./*.qml

QT_QPA_PLATFORM=offscreen "$qml_test_runner" \
  -input tests \
  -import "$source_root" \
  -o -,txt

PYTHONDONTWRITEBYTECODE=1 python3 "$source_root/tests/test_connect_helper.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$source_root/tests/test_page_interface.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$source_root/tests/test_oauth_callback.py"
"$source_root/tests/test-scripts.sh"

if rg -n 'QtWebEngine|WebEngineView|WebView|playerctl|node_modules' \
  --glob '*.qml' --glob '*.js' --glob '*.sh' --glob '*.service' \
  --glob '!scripts/test.sh' .; then
  echo "test.sh: forbidden heavyweight runtime dependency found" >&2
  exit 1
fi

echo "All validation and tests passed."
