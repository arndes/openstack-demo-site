#!/usr/bin/env bash
set -euo pipefail

PORT=${PORT:-8080}

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  echo "Server stopped."
}
trap cleanup EXIT INT TERM

python3 - <<EOF &
import http.server, json, os

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory='web', **kw)
    def do_GET(self):
        if self.path == '/info':
            body = json.dumps({
                'client_ip':   self.client_address[0],
                'server_addr': '127.0.0.1',
                'server_port': '$PORT',
                'hostname':    os.uname().nodename,
                'request_uri': self.path
            }).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(body))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()
    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} {fmt % args}")

http.server.HTTPServer(('', $PORT), H).serve_forever()
EOF

SERVER_PID=$!
echo "Preview server running at http://localhost:$PORT  (Ctrl+C to stop)"
xdg-open "http://localhost:$PORT" 2>/dev/null || true

wait "$SERVER_PID"
