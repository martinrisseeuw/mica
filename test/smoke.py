#!/usr/bin/env python3
"""Launch the real app against a localhost fixture using a disposable profile."""
import argparse, http.server, json, os, pathlib, subprocess, tempfile, threading, struct, zlib, shutil
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--chrome-only', action='store_true', help='Run sidebar, address editor, appearance, and width restoration checks only')
options = parser.parse_args()
suite = 'chrome' if options.chrome_only else 'smoke'
ROOT = pathlib.Path(__file__).resolve().parents[1]
def png_chunk(kind, data):
    return struct.pack('!I', len(data))+kind+data+struct.pack('!I', zlib.crc32(kind+data))
ICON = b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('!2I5B', 16,16,8,2,0,0,0)) + png_chunk(b'IDAT',zlib.compress((b'\0'+b'\x42\xb8\x83'*16)*16)) + png_chunk(b'IEND',b'')
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/extension-package.crx'):
            body=b'Cr24'+b'\0'*12
            self.send_response(200);self.send_header('Content-Type','application/x-chrome-extension');self.send_header('Content-Disposition','attachment; filename="fixture.crx"');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
        if self.path.startswith('/favicon.png'):
            self.send_response(200); self.send_header('Content-Type','image/png'); self.send_header('Content-Length',str(len(ICON))); self.end_headers(); self.wfile.write(ICON); return
        if self.path.startswith('/disconnect'):
            self.connection.close()
            return
        title = 'Second page' if self.path.startswith('/second') else 'Searchlight fixture'
        if self.path.startswith('/set-cookie'):
            title = 'Cookie set'
        elif self.path.startswith('/check-cookie'):
            title = 'Cookie present' if 'space=development' in self.headers.get('Cookie', '') else 'Cookie absent'
        body = f'<!doctype html><title>{title}</title><link rel="icon" href="/favicon.png"><h1>{title}</h1><p>This fixture checks native Chromium browsing.</p><a href="/second">Next page</a><input placeholder="Type here">'.encode()
        if self.path.startswith('/shield'):
            body = f"""<!doctype html><title>Shield checking</title>
              <div class="ad-slot">Advertisement</div><div class="address">Useful content</div>
              <script>window.adResult='pending';</script>
              <script src="http://doubleclick.net:{self.server.server_port}/ad-script.js"
                onload="window.adResult='allowed'" onerror="window.adResult='blocked'"></script>
              <script>setInterval(()=>{{ document.title='Shield '+adResult+' '+
                (getComputedStyle(document.querySelector('.ad-slot')).display==='none'?'hidden':'visible')+' '+
                (getComputedStyle(document.querySelector('.address')).display!=='none'?'safe':'broken')+' '+
                (typeof __slSend==='undefined'?'isolated':'unsafe'); }},100);</script>""".encode()
        if self.path.startswith('/ad-script.js'):
            body = b'window.adScriptExecuted=true;'
        self.send_response(200)
        if self.path.startswith('/set-cookie'):
            self.send_header('Set-Cookie', 'space=development; Path=/; Max-Age=3600; SameSite=Lax')
        self.send_header('Content-Type', 'application/javascript' if self.path.startswith('/ad-script.js') else 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
with tempfile.TemporaryDirectory(prefix='searchlight-smoke-') as directory:
    root = pathlib.Path(directory)
    result = root / 'result.json'
    env = dict(os.environ, SEARCHLIGHT_PROFILE=str(root / 'profile'), SEARCHLIGHT_TEST_MODE='1',
               SEARCHLIGHT_SMOKE_URL=f'http://127.0.0.1:{server.server_port}/',
               SEARCHLIGHT_SMOKE_RESULT=str(result))
    artifact = ROOT / 'artifacts'
    artifact.mkdir(exist_ok=True)
    env['SEARCHLIGHT_SMOKE_SCREENSHOT'] = str(artifact / 'native-start-page.png')
    env.pop('MICA_PROFILE', None)  # The test must never inherit a real profile override.
    env['SEARCHLIGHT_SMOKE_CHROME_ONLY'] = '1' if options.chrome_only else '0'
    results = []
    for phase in ['initial', 'restore']:
        result.unlink(missing_ok=True)
        if phase == 'restore':
            env['SEARCHLIGHT_SMOKE_RESTORE'] = '1'
        with (artifact / f'{suite}-{phase}.log').open('w') as log:
            app = subprocess.Popen([str(ROOT / 'dist/Mica.app/Contents/MacOS/Mica')], env=env, stdout=log, stderr=log)
            try:
                code = app.wait(timeout=75)
            except subprocess.TimeoutExpired:
                app.terminate()
                try: app.wait(timeout=5)
                except subprocess.TimeoutExpired: app.kill(); app.wait()
                shutil.copy2(root / 'profile/chromium.log', artifact / f'{suite}-{phase}-chromium.log')
                raise SystemExit(f'Smoke test timed out; see artifacts/{suite}-{phase}.log')
        if not result.exists():
            raise SystemExit(f'App exited {code} without a smoke result; see artifacts/{suite}-{phase}.log')
        payload = json.loads(result.read_text())
        payload['exitCode'] = code
        payload['phase'] = phase
        results.append(payload)
        (artifact / f'{suite}-result.json').write_text(json.dumps(results, indent=2))
        print(json.dumps(payload, indent=2), flush=True)
        if not payload['passed'] or code:
            raise SystemExit(1)
server.shutdown()
