# Third-party notices

## Mole

- Project: https://github.com/tw93/Mole
- Authors: tw93 and Mole contributors
- Pinned release: V1.55.0
- Pinned commit: 69ab325d4f05af0ea21aeeeae544046c9f04a76b
- License: GNU GPL version 3; full text in LICENSE and Sources/AlterApp/Resources/Mole/LICENSE.
- Unmodified files: lib/core/base.sh, app_protection.sh, app_protection_data.sh, timeout.sh and timeouts.sh; hashes in UPSTREAM.json.
- Alter modifications: separate read-only sandbox adapter; bounded native scanner; stricter installer-only Trash workflow. The bundled upstream files themselves are unchanged.
- Actual runtime calls: should_protect_path, is_path_whitelisted, load_mole_whitelist. Unused upstream function definitions do not constitute exposed app features. No Mole cleanup/uninstall/optimization entrypoint is distributed.

Mole's name and logo remain its project's trademarks. Alter uses its own name and a user-supplied icon. It is not Mole for Mac and has no official association or endorsement.

## Character artwork

The 23 supplied screenshots and the supplied app portrait depict Jeanne d'Arc Alter from the Fate franchise. They are user-provided reference assets for a private personal build. The original game/character/artwork rights remain with their respective owners. These assets are excluded from the GPL license applied to code. No ownership or blanket redistribution permission is asserted.

## Apple

SwiftUI, AppKit, macOS and Liquid Glass are Apple technologies. The interface uses public platform APIs and SF Symbols, and does not include copied Apple app assets. This is not an Apple product or endorsement.
