#!/usr/bin/env bash
# Fabrique CNSNN-Live-Windows.zip : rien à installer, on dézippe et on double-clique « Lancer CNSNN Live.bat ».
# Contient node.exe officiel (nodejs.org), le programme en un seul fichier et la page du jeu.
set -euo pipefail
cd "$(dirname "$0")"
NODE=v22.21.1
OUT=dist/CNSNN-Live
rm -rf "$OUT" && mkdir -p "$OUT"
npm install --ignore-scripts --no-audit --no-fund >/dev/null
node build.mjs
npx -y esbuild@0.24.0 serveur.mjs --bundle --platform=node --format=esm --target=node22 --log-level=warning \
  --banner:js="import { createRequire as __cr } from 'module'; const require = __cr(import.meta.url);" --outfile="$OUT/serveur.mjs"
cp dist/jeu.html "$OUT/"
tmp=$(mktemp -d)
curl -fsSL "https://nodejs.org/dist/$NODE/node-$NODE-win-x64.zip" -o "$tmp/node.zip"
curl -fsSL "https://nodejs.org/dist/$NODE/SHASUMS256.txt" | grep " node-$NODE-win-x64.zip\$" | awk '{print $1"  '"$tmp"'/node.zip"}' | sha256sum -c -
unzip -q -j "$tmp/node.zip" "node-$NODE-win-x64/node.exe" -d "$OUT"
printf '@echo off\r\ntitle CNSNN Live\r\ncd /d "%%~dp0"\r\nnode.exe serveur.mjs\r\npause\r\n' > "$OUT/Lancer CNSNN Live.bat"
cp LISEZMOI.txt "$OUT/"
(cd dist && rm -f CNSNN-Live-Windows.zip && zip -qr CNSNN-Live-Windows.zip CNSNN-Live)
ls -la dist/CNSNN-Live-Windows.zip
