#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-Debug}"
case "$CONFIGURATION" in
    Debug|Release) ;;
    *) echo "Usage: Tools/validate.sh [Debug|Release]" >&2; exit 2 ;;
esac

python3 Tests/test_shared_source_links.py
swift test --package-path Tools/IIJFetcher
python3 Tests/test_usage_chart_lifecycle.py
git diff --check

# The project is named IIJWidget; its app scheme is named MioWIdget.
if ! xcodebuild -scheme MioWIdget -configuration "$CONFIGURATION" > build.log 2>&1; then
    tail -n 80 build.log >&2
    exit 1
fi
tail -n 8 build.log
