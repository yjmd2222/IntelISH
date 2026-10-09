#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Assemble already built rotation components. No installation or publication."""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path
import plistlib

parser = argparse.ArgumentParser(description=__doc__)
for name in ('app', 'intelish', 'fbreannounce', 'output'):
    parser.add_argument('--' + name, type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
expected = {
    'IntelISHRotation.app': (args.app, 'org.yjmd2222.ISHRotation', '0.1.2'),
    'IntelISH.kext': (args.intelish, 'org.yjmd2222.IntelISH', '0.7.0'),
    'FBReannounce.kext': (args.fbreannounce, 'org.yjmd2222.FBReannounce', '0.2.3'),
}
# Validate before making an output directory.
manifest = {}
for name, (path, identifier, version) in expected.items():
    info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != identifier or info.get('CFBundleShortVersionString', info['CFBundleVersion']) != version:
        raise SystemExit('Unexpected component identity/version: ' + str(path))
    subprocess.run(['codesign', '--verify', '--strict', str(path)], check=True)
    binary = path / 'Contents/MacOS' / info['CFBundleExecutable']
    manifest[name] = {'version': version, 'executable_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
if args.output.exists():
    raise SystemExit('Output already exists: ' + str(args.output))
args.output.mkdir(parents=True)
for name, (path, _, _) in expected.items():
    subprocess.run(['cp', '-R', '-X', str(path), str(args.output / name)], check=True)
shutil.copyfile(root / 'LICENSE', args.output / 'IntelISH-LICENSE.txt')
shutil.copyfile(Path(__file__).with_name('README.md'), args.output / 'README.md')
# FBReannounce is GPL-2.0-only too; retain the license name in the package.
shutil.copyfile(root / 'LICENSE', args.output / 'FBReannounce-LICENSE.txt')
manifest['required_lilu'] = {'repository': 'https://github.com/yjmd2222/Lilu', 'branch': 'x2g2-userpatch', 'commit': '57bfe9ce4c47e10d1c5874a72d1c6d7a7a76bcd9', 'version': '1.7.3', 'included': False}
manifest['kext_source_revisions'] = {'IntelISH': 'f31fe3defdca1b8cabc693aad3fd0773146ffe2f', 'FBReannounce': 'a00a76977d3df82a8a92efafead1af3998f6f501'}
manifest['intelish_app_source_head'] = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
manifest['intelish_app_source_dirty'] = bool(subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip())
(args.output / 'components.json').write_text(json.dumps(manifest, indent=2) + '\n')
subprocess.run(['ditto', '-c', '-k', '--keepParent', str(args.output), str(args.output) + '.zip'], check=True)
print(str(args.output) + '.zip')
