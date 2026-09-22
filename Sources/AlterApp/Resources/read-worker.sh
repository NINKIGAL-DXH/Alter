#!/bin/bash
set -euo pipefail
# stdout/stderr and any individual worker file are bounded to 8 MiB.
ulimit -f 16384
case "$1" in
    */Kernel/analyze|*/Kernel/status) exec "$@" ;;
    *) exit 64 ;;
esac
