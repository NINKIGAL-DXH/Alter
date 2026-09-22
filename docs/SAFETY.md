# Safety design and limitations — Alter 0.2

## Two independent write paths

File cleanup, installer cleanup, app removal and project-artifact removal use a native reviewed move to Trash. System maintenance uses one explicitly confirmed upstream optimize handler. There is no generic shell command input, batch optimize button, launch agent, privileged helper, automatic cleanup, self-update installer or root GUI.

Discovery is not authorization. Candidates start unselected. The file confirmation shows every selected path, size, object count and reason; directories are moved as whole trees. A maintenance confirmation shows the selected task, upstream dry-run output, effects and lack of automatic rollback. These are task previews, not exhaustive transaction logs of every internal command. Only the user's later action executes them.

## Discovery and reading

Pinned source hashes are verified before shell discovery or maintenance. Go binaries are built from the pinned source plus the two source-visible integration patches in `scripts/build-mole.py`; the packaged app and workers are code signed. A SHA manifest bundled alongside source is provenance checking, not independent protection against an attacker replacing the whole app.

`mole-preview.sb` and `read-worker.sb` deny network and file writes except the UUID private job directory and `/dev/null`. Fixed adapters choose upstream discovery functions or `analyze --json` / `status --json`; they never invoke the upstream batch removal phase. Unrecognized responses and worker failures stop the request. Discovery searches system tools first, then the standard /opt/homebrew/bin and /usr/local/bin prefixes, with Homebrew auto-update, analytics and installation cleanup disabled. It does not inherit arbitrary shell startup files or PATH entries.

macOS denies executing set-id `/bin/ps` within Seatbelt. The native host therefore captures fixed read-only queries with time/output budgets, stores them in the private job and gives them to the original Mole parsers. Snapshot capture failure stops the request. The process table is not sent to a server or logged; it can contain private command arguments and is removed with the job. Each policy invocation captures it again. It is still a snapshot: an app can start after a check.

Apple Bash 3.2's here-strings/heredocs ignore TMPDIR. The preview profile denies metadata probes of the global temporary roots so Bash falls back to the private job working directory; it does not grant global /tmp write access. The process cwd is explicitly pinned to that job.

The uninstall preview adapts a privileged-removal ancestor preflight because a write-denying sandbox makes `-w` fail even for writable user-owned app folders. This override exists only in the discovery adapter. Alter never invokes Mole's privileged batch removal routine: physical parent checks and actual permissions are tested independently by the native executor. Existing whitelist files are read without legacy migration writes. Upstream files remain unchanged in Vendor.

Mole may read archive listings and configuration files during discovery. Status reads system metrics. The recursive move snapshot itself reads metadata only. Neither read-only scanning nor listing a candidate means it is eligible for removal. System paths remain read-only; macOS TCC/SIP restrictions are not bypassed. Inaccessible content can be absent from reported totals.

## Reviewed moves and recovery

Plans accept 1–64 unique, non-overlapping roots and expire after five minutes. Each root must be in the current home, a directly contained /Applications app, or a selected volume path; broad protected home/system/configuration roots and security directories are refused. A cross-volume move still fails at the final atomic rename. Running selected apps are refused, never force-quit.

Physical parent descriptors are opened without following symlinks. Symlink roots, hardlinked regular roots and immutable/restricted roots are refused. Nested symlinks are fingerprinted as links and are never followed. A streaming SHA-256-based metadata fingerprint includes relative paths, device/inode, mode, byte size and nanosecond modification/change times. Limits are 400,000 objects, 128 levels and 120 seconds per selected root. A changed tree invalidates the plan. Project and uninstall discovery run again before execution to preserve current identification and sibling-app rules.

Immediately before each move, Alter checks the original identity, current parent permissions, a private current-user Trash directory, and cancellation. `renameatx_np(RENAME_EXCL)` performs a descriptor-relative same-volume, no-overwrite move. There is no copy/delete fallback and no root file move. Restore rechecks identity and safe destination scope and refuses a naming conflict. New records preserve compatibility with the old installer-only records.

The app never empties Trash. Moving files there does not immediately reclaim volume space. History is bounded at 200 records / 256 KiB and does not discard older restoration information to make room. After a partial run, completed moves are reported separately.

## Maintenance

Only IDs in the bundled 21-entry Mole catalog resolve to handlers. Unknown IDs and stale authorization timestamps fail. Current-user execution sets Mole's no-auth guard. The optional Terminal handoff displays the exact task and expires after five minutes, runs `sudo -v` in Terminal, then calls the same app's fixed maintenance entrypoint as the current user. The app itself must never run as root. It does not save passwords, modify PAM, install a helper or maintain a sudo keepalive.

Maintenance may permanently remove history, rebuild databases, change permissions/preferences or restart services. It cannot use file-move recovery. Upstream protections, running-app checks, whitelist and task-specific limits remain active; the handlers may still have bugs or effects beyond their short descriptions. `disk_verify` retains its upstream default disabled state because uninterruptible APFS verification can freeze a machine. A skipped task is not represented as applied.

The development verification did not execute real maintenance or authenticate sudo. Administrator handoff and privileged handler effects have not been end-to-end tested on this user's system. Permission failures and partial results must be read before retrying.

## Resource limits and residual risks

- One GUI worker at a time. Go targets 256 MiB and two execution threads; the host samples the dedicated process group every 0.5 seconds and stops around 512 MiB resident memory or 64 subprocesses. These are sampled limits, not guaranteed hard ceilings.
- stdout/stderr are bounded to 8 MiB each. Discovery is capped at 900 seconds, status at 60, each native ps query at 10 and maintenance at 600. Cancellation kills the dedicated worker group, never arbitrary user processes. Root descendants or kernel-blocked operations may not be immediately observable or terminable by the current user.
- Discovery retains at most 5,000 candidates; exceeding the display budget is explicitly reported. Analysis rejects more than 50,000 direct children. The UI renders at most 23 circles and pages the full child list by 100. This does not imply an arbitrary filesystem can always be completely scanned within budget.
- Images are thumbnail-decoded and lazily displayed with advisory 20 MB / 16-item cache limits. Framework allocations and visible images add memory. Memory pressure requests cancellation and cache eviction; OOM cannot be ruled out.
- Identity check followed by rename is not an atomic compare-and-rename. A malicious same-user process can race the final step or mutate a tree after fingerprinting. Parent descriptors and rechecks reduce accidental races but do not isolate a compromised account.
- A crash after rename but before history persistence leaves a recoverable uniquely named item in Trash, possibly without a history row. Native error reporting cannot roll back every partial maintenance operation.
- APFS allocation, snapshots, links, permissions and concurrent changes affect size estimates. Zero or absent hardware metrics are not proof that a sensor reports zero.

## Verification

The 25 Swift test methods cover pinned Mole discovery/guards, real status JSON, running-cache protection, temporary app/artifact/installers, physical path constraints, cancellation/output limits, tree changes, Trash restore/conflicts, history safety and circle layout. Mutation fixtures are UUID directories created by the tests. Some upstream diagnostics and status read actual system metadata; no test invokes actual system maintenance or deletes user files.

Local CLT runs use `scripts/test-local.py` over those same methods. GitHub runs XCTest and packages/validates both architectures. App resource smoke checks validate all 23 image crops, the icon, full shell source hashes, both Go workers and linked dependency license metadata.
