#!/usr/bin/env python3
"""Fetch the pinned, checksum-verified official Sparkle distribution."""
import hashlib
import pathlib
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = '2.10.1'
SHA256 = '1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27'


def main():
    archive = ROOT / 'vendor' / f'Sparkle-{VERSION}.tar.xz'
    archive.parent.mkdir(exist_ok=True)
    if not archive.exists():
        url = f'https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/{archive.name}'
        subprocess.run(['/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--tlsv1.2', '--output', str(archive), url], check=True)
    if hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest() != SHA256:
        raise SystemExit('Sparkle checksum mismatch; remove the archive and retry.')
    target = ROOT / 'vendor' / 'sparkle'
    target.mkdir(exist_ok=True)
    with tarfile.open(archive) as source:
        source.extractall(target, filter='data')
    print(f'Sparkle {VERSION} ready in {target}')


if __name__ == '__main__':
    main()
