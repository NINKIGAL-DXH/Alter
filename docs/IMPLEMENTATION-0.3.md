# Alter 0.3 integration work

Development status, not a claim that every feature has passed release validation.

## Scope agreed with the user

- Fix Space Lens rescans and main-thread layout work.
- Large/old files, duplicate files, application updates and possible leftovers.
- Startup items, protected paths, menu-bar status.
- System security posture and code-signature validation, not a malware engine.
- Clearer native Liquid Glass with saturated accents and bounded animation.
- Learn the maintenance approaches of Mole and CleanMyMac; explain when each
  action is appropriate instead of advertising generic speed boosts.

## Implemented in the current working tree

The pinned Mole worker is compiled with an Alter-owned streaming traversal
adapter (`Integration/Mole/alter_index.go`) using Mole's allocated-size helper.
It records metadata into a private NDJSON file, imported into a disk-backed
SQLite index. Root scan builds all accessible descendants once. Navigation
queries the same index; explicit refresh replaces it. Moving/restoring a file
marks the display snapshot stale; write authorization never uses the index.

The adapter includes hidden directories and app bundles, skips directory
symlinks and other volumes, and records access-denied/depth-limit nodes. The
entire scan fails visibly on the overall budget instead of publishing a
silently truncated tree. Read-only canonicalization uses POSIX realpath;
Foundation can rewrite `/private/tmp` back to the `/tmp` alias, which the
physical write validator correctly refuses.

File collections reuse the index. Duplicate candidates are grouped by logical
size, hardlink identity is deduplicated, full SHA-256 hashes are streamed using
one 1 MiB buffer. Cloud placeholders are skipped. The retained copy and selected
files are hashed again before a duplicate-removal plan executes. Metadata and
Mole policy are still independently revalidated before Trash moves.

Startup management reads LaunchAgents/LaunchDaemons. Supported user agents use
launchctl enable/disable only after a specific preview; no plist deletion,
forced process termination, or root launchctl domain. Modern login items and
system daemons link to their macOS-owned settings. This does not claim that
all ServiceManagement registrations are individually editable by Alter.

The security page reads SIP, Gatekeeper, FileVault and firewall status, and
checks an application using Security.framework. Unknown/error is displayed as
unknown, not as safe. A valid signature does not prove absence of malware or
notarization.

Updates support bounded HTTPS Sparkle feeds and App Store handoff. Homebrew
checks and per-cask previews are separate; only official app-bundle recipes
without script/pkg artifacts can take the automated path. Other installers
use the owner's updater. Updating is not reversible Trash removal and is
explicitly described as such.

## Resource budgets

- Streaming traversal: 128 directory levels, batches of 128 dirents, 2 million
  records, conservatively estimated 480 MiB output; OS file cap 512 MiB.
- SQLite: 8 MiB page cache, file-backed temporary storage, 512 MiB database cap.
- Existing process-group RSS/output/time limits remain active.
- Space Lens: <= 23 circles from a 256-row visual snapshot; all indexed
  immediate children remain searchable and browsable in disk-backed pages of 100.
- File collections: cursor pages of 500. Duplicate scan: 100,000 candidates,
  10,000 identities per size group, 10,000 returned files, 1,000 groups, 900s.
- Feed: HTTPS-only redirects, ephemeral cookies/credentials, 2 MiB maximum,
  no XML entity declarations, 30s resource timeout.
- These are budgets, not an absolute guarantee against OS/framework OOM.

## Validation record and remaining release work

- Native arm64 release compilation passed.
- 33 local safety fixtures passed, including cached nested navigation, explicit
  refresh, disk pagination, duplicate retained-copy changes, cask artifact
  validation, system-domain startup refusal, and exclusions.
- Native UI navigation confirmed first scan and cached drill-down using a
  disposable fixture. Screenshot capture currently yields a Stage Manager
  thumbnail, so full-window visual fidelity remains unverified.
- Pending: GitHub arm64/Intel CI, final DMG builds and release verification.
- No real cleanup, app upgrade, startup change, or privileged maintenance has
  been executed on the development computer to test these features.

## References

- [Mole for Mac](https://mole.fit/): product information; its proprietary GUI is
  not included in Alter. The GPL CLI remains the declared core.
- [CleanMyMac](https://macpaw.com/cleanmymac): product information for management
  categories; Alter does not claim feature equivalence with its malware engine.
- [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials):
  native glass and accessibility fallbacks.
- [Homebrew commands](https://docs.brew.sh/Manpage) and
  [Sparkle appcasts](https://sparkle-project.org/documentation/publishing/):
  update source formats and owner-managed installation.
