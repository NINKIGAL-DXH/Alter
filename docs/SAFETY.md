# Safety boundary and verification

The UI has no arbitrary command box, JavaScript bridge, privileged helper, update installer, agent or background scan. It never asks for admin privileges. The only subprocess entrypoint is a fixed bundled policy adapter executed with a sanitized environment inside a write/network-denying sandbox. Missing sandbox support, invalid core hashes, timeouts, unexpected output or a policy refusal leave every file unselected/read-only.

The native scanner uses opendir/readdir and descriptor-relative metadata. It holds no complete tree, does not read file bodies, does not open archives, and cannot trigger a cloud download by reading data. Symlinks and other devices are skipped. Deadline, entry, depth and result limits bound work and retained data. A timeout/error/cancellation on installer discovery makes its candidates ineligible for moving.

Installer moves require an app-created selection plan, a second Mole check, current-user ownership, a regular file, one hard link, a supported extension, old mtime/ctime/birthtime, a safe parent chain, and an exact identity match. The pinned parent directory must not be group/world writable. The destination Trash is current-user owned and private. renameatx_np(RENAME_EXCL) performs the same-volume move relative to pinned directory descriptors. Cross-device moves fail; no copy/delete fallback exists. No directory removal is implemented.

Restore validates the recorded identity in Trash and the original Downloads directory, opens physical parent descriptors again, and performs a no-overwrite atomic rename. A conflict stops restoration and leaves both items intact.

## Explicit limitations

- File identity validation followed by a rename is not a fully atomic compare-and-rename. A malicious same-user process can race a final leaf replacement. The app never operates as root, never follows ancestor symlinks, and limits move sources to Downloads, but does not claim isolation against a compromised same-user account.
- There is a small crash window between a successful move and history persistence. The file remains recoverable in Trash under its unique name. No fallback ever permanently removes it.
- NSCache's 20 MB setting is advisory. UI frameworks and decoded currently-visible images consume additional memory. Pressure handling, lazy rendering, bounded result sets, file-descriptor limits and single-worker traversal reduce but cannot eliminate out-of-memory risk.
- Permission-denied and budget-limited scans are reported as partial, never treated as complete scan evidence.
- FileManager use in production is limited to app-owned history, resource reads and system metadata. It is not used for user-file recursive removal.

## Tests

swift test operates only inside UUID-named temporary fixture roots. Tests cover symlink leaves/ancestors, hardlinks, forbidden paths, recently modified files, stale confirmations, file identity changes, bounded/cancelled traversal, exact-content Trash/restore, restore collisions, invalid history files, live Mole protection decisions and an attempted sandbox write to a fixture sentinel.

No test scans or cleans the real user Downloads/Library directories. The app itself is only visually inspected unless the user explicitly operates its controls.
