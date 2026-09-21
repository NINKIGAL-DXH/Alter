#!/bin/bash
# Alter adapter, GPL-3.0. Only invokes Mole's pure protection predicates.
# Path arguments are positional and are never evaluated as shell code.
set -euo pipefail
[[ "$EUID" -ne 0 ]] || exit 77
[[ $# -ge 1 && $# -le 65 ]] || exit 64
core="$1"
shift
export PATH=/usr/bin:/bin
export NO_COLOR=1 MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1
ulimit -t 8
ulimit -n 64
source "$core/lib/core/app_protection.sh"
# Bound external whitelist input; never execute it.
whitelist="$HOME/.config/mole/whitelist"
if [[ -e "$whitelist" ]]; then
    [[ -f "$whitelist" && ! -L "$whitelist" ]] || exit 78
    bytes=$(/usr/bin/stat -f %z "$whitelist")
    [[ "$bytes" -le 32768 ]] || exit 78
fi
load_mole_whitelist "$HOME"
for target in "$@"; do
    [[ ${#target} -le 4096 ]] || exit 64
    if should_protect_path "$target" || is_path_whitelisted "$target"; then
        printf 'protected\n'
    else
        printf 'review\n'
    fi
done
