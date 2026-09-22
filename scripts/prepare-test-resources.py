#!/usr/bin/env python3
from pathlib import Path
import shutil, os
root = Path(__file__).resolve().parents[1]
out = root / '.build/test-resources'
out.mkdir(parents=True, exist_ok=True)
for name in ('read-worker.sh', 'read-worker.sb', 'mole-adapter.sh', 'mole-preview.sb', 'mole-optimize-run.sh'):
    shutil.copy2(root / 'Sources/AlterApp/Resources' / name, out / name)
shutil.copytree(root / 'Vendor/Mole', out / 'MoleFull', dirs_exist_ok=True)
(out / 'Kernel').mkdir(exist_ok=True)
for name in ('analyze', 'status'):
    shutil.copy2(root / '.build/mole' / os.environ.get('ALTER_ARCH', os.uname().machine) / name, out / 'Kernel' / name)
