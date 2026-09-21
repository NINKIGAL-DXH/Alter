#!/usr/bin/env python3
"""Offline verification of shipped resources and fixed Mole provenance."""
from pathlib import Path
import hashlib, json, re
root = Path(__file__).resolve().parents[1]
mole = root / 'Sources/AlterApp/Resources/Mole'
manifest = json.loads((mole / 'UPSTREAM.json').read_text())
assert manifest['commit'] == '69ab325d4f05af0ea21aeeeae544046c9f04a76b'
for name, expected in manifest['sha256'].items():
    assert hashlib.sha256((mole / name).read_bytes()).hexdigest() == expected, name
expressions = root / 'Sources/AlterApp/Resources/Expressions'
records = json.loads((expressions / 'expressions.json').read_text())
assert [e['id'] for e in records] == list(range(1, 24))
assert len({hashlib.sha256((expressions / e['file']).read_bytes()).hexdigest() for e in records}) == 23
for e in records:
    assert (expressions / e['file']).read_bytes().startswith(b'\xff\xd8\xff')
    assert e['quote'] and e['state']
    x, y, w, h = e['crop']
    assert 0 <= x < 1 and 0 <= y < 1 and 0 < w <= 1 and 0 < h <= 1
    assert x + w <= 1.000001 and y + h <= 1.000001
assert (root / 'Sources/AlterApp/Resources/Brand/Alter.png').read_bytes().startswith(b'\x89PNG')
# Ensure no full Mole mutation entrypoints accidentally enter the distributable.
assert not (mole / 'bin').exists()
assert not (mole / 'mole').exists()
assert not (mole / 'lib/core/file_ops.sh').exists()
swift = '\n'.join(p.read_text() for p in (root / 'Sources').rglob('*.swift'))
for forbidden in ['AuthorizationExecuteWithPrivileges', 'SMJobBless', 'NSAppleScript', 'removeItem(', 'truncate(']:
    assert forbidden not in swift, forbidden
policy = (mole / 'alter-policy.sh').read_text()
assert 'should_protect_path' in policy and 'is_path_whitelisted' in policy
assert 'MOLE_DRY_RUN=1' in policy
print('PASS: pinned Mole hashes, 23 unique expressions, supplied icon, and restricted runtime surface.')
