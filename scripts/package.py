#!/usr/bin/env python3
"""Assemble Mica; use --identity for Developer ID signing, otherwise local ad-hoc."""
import argparse
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = '0.2.9'
BUILD = '11'
BUNDLE_ID = 'nl.martnr.mica'


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def identity(value):
    if not value:
        return '-'
    output = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    candidates = re.findall(r'\b([A-F0-9]{40}) "(Developer ID Application: [^"]+)"', output)
    matches = [(sha, name) for sha, name in candidates if value in (sha, name)]
    if len(matches) != 1:
        raise SystemExit('Specify one valid Developer ID Application identity name or SHA-1 from security find-identity -v -p codesigning.')
    return matches[0][0]


def write_plist(path, name, identifier, helper=False):
    info = dict(CFBundleExecutable=name, CFBundleName=name, CFBundleDisplayName=name,
                CFBundleIdentifier=identifier, CFBundleVersion=BUILD, CFBundleShortVersionString=VERSION,
                CFBundlePackageType='APPL', LSMinimumSystemVersion='13.0', NSHighResolutionCapable=True,
                NSPrincipalClass='NSApplication', NSHumanReadableCopyright='Mica. Chromium components are provided under their respective licenses.')
    if helper:
        info['LSUIElement'] = True
    else:
        updates = json.loads((ROOT / 'resources/updates.json').read_text())
        info.update(SUFeedURL=updates['feedURL'], SUPublicEDKey=updates['publicEDKey'],
                    SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True,
                    SUScheduledCheckInterval=3600, SUEnableSystemProfiling=False,
                    SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True,
                    SUSignedFeedFailureExpirationInterval=0)
        info['CFBundleURLTypes'] = [dict(CFBundleURLName='Web URLs', CFBundleTypeRole='Viewer', CFBundleURLSchemes=['http', 'https'])]
        info.update(CFBundleIconFile='Mica', NSCameraUsageDescription='Allow camera access to websites you choose.',
                    NSMicrophoneUsageDescription='Allow microphone access to websites you choose.')
    path.write_bytes(plistlib.dumps(info))


def assemble(app, signing_identity):
    contents = app / 'Contents'
    for directory in ('MacOS', 'Resources', 'Frameworks'):
        (contents / directory).mkdir(parents=True)
    shutil.copy2(ROOT / 'build/Mica', contents / 'MacOS/Mica')
    write_plist(contents / 'Info.plist', 'Mica', BUNDLE_ID)
    framework = contents / 'Frameworks/Chromium Embedded Framework.framework'
    shutil.copytree(ROOT / 'vendor/cef/Release' / framework.name, framework, symlinks=True)
    sparkle = contents / 'Frameworks/Sparkle.framework'
    shutil.copytree(ROOT / 'vendor/sparkle/Sparkle.framework', sparkle, symlinks=True)
    helpers = []
    for suffix, bundle_suffix, role in [('', '', 'helper'), (' (Alerts)', '.alerts', 'helper'), (' (GPU)', '.gpu', 'gpu'), (' (Plugin)', '.plugin', 'helper'), (' (Renderer)', '.renderer', 'renderer')]:
        name = 'Mica Helper' + suffix
        helper = contents / 'Frameworks' / (name + '.app')
        binary = helper / 'Contents/MacOS' / name
        binary.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'build/MicaHelper', binary)
        write_plist(helper / 'Contents/Info.plist', name, BUNDLE_ID + '.helper' + bundle_suffix, True)
        helpers.append((helper, role))
    for name in ('LICENSE.txt', 'CREDITS.html'):
        shutil.copy2(ROOT / 'vendor/cef' / name, contents / 'Resources' / name)
    shutil.copy2(ROOT / 'LICENSE', contents / 'Resources/LICENSE-Mica.txt')
    shutil.copy2(ROOT / 'vendor/sparkle/LICENSE', contents / 'Resources/LICENSE-Sparkle.txt')
    for name in ('shield-rules.json', 'LICENSE-Search.txt', 'devtools-host.js', 'Mica.icns'):
        shutil.copy2(ROOT / 'resources' / name, contents / 'Resources' / name)

    def sign(path, role=None):
        args = ['codesign', '--force', '--sign', signing_identity]
        if signing_identity != '-':
            args += ['--timestamp', '--options', 'runtime']
        if role:
            args += ['--entitlements', str(ROOT / 'resources/entitlements' / (role + '.plist'))]
        run(*args, path)

    # Sign nested Mach-O files with the same team before enclosing bundles.
    # Never use --deep for signing; reserve it for verification.
    for library in sorted(framework.rglob('*')):
        if library.is_symlink() or not library.is_file():
            continue
        with library.open('rb') as stream:
            magic = stream.read(4)
        if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            sign(library)
    sign(framework)
    # Retain Sparkle's sandbox entitlements on its XPC helpers while signing
    # everything with Mica's Developer ID for hardened-runtime validation.
    for nested in sorted(sparkle.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if nested.is_symlink():
            continue
        if nested.suffix in ('.xpc', '.app') or (nested.is_file() and nested.name == 'Autoupdate'):
            args = ['codesign', '--force', '--sign', signing_identity, '--preserve-metadata=entitlements']
            if signing_identity != '-':
                args += ['--timestamp', '--options', 'runtime']
            run(*args, nested)
    sign(sparkle)
    for helper, role in helpers:
        sign(helper, role)
    sign(app, 'app')
    run('codesign', '--verify', '--deep', '--strict', app)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    local_identity = ROOT / '.tools/signing-identity'
    default_identity = os.environ.get('MICA_SIGNING_IDENTITY') or (local_identity.read_text().strip() if local_identity.exists() else None)
    parser.add_argument('--identity', default=default_identity)
    parser.add_argument('--remember', action='store_true', help='Remember this public identity for subsequent local builds')
    parser.add_argument('--adhoc', action='store_true', help='Explicitly make an unsigned development build')
    args = parser.parse_args()
    selected = identity(None if args.adhoc else args.identity)
    if args.remember and selected == '-':
        parser.error('--remember requires a Developer ID Application identity')
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.mica-stage-', dir=dist) as directory:
        app = pathlib.Path(directory) / 'Mica.app'
        assemble(app, selected)
        target = dist / 'Mica.app'
        # Preserve the previous complete bundle while replacing the build.
        previous = dist / 'Mica.previous.app'
        if previous.exists():
            shutil.rmtree(previous)
        if target.exists():
            target.rename(previous)
        try:
            app.rename(target)
        except BaseException:
            if previous.exists():
                previous.rename(target)
            raise
    if args.remember:
        local_identity.parent.mkdir(exist_ok=True)
        local_identity.write_text(selected + '\n')
    print(f'{target} ({"local development" if selected == "-" else "Developer ID signed; notarization still required"})')


if __name__ == '__main__':
    main()
