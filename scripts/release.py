#!/usr/bin/env python3
"""Build a shareable Developer ID signed, notarized and stapled Mica DMG.

Credentials stay in a local notarytool Keychain profile. --preview creates an
explicitly unnotarized local disk image to inspect the packaging without them.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile

from package import ROOT, VERSION, BUILD, assemble, identity, run
from updates import write_feed


def notarize(path, profile, logs):
    result = subprocess.run(['xcrun', 'notarytool', 'submit', str(path),
                             '--keychain-profile', profile, '--wait', '--output-format', 'json'],
                            text=True, capture_output=True)
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise SystemExit('Notary submission failed: ' + result.stderr.strip())
    (logs / (path.name + '.notary.json')).write_text(json.dumps(response, indent=2) + '\n')
    if result.returncode or response.get('status') != 'Accepted':
        if response.get('id'):
            run('xcrun', 'notarytool', 'log', response['id'], '--keychain-profile', profile,
                logs / (path.name + '.notary-log.json'))
        raise SystemExit('Apple did not accept this build. See the notarization log; no release was published.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', help='Developer ID Application name or SHA-1')
    parser.add_argument('--notary-profile', help='Local notarytool Keychain profile')
    parser.add_argument('--preview', action='store_true', help='Create an unnotarized local preview only')
    parser.add_argument('--notes-file', type=pathlib.Path, help='Plain-text release notes to include in the signed update feed')
    args = parser.parse_args()
    if not args.preview and (not args.identity or not args.notary_profile):
        parser.error('Release requires --identity and --notary-profile. Use --preview for local packaging only.')
    selected = identity(args.identity)
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    logs = ROOT / 'artifacts/release'
    logs.mkdir(parents=True, exist_ok=True)
    name = f'Mica-{VERSION}-arm64' + ('-unnotarized' if args.preview else '')
    with tempfile.TemporaryDirectory(prefix='.mica-release-', dir=dist) as directory:
        staging = pathlib.Path(directory)
        payload = staging / 'payload'
        payload.mkdir()
        app = payload / 'Mica.app'
        assemble(app, selected)
        if not args.preview:
            archive = staging / 'Mica.zip'
            run('ditto', '-c', '-k', '--keepParent', app, archive)
            notarize(archive, args.notary_profile, logs)
            run('xcrun', 'stapler', 'staple', app)
            run('xcrun', 'stapler', 'validate', app)
            run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
        (payload / 'Applications').symlink_to('/Applications')
        (payload / 'Install Mica.txt').write_text(
            'Drag Mica into Applications. Requires Apple Silicon and macOS 13 or later.\n'
            'Install 1Password through Extensions in Mica. To connect the desktop app,\n'
            'add Mica in 1Password Settings > Browser after installation.\n' +
            ('\nLOCAL PREVIEW: this disk image is not notarized for distribution.\n' if args.preview else ''))
        image = staging / (name + '.dmg')
        run('hdiutil', 'create', '-volname', 'Mica', '-srcfolder', payload, '-format', 'UDZO', '-ov', image)
        run('hdiutil', 'verify', image)
        if not args.preview:
            run('codesign', '--force', '--sign', selected, '--timestamp', image)
            notarize(image, args.notary_profile, logs)
            run('xcrun', 'stapler', 'staple', image)
            run('xcrun', 'stapler', 'validate', image)
            run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', image)
        output = dist / image.name
        image.replace(output)
        checksum = hashlib.file_digest(output.open('rb'), 'sha256').hexdigest()
        output.with_suffix('.dmg.sha256').write_text(f'{checksum}  {output.name}\n')
        if not args.preview:
            installed = dist / 'Mica-notarized.app'
            if installed.exists():
                shutil.rmtree(installed)
            shutil.copytree(app, installed, symlinks=True)
            notes = args.notes_file.read_text() if args.notes_file else f'Mica {VERSION}: improvements and fixes.'
            feed = write_feed(output, VERSION, BUILD, notes, dist / 'updates' / VERSION / 'appcast.xml')
            print(feed)
        print(output)


if __name__ == '__main__':
    main()
