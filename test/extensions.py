#!/usr/bin/env python3
"""Opt-in official extension smoke test, isolated profile, no account sign-in.
Download the official CRX to .tools/1password-probe.crx before running.
The CRX is test input only and is never redistributed in the app.
"""
import base64, hashlib, http.server, io, json, os, pathlib, shutil, struct, subprocess, tempfile, threading, zipfile, zlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
raw=(ROOT/'.tools/1password-probe.crx').read_bytes()
assert raw[:4]==b'Cr24' and struct.unpack('<I',raw[4:8])[0]==3
def varint(data,pos):
    value=shift=0
    while True:
        byte=data[pos];pos+=1;value|=(byte&127)<<shift;shift+=7
        if not byte&128:return value,pos

def fields(data):
    pos=0
    while pos<len(data):
        tag,pos=varint(data,pos);size,pos=varint(data,pos)
        if tag&7==2:yield tag>>3,data[pos:pos+size];pos+=size
        elif tag&7==0:yield tag>>3,size
        else:raise ValueError('Unsupported CRX field')

public_key=None
for field,proof in fields(raw[12:12+struct.unpack('<I',raw[8:12])[0]]):
    if field in (2,3):
        key=dict(fields(proof))[1]
        extension_id=''.join(chr(97+int(n,16)) for n in hashlib.sha256(key).hexdigest()[:32])
        if extension_id=='aeblfdkhhhdcdjpifhhbdiojplfjncoa':public_key=base64.b64encode(key).decode()
assert public_key, 'Official extension identity missing from CRX'
archive=zipfile.ZipFile(io.BytesIO(raw[12+struct.unpack('<I',raw[8:12])[0]:]))
assert all(not n.startswith('/') and '..' not in pathlib.Path(n).parts for n in archive.namelist())
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200);self.end_headers();self.wfile.write(b'<!doctype html><title>Extension fixture</title><input type="password">')
    def log_message(self,*_):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
with tempfile.TemporaryDirectory(prefix='searchlight-smoke-') as directory:
    root=pathlib.Path(directory); profile=root/'profile'; fixture=profile/'extension-fixture';fixture.mkdir(parents=True)
    archive.extractall(fixture)
    # Keep the signed package identity when loading its files as a test fixture.
    manifest=json.loads((fixture/'manifest.json').read_text());manifest['key']=public_key
    (fixture/'manifest.json').write_text(json.dumps(manifest))
    popup=profile/'popup-fixture';popup.mkdir()
    (popup/'manifest.json').write_text(json.dumps({'manifest_version':3,'name':'Mica popup fixture','version':'1.0','permissions':['activeTab','scripting'],'action':{'default_popup':'popup.html','default_icon':{'38':'action.png'}}}))
    def png_chunk(kind,data):return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data))
    (popup/'action.png').write_bytes(b'\x89PNG\r\n\x1a\n'+png_chunk(b'IHDR',struct.pack('!2I5B',38,38,8,2,0,0,0))+png_chunk(b'IDAT',zlib.compress((b'\0'+b'\x42\xb8\x83'*38)*38))+png_chunk(b'IEND',b''))
    (popup/'popup.html').write_text('<!doctype html><title>Mica popup fixture</title><p>Native extension popup</p><script src="popup.js"></script>')
    (popup/'popup.js').write_text("chrome.tabs.query({active:true,currentWindow:true},async tabs=>{try{const r=await chrome.scripting.executeScript({target:{tabId:tabs[0].id},func:()=>document.title});document.body.append(' Active tab verified:'+r[0].result)}catch(e){document.body.append(' Action error:'+e.message)}})")
    result=root/'result.json';artifact=ROOT/'artifacts';artifact.mkdir(exist_ok=True)
    env=dict(os.environ,SEARCHLIGHT_PROFILE=str(profile),SEARCHLIGHT_TEST_MODE='1',SEARCHLIGHT_EXTENSION_PROBE='1',SEARCHLIGHT_SMOKE_URL=f'http://127.0.0.1:{server.server_port}/',SEARCHLIGHT_SMOKE_RESULT=str(result),SEARCHLIGHT_SMOKE_SCREENSHOT=str(artifact/'extension-main.png'))
    env.pop('MICA_PROFILE', None)  # The test must never inherit a real profile override.
    for phase in ['probe','restore']:
        result.unlink(missing_ok=True)
        if phase=='restore':env['MICA_EXTENSION_RESTORE']='1'
        with (artifact/f'extension-{phase}.log').open('w') as log:
            app=subprocess.Popen([str(ROOT/'dist/Mica.app/Contents/MacOS/Mica')],env=env,stdout=log,stderr=log)
            try: code=app.wait(timeout=75)
            except subprocess.TimeoutExpired:
                app.terminate()
                try:app.wait(timeout=5)
                except subprocess.TimeoutExpired:app.kill();app.wait()
                raise SystemExit('Extension test timed out; see artifacts/extension-probe.log')
        payload=json.loads(result.read_text()) if result.exists() else {'passed':False,'error':'No result; see extension-probe.log'}
        if (profile/'chromium.log').exists():shutil.copy2(profile/'chromium.log',artifact/'extension-chromium.log')
        payload['exitCode']=code
        (artifact/('extension-result.json' if phase=='probe' else 'extension-restore-result.json')).write_text(json.dumps(payload,indent=2));print(json.dumps(payload,indent=2))
        if not payload['passed'] or code:raise SystemExit(1)
server.shutdown()
