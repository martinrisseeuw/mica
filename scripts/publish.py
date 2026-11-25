#!/usr/bin/env python3
"""Publish only verified release assets to Mica's public update repository."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from package import ROOT, VERSION, BUILD
from updates import configuration, sparkle_tool, NS


def gh(*args):
    return subprocess.check_output(['gh', *map(str, args)], text=True).strip()


def verified_assets():
    config = configuration()
    directory = ROOT / 'dist/updates' / VERSION
    manifest = json.loads((directory/'release.json').read_text())
    archive = ROOT / 'dist' / f'Mica-{VERSION}-arm64.dmg'
    feed = directory/'appcast.xml'
    if manifest['version'] != VERSION or manifest['build'] != BUILD or manifest['repository'] != config['repository']:
        raise ValueError('Release manifest does not match the current version and repository')
    for path, key in [(archive, 'archiveSHA256'), (feed, 'feedSHA256')]:
        if path.is_symlink() or hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != manifest[key]:
            raise ValueError(f'Changed release artifact: {path.name}')
    checksum = archive.with_suffix('.dmg.sha256')
    if checksum.read_text().split()[0] != manifest['archiveSHA256']:
        raise ValueError('Installer checksum file does not match')
    item = ET.parse(feed).getroot().find('channel/item')
    enclosure = item.find('enclosure')
    expected = f'https://github.com/{config["repository"]}/releases/download/v{VERSION}/{archive.name}'
    if item.findtext(f'{{{NS}}}version') != BUILD or enclosure.attrib['url'] != expected or int(enclosure.attrib['length']) != archive.stat().st_size:
        raise ValueError('Feed version, download URL or length does not match the installer')
    account = config['keychainAccount']
    sparkle_tool('sign_update', '--account', account, '--verify', feed)
    sparkle_tool('sign_update', '--account', account, '--verify', archive, enclosure.attrib[f'{{{NS}}}edSignature'])
    subprocess.run(['xcrun', 'stapler', 'validate', str(archive)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', str(archive)], check=True)
    return config, [archive, checksum, feed]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create-repository', action='store_true', help='Create the public binary-only repository if it does not exist')
    parser.add_argument('--publish', action='store_true', help='Publish after uploading; otherwise leave a draft')
    parser.add_argument('--notes-file', type=Path, required=True)
    args = parser.parse_args()
    config, assets = verified_assets()
    repo = config['repository']
    lookup = subprocess.run(['gh', 'api', f'repos/{repo}'], text=True, capture_output=True)
    if lookup.returncode:
        if not args.create_repository or '404' not in lookup.stderr:
            raise SystemExit('Release repository is unavailable; no assets were uploaded.')
        gh('repo', 'create', repo, '--public', '--description', 'Signed Mica browser downloads and automatic update feed')
        body = {'message': 'docs: add Mica download instructions',
                'content': base64.b64encode((ROOT/'resources/distribution/README.md').read_bytes()).decode()}
        with tempfile.NamedTemporaryFile('w', suffix='.json') as file:
            json.dump(body, file); file.flush()
            gh('api', '--method', 'PUT', f'repos/{repo}/contents/README.md', '--input', file.name)
    elif json.loads(lookup.stdout)['visibility'] != 'public':
        raise SystemExit('Refusing to change the visibility of an existing repository.')
    tag = 'v'+VERSION
    exists = subprocess.run(['gh', 'release', 'view', tag, '--repo', repo, '--json', 'isDraft'], text=True, capture_output=True)
    if exists.returncode == 0:
        if not json.loads(exists.stdout)['isDraft']:
            raise SystemExit('This version is already published; create a new version instead of changing its signed assets.')
    else:
        gh('release', 'create', tag, '--repo', repo, '--draft', '--title', f'Mica {VERSION}', '--notes-file', args.notes_file)
    gh('release', 'upload', tag, '--repo', repo, '--clobber', *assets)
    # GitHub does not create a draft's new tag until publication, so the
    # /releases/tags endpoint can return 404 even after a successful upload.
    pages = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'))
    matching = [release for page in pages for release in page if release['tag_name'] == tag]
    if len(matching) != 1 or not matching[0]['draft']:
        raise SystemExit('Could not uniquely verify the draft release; nothing was published.')
    remote = matching[0]
    uploaded = {entry['name']: entry for entry in remote['assets']}
    if set(uploaded) != {path.name for path in assets}:
        raise SystemExit('Unexpected release assets; the release remains a draft.')
    for path in assets:
        digest = 'sha256:'+hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
        if uploaded[path.name]['size'] != path.stat().st_size or uploaded[path.name].get('digest') != digest:
            raise SystemExit('GitHub asset verification failed; the release remains a draft.')
    if args.publish:
        gh('release', 'edit', tag, '--repo', repo, '--draft=false', '--latest')
        remote = json.loads(gh('api', f'repos/{repo}/releases/{remote["id"]}'))
        if remote['draft']:
            raise SystemExit('GitHub still reports this release as a draft.')
    print(remote['html_url'])


if __name__ == '__main__':
    main()
