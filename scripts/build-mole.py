#!/usr/bin/env python3
"""Build pinned Mole Go workers; never install or execute the cleanup CLI."""
from pathlib import Path
import hashlib, json, os, shutil, subprocess, tempfile

root = Path(__file__).resolve().parents[1]
vendor = root / 'Vendor/Mole'
manifest = json.loads((vendor / 'UPSTREAM.json').read_text())
for name, digest in manifest['sha256'].items():
    if hashlib.sha256((vendor / name).read_bytes()).hexdigest() != digest:
        raise SystemExit('Upstream integrity failure: ' + name)
stage = Path(tempfile.mkdtemp(prefix='alter-mole-build-'))
shutil.copytree(vendor, stage / 'source')
# Explicit integration patch: cache writes must stay in Alter's private job directory.
# Vendor/Mole remains byte-for-byte upstream, and this patch ships with source.
cache = stage / 'source/cmd/analyze/cache.go'
before = 'func moleCacheRoot(home string) string {\n\treturn filepath.Join(home, ".cache", "mole")\n}'
after = 'func moleCacheRoot(home string) string {\n\tif dir := os.Getenv("ALTER_MOLE_CACHE_DIR"); dir != "" { return dir }\n\treturn filepath.Join(home, ".cache", "mole")\n}'
source = cache.read_text()
assert source.count(before) == 1, 'Cache patch no longer matches pinned Mole'
cache.write_text(source.replace(before, after))
# Alter-owned streaming index; vendored upstream is not modified.
shutil.copy2(root / 'Integration/Mole/alter_index.go', stage / 'source/cmd/analyze/alter_index.go')
main = stage / 'source/cmd/analyze/main.go'
source = main.read_text()
needle = '\tgo pruneAnalyzerCache()'
assert source.count(needle) == 1
source = source.replace(needle, '\tif os.Getenv("ALTER_MOLE_INDEX") == "1" {\n\t\tif err := runAlterIndex(abs); err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }; return\n\t}\n' + needle)
main.write_text(source)
# macOS denies set-id /bin/ps in Seatbelt. Consume fresh, bounded native ps
# snapshots for the three fixed queries; metric parsers remain upstream.
metrics = stage / 'source/cmd/status/metrics.go'
needle = 'var runCmd = func(ctx context.Context, name string, args ...string) (string, error) {\n'
bridge = r'''	if name == "ps" && os.Getenv("ALTER_MOLE_PROCESS_DIR") != "" {
        var file string
        switch strings.Join(args, "\x00") {
        case "-Aceo\x00pid=,ppid=,state=,pcpu=,pmem=,rss=,comm=\x00-r": file = "processes"
        case "aux": file = "fallback"
        case "-Aceo\x00pcpu": file = "cpu"
        default: return "", fmt.Errorf("unsupported Alter process query")
        }
        data, err := os.ReadFile(os.Getenv("ALTER_MOLE_PROCESS_DIR") + "/" + file)
        return string(data), err
    }
'''
source = metrics.read_text()
assert source.count(needle) == 1, 'Status bridge no longer matches pinned Mole'
metrics.write_text(source.replace(needle, needle + bridge))
arch = os.environ.get('ALTER_ARCH', os.uname().machine)
assert arch in ('arm64', 'x86_64')
out = root / '.build/mole' / arch
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, GOMAXPROCS='2', GOFLAGS='-p=2', GOMEMLIMIT='512MiB',
           GOOS='darwin', GOARCH='arm64' if arch == 'arm64' else 'amd64', CGO_ENABLED='0')
go = os.environ.get('ALTER_GO', 'go')
for command in ('analyze', 'status'):
    subprocess.run([go, 'build', '-trimpath', '-ldflags=-s -w', '-o', str(out / command), './cmd/' + command],
                   cwd=stage / 'source', env=env, check=True)
# Preserve licenses for Go and every module actually linked into these workers.
licenses = out / 'licenses'
licenses.mkdir(exist_ok=True)
goroot = subprocess.check_output([go, 'env', 'GOROOT'], env=env, text=True).strip()
shutil.copy2(Path(goroot) / 'LICENSE', licenses / 'Go-LICENSE')
stream = subprocess.check_output([go, 'list', '-deps', '-json', './cmd/analyze', './cmd/status'], cwd=stage / 'source', env=env, text=True)
decoder = json.JSONDecoder(); offset = 0; modules = {}
while offset < len(stream):
    while offset < len(stream) and stream[offset].isspace(): offset += 1
    if offset == len(stream): break
    package, offset = decoder.raw_decode(stream, offset)
    module = package.get('Module', {})
    if module.get('Dir') and not module.get('Main'):
        modules[module['Path']] = module
for name, module in modules.items():
    files = [p for p in Path(module['Dir']).iterdir() if p.is_file() and p.name.lower().startswith(('license', 'copying', 'notice'))]
    if not files: raise SystemExit('Missing linked dependency license: ' + name)
    target = licenses / name.replace('/', '_'); target.mkdir(exist_ok=True)
    for file in files:
        destination = target / file.name
        if destination.exists(): destination.chmod(0o644)
        shutil.copyfile(file, destination)
        destination.chmod(0o644)
(licenses / 'modules.json').write_text(json.dumps({name: module.get('Version') for name, module in modules.items()}, indent=2) + '\n')
print(out)
