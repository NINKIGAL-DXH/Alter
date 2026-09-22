#!/bin/bash
# Execute exactly one catalog handler after Alter's task-specific confirmation.
set -euo pipefail
[[ $EUID -ne 0 && $# -eq 5 ]] || exit 64
core="$1"; task="$2"; job="$3"; authority="$4"; expires="$5"
[[ "$task" =~ ^[a-z0-9_]+$ && "$expires" =~ ^[0-9]+$ && $(date +%s) -lt "$expires" ]] || exit 65
[[ -d "$job" && ! -L "$job" && -O "$job" ]] || exit 65
ulimit -f 16384
export TMPDIR="$job" XDG_CACHE_HOME="$job/cache" MO_NO_OPLOG=1 NO_COLOR=1 MOLE_DRY_RUN=0
export MOLE_OPTIMIZE_SUDO_AVAILABLE=false MOLE_TEST_NO_AUTH=1
if [[ "$authority" == admin ]]; then
    # This branch is reached only by the user-opened Terminal handoff, not by the GUI.
    sudo -n true || exit 77
    export MOLE_OPTIMIZE_SUDO_AVAILABLE=true MOLE_TEST_NO_AUTH=0
elif [[ "$authority" != user ]]; then exit 64; fi
source "$core/lib/core/common.sh"
source "$core/lib/optimize/diagnostics.sh"
source "$core/lib/optimize/maintenance.sh"
source "$core/lib/optimize/tasks.sh"
source "$core/lib/manage/whitelist.sh"
# Do not migrate unrelated config as a side effect of a single maintenance task.
save_whitelist_patterns() { :; }
load_whitelist optimize
handler=$(optimize_catalog_handler_for "$task") || exit 64
whitelist_name=$(optimize_catalog_health_name_for "$task")
if is_whitelisted "$task"; then printf 'ALTER_OUTCOME=skipped\nProtected by Mole whitelist\n'; exit 0; fi
optimize_task_start
"$handler"
printf '\nALTER_OUTCOME=%s\n' "$MOLE_OPTIMIZE_TASK_OUTCOME"
[[ "$MOLE_OPTIMIZE_TASK_OUTCOME" != failed ]]
