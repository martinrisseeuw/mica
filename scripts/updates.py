#!/usr/bin/env python3
"""Create and verify the signed Sparkle feed for a completed Mica release."""
import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def configuration():
    config = json.loads((ROOT / 'resources/updates.json').read_text())
    repo = config['repository']
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repo):
        raise ValueError('Invalid update repository')
    if config['feedURL'] != f'https://github.com/{repo}/releases/latest/download/appcast.xml':
        raise ValueError('Update feed must use the configured HTTPS release repository')
    if len(base64.b64decode(config['publicEDKey'], validate=True)) != 32:
        raise ValueError('Invalid Ed25519 public key')
    return config


def sparkle_tool(name, *args):
    return subprocess.check_output([str(ROOT / 'vendor/sparkle/bin' / name), *map(str, args)], text=True).strip()


def write_feed(archive, version, build, notes, output):
    config = configuration()
    account = config['keychainAccount']
    if sparkle_tool('generate_keys', '--account', account, '-p') != config['publicEDKey']:
        raise ValueError('Signing key does not match the public key embedded in Mica')
    signature = sparkle_tool('sign_update', '--account', account, '-p', archive)
    sparkle_tool('sign_update', '--account', account, '--verify', archive, signature)
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Mica updates'
    ET.SubElement(channel, 'link').text = f'https://github.com/{config["repository"]}/releases'
    ET.SubElement(channel, 'description').text = 'Signed updates for Mica for macOS.'
    ET.SubElement(channel, f'{{{NS}}}bundleIdentifier').text = 'nl.martnr.mica'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Mica {version}'
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    ET.SubElement(item, f'{{{NS}}}version').text = str(build)
    ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '13.0'
    ET.SubElement(item, 'description').text = notes
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{config["repository"]}/releases/download/v{version}/{archive.name}',
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{NS}}}edSignature': signature,
    })
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(rss)
    ET.ElementTree(rss).write(output, encoding='utf-8', xml_declaration=True)
    sparkle_tool('sign_update', '--account', account, output)
    sparkle_tool('sign_update', '--account', account, '--verify', output)
    manifest = {
        'version': version, 'build': str(build), 'repository': config['repository'],
        'archive': str(archive.relative_to(ROOT)),
        'archiveSHA256': hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest(),
        'feedSHA256': hashlib.file_digest(output.open('rb'), 'sha256').hexdigest(),
    }
    output.with_name('release.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return output
