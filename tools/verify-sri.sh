#!/usr/bin/env bash
# Re-downloads each pinned CDN script and checks it against the integrity="sha384-..." attribute in public/index.html.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
grep -o '<script src="https://[^"]*" integrity="sha384-[^"]*"' public/index.html | while read -r line; do
  url=$(echo "$line" | sed -E 's/.*src="([^"]*)".*/\1/')
  want=$(echo "$line" | sed -E 's/.*integrity="sha384-([^"]*)".*/\1/')
  got=$(curl -fsSL "$url" | openssl dgst -sha384 -binary | openssl base64 -A)
  if [ "$want" = "$got" ]; then echo "OK    $url"; else echo "MISMATCH $url"; exit 1; fi
done
