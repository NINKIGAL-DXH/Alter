# Alter

A personal macOS space-inspection companion with a native SwiftUI interface, Liquid Glass navigation and 23 character expressions. The supplied character portrait is used for both the app icon and in-app identity.

**Safety-first 0.1.0:** scans are read-only. After explicit per-file review, only user-owned installer files in `~/Downloads` (and one level below) that have not changed for at least 30 days may be moved to Trash. No permanent delete, Trash emptying, privileged helper, sudo, system optimization, app uninstall, or recursive removal is available in the application.

## Mole core and attribution

Alter embeds and actually invokes the **path and application protection core from [tw93/Mole](https://github.com/tw93/Mole)**, pinned to **V1.55.0**, commit `69ab325d4f05af0ea21aeeeae544046c9f04a76b` (GPL-3.0). The upstream files are unmodified and SHA-256 verified before every policy run. Mole's `should_protect_path` and `is_path_whitelisted` predicates gate installer selection and are re-run immediately before a confirmed operation.

The native, bounded Swift scanner and reversible move/restore adapter are Alter code. This is **not** the full Mole CLI or the separate proprietary Mole for Mac app. Mole's destructive command entrypoints are not shipped or exposed. Alter is an independent derivative and is not endorsed by or affiliated with Mole. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the bundled provenance manifest.

## Interface

- Native sidebar and toolbar; SwiftUI `glass` / `glassProminent` buttons on macOS 26+.
- Readable standard-material content, with Reduce Transparency and Reduce Motion support.
- Large character panels on both cleanup and space-details pages.
- All 23 supplied expressions, each with a contextual caption and manual preview.
- System/light/dark appearance, optional companion, bounded thumbnail cache.
- The approved original HTML is preserved as `ui-preview/Alter.html`; `ui-preview/Alter-glass.html` is the updated portable design preview. These HTML files contain only demonstration data. The native application uses actual local metadata and does not fabricate results.

The design follows [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): glass for controls/navigation, standard materials for content.

## Build and download

Requires macOS 14+, and Xcode 26+ / a matching recent Command Line Tools SDK to build. Liquid Glass requires macOS 26; macOS 14–15 use standard material and bordered controls.

```sh
python3 scripts/verify.py
swift test --jobs 2
./scripts/build.sh
./scripts/make-dmg.sh
```

GitHub Actions builds Apple Silicon and Intel DMGs on macOS runners, verifies their images and uploads checksums and matching source archives. The local default architecture is the host architecture. Output is under `dist/`. Existing output is never silently overwritten.

Builds are **ad-hoc signed, not Developer ID signed or notarized**. No signing certificate was supplied. See [installation notes](docs/INSTALL.md). No instruction or script disables Gatekeeper or clears quarantine.

## Operational limits

| Surface | Bound |
| --- | --- |
| Active scan tasks | 1 |
| Downloads scan | 10 seconds, 30,000 entries, 128 retained results, one subdirectory level |
| Cache inspection | 12 seconds, 60,000 entries, 64 retained results; read-only |
| Selected-folder scan | 20 seconds, 100,000 entries, 300 retained large-file results |
| Traversal | physical descriptor-relative traversal; no symlink following; no cross-device traversal; depth capped at 24 |
| Images | downsampled on demand; 20 MB NSCache budget, 16 cached images; no decoded original-image gallery |
| Mole worker | batches ≤64 paths; 10-second wall timeout; 8-second CPU / 128 MiB sampled worker RSS / 64-fd limits; sanitized environment |
| Move confirmation | ≤20 files / 25 GB, expires after 5 minutes, defaults to no selection |
| Recovery records | ≤200 / 256 KiB, refuses additional moves rather than discarding recovery records |

An NSCache budget is an eviction target, not a total-process memory ceiling. OS memory-pressure notifications cancel scanning and flush image caches. These safeguards reduce resource exhaustion risk; they cannot prove that an app never runs out of memory on every system.

## Scope and limitations

Cache and application inventory are read-only in this release. No automatic cache cleaning, application uninstall, login-item changes, package-manager operations, system-service restarts, background agents, scheduled scans, network analytics, or auto-update code.

Space totals are allocated-byte estimates for physically visited regular files. Hardlinks are excluded to avoid double counting; APFS clones, compression, permissions, skipped bundles and traversal limits mean totals can be partial and are labelled accordingly. Moving into Trash does **not** reclaim free space until the user separately manages Trash.

Restore uses Alter's local history and never overwrites an existing destination. The moved file gets a unique `Alter-UUID.ext` name to avoid path/name collisions. After an app crash between the atomic move and history persistence, the file remains in Trash and may require manual recovery. There is no claim of filesystem transactionality against a malicious process running as the same user.

## License and artwork

Alter code is GPL-3.0; full corresponding source is in this repository and supplied with build artifacts. Mole copyright and license notices are retained. All character screenshots and the icon were supplied by the user for a private personal prototype. Character/artwork rights remain with their respective owners and are **not** licensed under the code's GPL terms. This repository defaults to private; public artwork redistribution needs separate rights review.
