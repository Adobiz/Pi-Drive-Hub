#!/usr/bin/env python3
"""Export mac/ and its root workflow for merging into the existing repository."""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
# Use an isolated index so this also works before the first git init.
with tempfile.TemporaryDirectory(prefix='pi-source-index-') as index:
    subprocess.run(['git', 'init', '--quiet', index], check=True)
    command = ['git', '-c', 'core.excludesFile=/dev/null',
               '--git-dir=' + index + '/.git', '--work-tree=' + str(ROOT)]
    result = subprocess.check_output(command + [
        'ls-files', '--others', '--exclude-standard', '-z'], cwd=ROOT)
    candidates = sorted(os.fsdecode(p) for p in result.split(b'\0')
                        if p and not os.fsdecode(p).startswith('.git/')
                        and os.fsdecode(p) != '.git')

workflow_path = Path('.github/workflows/macos.yml')
workflow = ROOT / workflow_path
if not workflow.is_file():
    workflow = ROOT.parent / workflow_path
assert workflow.is_file(), 'Missing root macOS workflow'
files = {f'mac/{p}': ROOT / p for p in candidates if not p.startswith('.github/')}
files[workflow_path.as_posix()] = workflow
files = dict(sorted(files.items()))

patterns = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'GitHub token': rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})',
    'AWS access key': rb'AKIA[0-9A-Z]{16}',
    'embedded login credential': rb'''["']?(?:BDUSS|__puus|refresh_token|access_token)["']?\s*[:=]\s*["'][^"'\s]{20,}["']''',
}
issues = []
for relative, source in files.items():
    allowed_root = ROOT.parent if source == workflow else ROOT
    if not source.resolve().is_relative_to(allowed_root):
        issues.append((relative, 'symlink outside project')); continue
    if source.is_symlink() and os.path.isabs(os.readlink(source)):
        issues.append((relative, 'absolute symlink')); continue
    data = source.read_bytes()
    for name, pattern in patterns.items():
        if re.search(pattern, data):
            issues.append((relative, name))
if issues:
    for relative, reason in issues:
        print(f'BLOCKED: {relative}: {reason}')
    raise SystemExit('Review these files before exporting. No credential values were printed.')

required = ['.gitignore', 'pubspec.lock',
            'macos/Podfile.lock', 'third_party/tray_manager_local/LICENSE']
assert all(name in candidates for name in required), 'Missing required source files'
assert not any(p.startswith(('build/', '.dart_tool/', 'macos/Pods/')) for p in candidates)

export_parent = BUILD / 'github-source'
export_parent.mkdir(exist_ok=True)
destination = export_parent / 'Pi-Drive-Hub'
with tempfile.TemporaryDirectory(prefix='.source-stage-', dir=BUILD) as staging:
    staged = Path(staging) / destination.name
    for relative, source in files.items():
        target = staged / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_symlink():
            target.symlink_to(os.readlink(source))
        else:
            shutil.copy2(source, target)
    if destination.exists():
        shutil.rmtree(destination)
    shutil.move(str(staged), destination)

(export_parent / 'manifest.txt').write_text('\n'.join(files) + '\n')
version = re.search(r'^version:\s*([^+\s]+)', (ROOT / 'pubspec.yaml').read_text(), re.M).group(1)
output = BUILD / 'distribution' / f'Pi-Drive-Hub-mac-overlay-{version}.zip'
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for relative in files:
        archive.write(destination / relative, f'{destination.name}/{relative}')
    assert archive.testzip() is None
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix('.zip.sha256').write_text(f'{checksum}  {output.name}\n')
print(f'Merge files: {len(files)}')
print('Common private-key/token patterns: no matches (not a complete security audit)')
print(f'Merge overlay: {destination}')
print(f'Manifest: {export_parent / "manifest.txt"}')
print(f'Source archive: {output}')
