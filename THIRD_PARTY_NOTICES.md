# Third-party notices

## Mole

- Project: https://github.com/tw93/Mole
- Authors: tw93 and Mole contributors.
- Pinned release: V1.55.0.
- Pinned commit: 69ab325d4f05af0ea21aeeeae544046c9f04a76b.
- License: GNU GPL version 3; full text in LICENSE and Vendor/Mole/LICENSE.
- Vendor/Mole/UPSTREAM.json identifies and hashes 118 unchanged upstream files, including the shell modules and source for analyze/status. Legacy pure protection modules remain in Sources/AlterApp/Resources/Mole for compatibility.
- Runtime integration: clean dry-run ledger, installer/project detection, uninstall discovery and sibling protection, path policy, 21-entry optimization catalog and individual handlers, plus Go analyze/status JSON workers.
- Separate Alter adapters implement write-denying preview, bounded processes, fixed read-only native process snapshots, GUI confirmation and recoverable native Trash moves. The discovery-only uninstall permission preflight is adapted for Seatbelt; no upstream privileged batch removal entrypoint is called. Whitelist migration is suppressed during preview.
- `scripts/build-mole.py` patches only temporary build copies: analyze cache location can be a private Alter job directory; the three fixed status ps queries can read native snapshots. The vendor files stay byte-identical. These patches and all adapter source are included in the corresponding release source archive.

The command-line project's GPL code is distinct from the separately distributed Mole for Mac GUI. Alter does not incorporate that GUI's source and is not an official Mole product. Mole's name, logo and trademarks remain with their owners; see Vendor/Mole/TRADEMARK.md. No association or endorsement is asserted.

## Go and linked modules

Go workers use the pinned upstream go.mod/go.sum. Builds copy the Go LICENSE and license/notice files from each actually linked Go module into `Alter.app/Contents/Resources/AlterAssets/Kernel/licenses/`. Its `modules.json` lists linked module versions. The build fails if a linked module license cannot be located. Their respective licenses and copyright notices apply independently and are not replaced by Alter's GPL notice.

## Character artwork

The 23 supplied screenshots and supplied app portrait depict Jeanne d'Arc Alter from the Fate franchise. They are user-provided reference assets for this independently developed fan project. Original game, character, artwork and trademark rights remain with their respective owners. Images are excluded from the code's GPL license. Public repository access is not a grant of redistribution or commercial-use rights; no ownership or blanket permission is asserted.

## Platform and design references

SwiftUI, AppKit, macOS and Liquid Glass are Apple technologies. Alter uses public APIs and SF Symbols. The space visualization independently implements area-proportional circles, influenced by the publicly documented Space Lens interaction in CleanMyMac. No Apple, MacPaw or Mole GUI source/assets are copied. Alter is not endorsed by those companies.
