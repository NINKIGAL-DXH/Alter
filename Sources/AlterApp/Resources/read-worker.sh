#!/bin/bash
set -euo pipefail
# Index files are disk-backed and bounded separately; stdout remains capped by the host.
if [[ "${ALTER_MOLE_INDEX:-}" == "1" ]]; then ulimit -f 1048576; else ulimit -f 16384; fi
case "$1" in
    */Kernel/analyze|*/Kernel/status) exec "$@" ;;
    *) exit 64 ;;
esac
