#!/usr/bin/env python3
"""Exercise a real signed Sparkle replacement and Mica shutdown in an isolated copy."""
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / 'artifacts'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)
identity = (ROOT / '.tools/signing-identity').read_text().strip()
config = json.loads((ROOT / 'resources/updates.json').read_text())


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def sign(path):
    run('codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp',
        '--entitlements', ROOT / 'resources/entitlements/app.plist', path)


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_message(self, *_):
        pass


def main():
    checks = []
    ARTIFACTS.mkdir(exist_ok=True)
    (ARTIFACTS/'update-result.json').write_text(json.dumps({'passed': False, 'checks': []})+'\n')
    source_info = plistlib.loads((ROOT/'dist/Mica.app/Contents/Info.plist').read_bytes())
    target_build = source_info['CFBundleVersion']
    previous_build = str(int(target_build)-1)
    host_source = ROOT/'dist/Mica.app'
    previous_release = ROOT/'dist/Mica-notarized.app'
    previous_info = previous_release/'Contents/Info.plist'
    if previous_info.is_file() and plistlib.loads(previous_info.read_bytes())['CFBundleVersion'] == previous_build:
        host_source = previous_release
    identifier = 'nl.martnr.mica.update-test.' + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix='searchlight-smoke-update-') as directory:
        # Mica canonicalizes its profile path; use the same /private/var path
        # for its bundle so the native probe's isolation guard can match it.
        root = Path(directory).resolve()
        profile = root / 'profile'; profile.mkdir()
        web = root / 'web'; web.mkdir()
        (web / 'index.html').write_text('<title>Mica update fixture</title><h1>Update fixture</h1>')
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(web)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}'
        host = root / 'Mica.app'
        payload = root / 'payload'; payload.mkdir()
        target = payload / 'Mica.app'
        for app, build, source in [(host, previous_build, host_source), (target, target_build, ROOT/'dist/Mica.app')]:
            run('cp', '-cR', source, app)
            info_path = app / 'Contents/Info.plist'
            info = plistlib.loads(info_path.read_bytes())
            info.update(CFBundleIdentifier=identifier, CFBundleVersion=build,
                        CFBundleShortVersionString='0.0.'+build, SUDefaultsDomain=identifier,
                        SUFeedURL=url+'/appcast.xml', NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
            info_path.write_bytes(plistlib.dumps(info))
            sign(app)
        # Exercise the same disk-image extraction path used by public releases.
        archive = web / 'Mica-update.dmg'
        run('hdiutil', 'create', '-volname', 'Mica update fixture', '-srcfolder', payload,
            '-format', 'UDZO', archive)
        tool = ROOT / 'vendor/sparkle/bin/sign_update'
        args = [tool, '--account', config['keychainAccount']]
        signature = subprocess.check_output([*map(str, args), '-p', str(archive)], text=True).strip()
        rss = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(rss, 'channel')
        ET.SubElement(channel, 'title').text = 'Isolated update fixture'
        ET.SubElement(channel, f'{{{NS}}}bundleIdentifier').text = identifier
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = 'Update fixture'
        ET.SubElement(item, f'{{{NS}}}version').text = target_build
        ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '13.0'
        ET.SubElement(item, 'enclosure', {'url': url+'/'+archive.name, 'length': str(archive.stat().st_size),
                     'type': 'application/octet-stream', f'{{{NS}}}edSignature': signature})
        feed = web / 'appcast.xml'
        ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
        run(*args, feed)
        run(*args, '--verify', feed)
        bad = root / 'tampered.xml'; bad.write_bytes(feed.read_bytes().replace(b'Update fixture', b'Tampered fixture'))
        result = subprocess.run(list(map(str, [*args, '--verify', bad])), capture_output=True)
        assert result.returncode != 0, 'Tampered feed was accepted'
        checks.append('Signed update feed verifies and altered metadata is rejected')
        run(*args, '--verify', archive, signature)
        checks.append('Update archive Ed25519 signature verifies')
        space, tab = str(uuid.uuid4()), str(uuid.uuid4())
        session = {'version': 1, 'activeSpace': space, 'sidebarVisible': False, 'adblockEnabled': True,
                   'adblockPausedHosts': [], 'devToolsPosition': 'right', 'spaces': [
                       {'id': space, 'name': 'Update test', 'activeTab': tab, 'folders': [], 'tabs': [
                           {'id': tab, 'title': 'Saved pin', 'url': url+'/', 'pinned': True,
                            'pinURL': url+'/', 'pinTitle': 'Saved pin'}]}]}
        (profile / 'session.json').write_text(json.dumps(session))
        env = dict(os.environ, SEARCHLIGHT_PROFILE=str(profile), SEARCHLIGHT_TEST_MODE='1',
                   SEARCHLIGHT_SMOKE_URL=url+'/', SEARCHLIGHT_SMOKE_RESULT=str(root/'ordinary-result.json'))
        env.pop('MICA_PROFILE', None)
        for phase in ['install', 'verify']:
            env['SEARCHLIGHT_UPDATE_PROBE'] = phase
            with (ARTIFACTS / f'update-{phase}.log').open('w') as log:
                app = subprocess.Popen([str(host/'Contents/MacOS/Mica')], env=env, stdout=log, stderr=log)
                try:
                    code = app.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    app.terminate()
                    try: app.wait(timeout=5)
                    except subprocess.TimeoutExpired: app.kill(); app.wait()
                    raise AssertionError(f'Update {phase} timed out; see artifacts/update-{phase}.log')
            result_path = root/'update-result.json'
            assert result_path.is_file(), f'Update probe did not report a result; see artifacts/update-{phase}.log (exit {code})'
            result = json.loads(result_path.read_text())
            assert code == 0 and result['error'] == '', result
            if phase == 'install':
                assert result['stage'] == 'ready', result
                deadline = time.monotonic() + 60
                while time.monotonic() < deadline:
                    try:
                        if plistlib.loads((host/'Contents/Info.plist').read_bytes())['CFBundleVersion'] == target_build: break
                    except FileNotFoundError: pass
                    time.sleep(0.25)
                else: raise AssertionError('Sparkle did not replace the app after clean shutdown')
                run('codesign', '--verify', '--deep', '--strict', host)
                checks.append('Sparkle downloads, validates and replaces a real Mica bundle after graceful CEF shutdown')
            else:
                assert result['stage'] == 'relaunched' and result['version'] == target_build, result
                saved = json.loads((profile/'session.json').read_text())
                assert saved['activeSpace'] == space and saved['spaces'][0]['tabs'][0]['id'] == tab
                assert saved['spaces'][0]['tabs'][0]['pinURL'] == url+'/' and saved['devToolsPosition'] == 'right'
                assert saved['sidebarVisible'] is False
                checks.append('Updated Mica launches and preserves its space, pin, sidebar and DevTools settings')
        server.shutdown()
    # Only remove this test run's uniquely named preference and cache data.
    subprocess.run(['defaults', 'delete', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.rmtree(Path.home()/'Library/Caches'/identifier, ignore_errors=True)
    (ARTIFACTS/'update-result.json').write_text(json.dumps({'passed': True, 'checks': checks,
        'sourceBuild': previous_build, 'targetBuild': target_build, 'usedPreviousRelease': host_source == previous_release}, indent=2)+'\n')
    print(json.dumps({'passed': True, 'checks': checks}, indent=2))


if __name__ == '__main__':
    main()
