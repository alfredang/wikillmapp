#!/bin/sh
# Serve the library root read-only on a free local port, so pages can be opened in the Playwright
# browser to check that their visuals render. Prints the base URL; stop it with: kill <pid>.
# Usage (from anywhere): sh .claude/skills/rich-visuals/serve.sh
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT" >/dev/null 2>&1 &
echo "pid $! — open http://127.0.0.1:$PORT/<page path with spaces as %20>"
