#!/usr/bin/env python3
"""Real CEF import test: synthetic Chrome profile only, no user data or accounts."""
import base64
import hashlib
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / 'artifacts'
ARTIFACT.mkdir(exist_ok=True)
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'<!doctype html><title>Import fixture</title>')
    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
with tempfile.TemporaryDirectory(prefix='searchlight-smoke-') as directory:
    root = pathlib.Path(directory).resolve()
    profile = root / 'profile'
    fixture = profile / 'import-fixture'
    fixture.mkdir(parents=True)
    # Public fixture identity only. No private key is persisted or used by Mica.
    key = subprocess.check_output(['openssl', 'genrsa', '1024'], stderr=subprocess.DEVNULL)
    public = subprocess.check_output(['openssl', 'rsa', '-pubout', '-outform', 'DER'], input=key, stderr=subprocess.DEVNULL)
    identifier = ''.join(chr(97 + int(c, 16)) for c in hashlib.sha256(public).hexdigest()[:32])
    manifest = dict(manifest_version=3, name='Mica import fixture', version='1.0', key=base64.b64encode(public).decode(), permissions=['storage'], background={'service_worker': 'background.js'}, action={'default_popup': 'verify.html'})
    (fixture / 'manifest.json').write_text(json.dumps(manifest))
    (fixture / 'background.js').write_text("chrome.runtime.onInstalled.addListener(async()=>{if((await chrome.storage.local.get('fixtureInitialized')).fixtureInitialized)return;await new Promise(r=>setTimeout(r,4000));for(const area of ['local','sync'])await chrome.storage[area].set({theme:'light',settings:{showBadge:true,keepDefault:17},destinationOnly:'keep-me'});await chrome.storage.local.set({fixtureInitialized:true});});")
    (fixture / 'verify.html').write_text('<!doctype html><title>Checking import</title><script src="verify.js"></script>')
    (fixture / 'verify.js').write_text("""(async()=>{
      const isolated=location.search.includes('isolated');
      if(location.search.includes('setup')){
        for(let i=0;i<100;i++){
          if((await chrome.storage.local.get('fixtureInitialized')).fixtureInitialized)break;
          await new Promise(r=>setTimeout(r,100));
        }
        for(const area of ['local','sync']){
          const data=await chrome.storage[area].get(null);
          if(data.theme!=='light'||data.fontSize!==undefined)throw Error('Settings applied before setup completed');
        }
        document.title='Setup verified';return;
      }
      for(const area of ['local','sync']){
        const data=await chrome.storage[area].get(null);
        if(isolated){if(data.theme==='dark'||data.fontSize!==undefined||data.settings?.showBadge===false)throw Error('Settings crossed spaces');continue;}
        if(data.theme!=='dark'||data.fontSize!==18||data.settings?.showBadge!==false)throw Error(area+' preferences missing');
        if(data.settings.keepDefault!==17||data.destinationOnly!=='keep-me')throw Error('Destination defaults overwritten');
        if(data.token||data.settings.account||data.settings.refreshToken)throw Error('Source account data copied');
      }
      document.title=isolated?'Isolation verified':'Import verified';
    })().catch(e=>document.title='Import failure:'+e.message);""")
    source = profile / 'chrome-source'
    chrome = source / 'Default'
    extension = chrome / 'Extensions' / identifier / '1.0_0'
    extension.mkdir(parents=True)
    (extension / 'manifest.json').write_text(json.dumps(manifest))
    (source / 'Local State').write_text(json.dumps({'profile': {'info_cache': {'Default': {'name': 'Test profile'}}}}))
    (chrome / 'Preferences').write_text(json.dumps({'profile': {'name': 'Test profile'}, 'extensions': {'settings': {identifier: {'path': f'{identifier}/1.0_0', 'from_webstore': True}}}}))
    for area in ['Local Extension Settings', 'Sync Extension Settings']:
        subprocess.run([str(ROOT / 'build/ExtensionImportTests'), '--seed', str(chrome / area / identifier)], check=True)
    before = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file()}
    result = root / 'result.json'
    env = dict(os.environ, SEARCHLIGHT_PROFILE=str(profile), SEARCHLIGHT_TEST_MODE='1', MICA_IMPORT_PROBE='1', MICA_IMPORT_FIXTURE_ID=identifier,
               SEARCHLIGHT_SMOKE_URL=f'http://127.0.0.1:{server.server_port}/', SEARCHLIGHT_SMOKE_RESULT=str(result), SEARCHLIGHT_SMOKE_SCREENSHOT=str(ARTIFACT / 'extension-import.png'))
    env.pop('MICA_PROFILE', None)
    for phase in ['initial', 'restore']:
        if phase == 'restore':
            env['MICA_IMPORT_RESTORE'] = '1'
        result.unlink(missing_ok=True)
        with (ARTIFACT / f'extension-import-{phase}.log').open('w') as log:
            app = subprocess.Popen([str(ROOT / 'dist/Mica.app/Contents/MacOS/Mica')], env=env, stdout=log, stderr=log)
            try:
                code = app.wait(timeout=75)
            except subprocess.TimeoutExpired:
                app.terminate()
                try:
                    app.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    app.kill(); app.wait()
                raise SystemExit('Import probe timed out; see artifacts/extension-import-initial.log')
        payload = json.loads(result.read_text()) if result.exists() else {'passed': False, 'error': 'No test result'}
        payload['exitCode'] = code
        (ARTIFACT / f'extension-import-{phase}-result.json').write_text(json.dumps(payload, indent=2))
        print(json.dumps(payload, indent=2), flush=True)
        if code or not payload['passed']:
            raise SystemExit(1)
    after = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file()}
    assert before == after, 'Source Chrome profile changed'
    queue = (profile / 'extension-imports.json').read_text()
    assert 'source-secret' not in queue and 'source-refresh' not in queue
server.shutdown()
