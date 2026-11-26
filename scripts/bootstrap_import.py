#!/usr/bin/env python3
"""Fetch the pinned, checksum-verified native extension-settings readers."""
import hashlib
import pathlib
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEPENDENCIES = (
    ('leveldb', '1.23', '9a37f8a6174f09bd622bc723b55881dc541cd50747cbd08831c2a82d620f6d76'),
    ('snappy', '1.2.2', '90f74bc1fbf78a6c56b3c4a082a05103b3a56bb17bca1a27e052ea11723292dc'),
)
for name, version, checksum in DEPENDENCIES:
    destination = ROOT / 'vendor' / f'{name}-{version}'
    if (destination / '.mica-verified').exists():
        continue
    archive = ROOT / 'vendor' / f'{name}.tar.gz'
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        subprocess.run(['curl', '--fail', '--location', '--max-time', '120',
                        f'https://codeload.github.com/google/{name}/tar.gz/refs/tags/{version}',
                        '--output', str(archive)], check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
        raise SystemExit(f'{name} checksum mismatch; remove {archive} and retry.')
    with tarfile.open(archive) as source:
        source.extractall(ROOT / 'vendor', filter='data')
    (destination / '.mica-verified').write_text(checksum + '\n')
