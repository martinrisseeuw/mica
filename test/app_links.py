#!/usr/bin/env python3
"""Check external app links with real CEF navigation and a fake OS launcher."""
import argparse
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=pathlib.Path, default=ROOT / 'dist/Mica.app')
options = parser.parse_args()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/redirect'):
            self.send_response(302)
            self.send_header('Location', 'claude://login/callback?code=synthetic%2Bvalue&state=a%2Fb#done')
            self.end_headers()
            return
        body = f'''<!doctype html><title>App links fixture</title>
<a id="same" href="claude://login/callback?code=synthetic%2Bvalue&state=a%2Fb#done">Open app</a>
<a id="popup" target="_blank" href="claude://login/callback?code=synthetic%2Bvalue&state=a%2Fb#done">Open app in new window</a>
<button id="script" onclick="location.href=document.querySelector('#same').href">Open app with script</button>
<a id="missing" href="mica-unhandled-test://open">Missing app</a>
<a id="redirect" href="/redirect">Open through redirect</a>
<iframe id="frame" data-url="http://127.0.0.1:{frame_server.server_port}/frame" style="position:absolute;left:0;top:200px;width:400px;height:100px;border:0"></iframe>
<script>addEventListener('message',()=>document.title='Frame ready')</script>'''.encode()
        if self.path.startswith('/frame'):
            body = b'''<!doctype html><a target="_top" href="claude://open?synthetic-frame=1">Open from frame</a>
<script>parent.postMessage('ready','*')</script>'''
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


frame_server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=frame_server.serve_forever, daemon=True).start()
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
artifact = ROOT / 'artifacts'
artifact.mkdir(exist_ok=True)
try:
    with tempfile.TemporaryDirectory(prefix='searchlight-smoke-app-links-') as directory:
        root = pathlib.Path(directory)
        result = root / 'result.json'
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('MICA_', 'SEARCHLIGHT_'))}
        env.update(SEARCHLIGHT_PROFILE=str(root / 'profile'), SEARCHLIGHT_TEST_MODE='1',
                   SEARCHLIGHT_SMOKE_URL=f'http://127.0.0.1:{server.server_port}/?private=synthetic-page-token',
                   SEARCHLIGHT_SMOKE_RESULT=str(result), MICA_APP_LINKS_PROBE='1')
        with (artifact / 'app-links-smoke.log').open('w') as log:
            app = subprocess.Popen([str(options.app / 'Contents/MacOS/Mica')],
                                   env=env, stdout=log, stderr=log)
            try:
                code = app.wait(timeout=65)
            except subprocess.TimeoutExpired:
                app.terminate()
                try:
                    app.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    app.kill()
                    app.wait()
                raise SystemExit('App links test timed out; see artifacts/app-links-smoke.log')
        if not result.exists():
            raise SystemExit(f'App exited {code} without a result; see artifacts/app-links-smoke.log')
        payload = json.loads(result.read_text())
        payload['exitCode'] = code
        (artifact / 'app-links-smoke.json').write_text(json.dumps(payload, indent=2) + '\n')
        print(json.dumps(payload, indent=2))
        if code or not payload['passed']:
            raise SystemExit(1)
finally:
    server.shutdown()
    server.server_close()
    frame_server.shutdown()
    frame_server.server_close()
