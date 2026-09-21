from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        return

    def send_json(self, payload: dict[str, object], status: int = 200) -> None:
        body = json.dumps(payload).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == '/api/tags':
            self.send_json({'models': [{'name': 'roblox-ai-studio:latest', 'model': 'roblox-ai-studio:latest'}]})
            return
        self.send_json({'error': 'not found'}, 404)

    def do_POST(self) -> None:  # noqa: N802
        if self.path != '/api/generate':
            self.send_json({'error': 'not found'}, 404)
            return
        length = int(self.headers.get('Content-Length', '0'))
        payload = json.loads(self.rfile.read(length).decode('utf-8'))
        if payload.get('model') != 'roblox-ai-studio':
            self.send_json({'error': 'unexpected model'}, 400)
            return
        if payload.get('stream') is not False or payload.get('think') is not False:
            self.send_json({'error': 'unsafe generation options'}, 400)
            return
        self.send_json({'model': 'roblox-ai-studio', 'response': 'IA_LOCALE_OK', 'done': True})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=11434)
    args = parser.parse_args()
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()


if __name__ == '__main__':
    main()
