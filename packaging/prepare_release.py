"""Collect the qualified CI artifacts into release assets.

Usage: prepare_release.py ARTIFACT_DIR OUTPUT_DIR

Only artifacts from a CI run whose required tests passed reach this step. Each
architecture contributes one portable ZIP and its MSI; both architectures must
have been built from the identical source snapshot, which is published once.
"""
from pathlib import Path
import shutil
import sys
import zipfile

VERSION = '3.10.22-2'
MEMBERS = (
    'arj.exe',
    'rearj.exe',
    'arjcrypt.dll',
    'COPYING',
    'COPYRIGHT.txt',
    'rearj.cfg.example',
    'PACKAGING.md',
    'source.tar.gz',
)

artifacts, output = map(Path, sys.argv[1:])
output.mkdir()
source = None
for architecture in ('x86', 'x64'):
    native = artifacts / f'windows-{architecture}'
    snapshot = (native / 'source.tar.gz').read_bytes()
    if source is not None and source != snapshot:
        raise SystemExit('Architecture source snapshots differ')
    source = snapshot

    name = f'arj-{VERSION}-windows-{architecture}'
    with zipfile.ZipFile(output / (name + '.zip'), 'w', zipfile.ZIP_DEFLATED) as archive:
        for member in MEMBERS:
            archive.write(native / member, name + '/' + member)

    packages = list((artifacts / f'msi-{architecture}').glob('*.msi'))
    if len(packages) != 1:
        raise SystemExit('Expected exactly one qualified MSI per architecture')
    shutil.copy2(packages[0], output / packages[0].name)

(output / f'arj-{VERSION}-source.tar.gz').write_bytes(source)
