#!/usr/bin/env python3
"""Check Find through native key events in an isolated Mica profile."""
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
        body = b'<!doctype html><title>Find fixture</title><p>m</p><p>m</p><p>m</p><input placeholder="Type here">'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
artifact = ROOT / 'artifacts'
artifact.mkdir(exist_ok=True)
try:
    with tempfile.TemporaryDirectory(prefix='searchlight-smoke-find-') as directory:
        root = pathlib.Path(directory)
        result = root / 'result.json'
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('MICA_', 'SEARCHLIGHT_'))}
        env.update(SEARCHLIGHT_PROFILE=str(root / 'profile'), SEARCHLIGHT_TEST_MODE='1',
                   SEARCHLIGHT_SMOKE_URL=f'http://127.0.0.1:{server.server_port}/',
                   SEARCHLIGHT_SMOKE_RESULT=str(result), MICA_FIND_PROBE='1')
        with (artifact / 'find-smoke.log').open('w') as log:
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
                raise SystemExit('Find test timed out; see artifacts/find-smoke.log')
        if not result.exists():
            raise SystemExit(f'App exited {code} without a result; see artifacts/find-smoke.log')
        payload = json.loads(result.read_text())
        payload['exitCode'] = code
        (artifact / 'find-smoke.json').write_text(json.dumps(payload, indent=2) + '\n')
        print(json.dumps(payload, indent=2))
        if code or not payload['passed']:
            raise SystemExit(1)
finally:
    server.shutdown()
    server.server_close()
