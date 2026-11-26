#!/usr/bin/env python3
"""Download the pinned official CEF distribution and a project-local CMake."""
import hashlib, pathlib, subprocess, sys, tarfile, urllib.request, venv
ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = 'cef_binary_158.0.6+g23f1736+chromium-158.0.8127.89_macosarm64_minimal.tar.bz2'
SHA1 = '63faae7ccd6a497430c06d26b17c4cac20dca387'
# Upstream publishes SHA-1 checksums over HTTPS; this verifies the pinned archive.
archive = ROOT / 'vendor' / NAME
cef = ROOT / 'vendor' / 'cef'
if not (cef / 'include' / 'cef_version.h').exists():
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        print('Downloading official CEF Apple Silicon distribution…', flush=True)
        urllib.request.urlretrieve('https://cef-builds.spotifycdn.com/' + urllib.parse.quote(NAME), archive)
    with archive.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha1').hexdigest()
    if actual != SHA1:
        raise SystemExit('CEF checksum mismatch; remove the downloaded archive and retry.')
    cef.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            parts = pathlib.PurePosixPath(member.name).parts
            if len(parts) < 2:
                continue
            member.name = str(pathlib.PurePosixPath(*parts[1:]))
            tar.extract(member, cef, filter='data')
python = ROOT / '.tools' / 'python'
if not (python / 'bin' / 'cmake').exists():
    venv.create(python, with_pip=True)
    subprocess.run([str(python / 'bin' / 'pip'), 'install', 'cmake==4.4.5'], check=True)
subprocess.run([sys.executable, str(ROOT / 'scripts/bootstrap_sparkle.py')], check=True)
subprocess.run([sys.executable, str(ROOT / 'scripts/bootstrap_import.py')], check=True)
print('Dependencies ready.')
