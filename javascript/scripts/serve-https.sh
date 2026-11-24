#!/bin/sh
# Serves the folder that holds this repo and the SDK checkouts at https://localhost:8443, so the demo's return URL
# (javascript/return.html) is https on the page's own origin and the Payment Web App popup closes itself on return.
# The certificate is self-signed for localhost and made once into javascript/.cert/ (gitignored); the browser asks you
# to trust it the first time. Only this Mac can connect.
# Usage: scripts/serve-https.sh [port]
set -eu
port=${1:-8443}
here=$(cd "$(dirname "$0")/.." && pwd) # javascript/
repo=$(dirname "$here")
root=$(dirname "$repo")
cert="$here/.cert"
if [ ! -f "$cert/localhost.pem" ]; then
  mkdir -p "$cert"
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost,IP:127.0.0.1 \
    -keyout "$cert/localhost-key.pem" -out "$cert/localhost.pem" 2>/dev/null
fi
echo "Open https://localhost:$port/$(basename "$repo")/javascript/"
exec python3 -I -c '
import functools, http.server, ssl, sys
root, port, cert = sys.argv[1], int(sys.argv[2]), sys.argv[3]
server = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(http.server.SimpleHTTPRequestHandler, directory=root))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert + "/localhost.pem", cert + "/localhost-key.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
' "$root" "$port" "$cert"
