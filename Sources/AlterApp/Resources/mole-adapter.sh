#!/bin/bash
# Alter GPL-3.0 adapter. Upstream files stay unchanged. No batch mutation CLI.
set -euo pipefail
[[ $EUID -ne 0 && $# -ge 3 ]] || exit 64
core="$1"; action="$2"; job="$3"; shift 3
[[ -d "$core/lib" && -d "$job" && ! -L "$job" && -O "$job" ]] || exit 64
ulimit -f 16384
export TMPDIR="$job" XDG_CACHE_HOME="$job/cache" MO_NO_OPLOG=1 NO_COLOR=1
export MOLE_DRY_RUN=1 MOLE_TEST_NO_AUTH=1 MOLE_OPTIMIZE_SUDO_AVAILABLE=false
mkdir -p cache/mole
# Machine-readable records have NUL-delimited fields. Normal Mole messages go to stderr.
exec 3>&1 1>&2
emit() { printf '%s\0%s\0%s\0%s\0' "$1" "$2" "$3" "$4" >&3; }
# Only this exact process query uses the native read-only snapshot. Other
# queries keep their original failure semantics, never assume an idle owner.
ps() {
    if [[ $# -eq 2 && "$1" == -axo && "$2" == pid,ppid,comm,args && -f "$job/process-table" ]]; then
        /bin/cat "$job/process-table"
    else command ps "$@"; fi
}
case "$action" in
    clean)
        source "$core/bin/clean.sh"
        CLEAN_PREVIEW_FINAL_FILE="$job/clean-list.txt"
        start_cleanup
        perform_cleanup > "$job/clean-log" 2>&1
        emit notice "" 0 "$(tail -c 16000 "$job/clean-log")"
        emit_deduplicated_dry_run_ledger > "$job/ledger"
        while IFS= read -r -d '' identity && IFS= read -r -d '' kb && IFS= read -r -d '' count && IFS= read -r -d '' known && IFS= read -r -d '' section && IFS= read -r -d '' path; do
            emit cache "$path" "$((kb * 1024))" "$section · Mole dry-run"
        done < "$job/ledger"
        ;;
    installer)
        export MOLE_TEST_MODE=1
        source "$core/bin/installer.sh"
        if [[ $# -eq 1 ]]; then scan_installers_in_path "$1" > "$job/paths"; else scan_all_installers > "$job/paths"; fi
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            bytes=$(/usr/bin/stat -f %z "$path" 2>/dev/null) || continue
            emit installer "$path" "$bytes" "Mole 安装包识别 · 移入废纸篓"
        done < "$job/paths"
        ;;
    purge)
        [[ $# -eq 1 ]] || exit 64
        source "$core/lib/clean/project.sh"
        : > "$XDG_CACHE_HOME/mole/purge_scanning"
        scan_purge_targets "$1" "$job/paths"
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            emit artifact "$path" 0 "Mole 项目产物 · 重新使用时可能需要重新构建或下载依赖"
        done < "$job/paths"
        ;;
    uninstall)
        [[ $# -eq 1 && "$1" == *.app && "$1" != *'|'* ]] || exit 64
        source "$core/bin/uninstall.sh"
        export MOLE_DELETE_MODE=trash
        # In a write-denying sandbox, -w intentionally reports false even for
        # user-owned app parents. This is a privileged-removal preflight only;
        # Alter never calls the batch removal phase or elevates a file move.
        # The native executor checks real parent permissions and identities.
        _mole_privileged_path_has_mutable_ancestor() { return 1; }
        append_log_line() { :; }
        append_log_lines() { :; }
        target="$1"
        bundle_id=$(uninstall_resolve_eligible_bundle_id "$target" "") || exit 65
        name="${target##*/}"; name="${name%.app}"
        selected_apps=("0|$target|$name|$bundle_id|0|0")
        running_apps=(); sudo_apps=(); brew_cask_apps=(); blocked_apps=(); manual_removal_apps=(); app_details=(); apps_data=()
        total_estimated_size=0
        _batch_scan_app_details
        [[ ${#app_details[@]} -eq 1 ]] || { echo 'Mole requires the vendor uninstaller, or could not establish a safe app plan.'; exit 65; }
        IFS='|' read -r name app_path bid kb related system sensitive needs_sudo brew cask diag review helpers sibling identity original_bid fingerprint info_identity <<< "${app_details[0]}"
        # Cask uninstall scripts and vendor uninstallers may have unpreviewed side effects.
        # Show that requirement explicitly rather than pretending to uninstall the package.
        emit application "$app_path" 0 "Mole 应用预览 · 运行中的应用需先退出"
        for encoded in "$related" "$system" "$diag"; do
            printf '%s' "$encoded" | /usr/bin/base64 -D > "$job/related"
            while IFS= read -r path || [[ -n "$path" ]]; do
                [[ -n "$path" ]] || continue
                emit related "$path" 0 "Mole 关联项目 · 可能包含偏好设置与应用数据"
            done < "$job/related"
        done
        [[ "$brew" != true ]] || emit notice "" 0 "此应用归 Homebrew 管理；移动 app 不会移除 cask 收据，完整包管理卸载请使用 Homebrew。"
        ;;
    policy)
        source "$core/lib/core/common.sh"
        load_mole_whitelist "$HOME"
        for target in "$@"; do
            if should_protect_path "$target" || is_path_whitelisted "$target" || ! validate_path_for_deletion "$target"; then emit protected "$target" 0 "Mole 保护或白名单命中"; else emit review "$target" 0 "Mole 复核通过"; fi
        done
        ;;
    optimize-list)
        source "$core/lib/optimize/catalog.sh"
        for ((i=0;i<${#MOLE_OPTIMIZE_ACTIONS[@]};i++)); do
            emit "${MOLE_OPTIMIZE_ACTIONS[$i]}" "${MOLE_OPTIMIZE_HEALTH_NAMES[$i]}" 0 "${MOLE_OPTIMIZE_DESCRIPTIONS[$i]}"
        done
        ;;
    optimize-preview)
        [[ $# -eq 1 ]] || exit 64
        source "$core/lib/core/common.sh"
        source "$core/lib/optimize/diagnostics.sh"
        source "$core/lib/optimize/maintenance.sh"
        source "$core/lib/optimize/tasks.sh"
        source "$core/lib/manage/whitelist.sh"
        # Read existing whitelist without migrating or creating configuration.
        save_whitelist_patterns() { :; }
        load_whitelist optimize
        handler=$(optimize_catalog_handler_for "$1") || exit 64
        optimize_task_start
        if is_whitelisted "$1"; then optimize_task_result skipped; printf "Mole whitelist: skipped\n" > "$job/preview"; else "$handler" > "$job/preview" 2>&1; fi
        emit "$MOLE_OPTIMIZE_TASK_OUTCOME" "$1" 0 "$(cat "$job/preview")"
        ;;
    *) exit 64 ;;
esac
