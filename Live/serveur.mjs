// CNSNN Live : petit programme qui lit les commentaires publics du live TikTok et les passe au jeu.
// Il ne se connecte pas à ton compte (pas de mot de passe) et n'écrit jamais rien sur TikTok : il lit seulement.
// Bibliothèque non officielle : https://github.com/zerodytrash/TikTok-Live-Connector
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { exec } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { WebSocketServer } from 'ws';
import { TikTokLiveConnection, WebcastEvent, ControlEvent } from 'tiktok-live-connector';

const PORT = 4747;
const here = path.dirname(fileURLToPath(import.meta.url));
const page = readFileSync(path.join(here, 'jeu.html'));
let user = process.argv[2] || 'jeucnsnn';
let conn = null, retry = null, state = 'Pas encore connecté';
const clients = new Set();

const send = m => { const s = JSON.stringify(m); clients.forEach(c => c.readyState === 1 && c.send(s)); };
const setState = text => { state = text; console.log(new Date().toLocaleTimeString('fr-FR'), text); send({ type: 'state', text }); };

async function connect(u) {
  clearTimeout(retry);
  if (u) user = u.replace(/^@/, '').trim();
  if (conn) { try { conn.disconnect(); } catch {} conn = null; }
  const c = new TikTokLiveConnection(user, { processInitialData: false });
  conn = c;
  c.on(WebcastEvent.CHAT, d => {
    // Version 2.5 : le texte est dans « content » et le @pseudo dans « displayId » (anciennes versions : comment, uniqueId).
    const u = { uniqueId: d.user?.uniqueId || d.user?.displayId, nickname: d.user?.nickname };
    const text = d.content ?? d.comment ?? '';
    console.log(new Date().toLocaleTimeString('fr-FR'), `💬 ${u.nickname || u.uniqueId || '?'} : ${text}`);
    send({ type: 'chat', comment: text, user: u });
  });
  c.on(ControlEvent.DISCONNECTED, () => { if (conn !== c) return; setState(`Live de @${user} terminé ou coupé. Nouvel essai dans 20 s…`); retry = setTimeout(() => connect(), 20000); });
  c.on(WebcastEvent.STREAM_END, () => { if (conn !== c) return; setState(`Live de @${user} terminé.`); });
  setState(`Connexion au live de @${user}…`);
  try {
    await c.connect();
    if (conn === c) setState(`✅ Commentaires du live de @${user} reçus`);
  } catch (e) {
    if (conn !== c) return;
    console.log('   détail :', e?.name, e?.message);
    const offline = /offline|not live|UserOffline|Room ID/i.test(String(e?.name) + String(e?.message));
    setState(offline ? `En attente : @${user} n'est pas encore en live. Lance ton live, le jeu le trouvera tout seul (nouvel essai dans 20 s)…` : `Connexion impossible (${String(e?.message || e).slice(0, 120)}). Nouvel essai dans 20 s…`);
    retry = setTimeout(() => connect(), 20000);
  }
}

const server = http.createServer((req, res) => {
  if (req.url === '/' || req.url.startsWith('/?') || req.url.startsWith('/jeu')) { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); res.end(page); }
  else { res.writeHead(404); res.end(); }
});
const wss = new WebSocketServer({ server, path: '/ws' });
wss.on('connection', ws => {
  clients.add(ws); ws.send(JSON.stringify({ type: 'state', text: state }));
  ws.on('message', b => { try { const m = JSON.parse(b); if (m.type === 'connect' && m.user) connect(m.user); } catch {} });
  ws.on('close', () => clients.delete(ws));
});
server.listen(PORT, '127.0.0.1', () => {
  const url = `http://localhost:${PORT}`;
  console.log(`\n  CNSNN Live est lancé : ${url}\n  Laisse cette fenêtre ouverte pendant le live. Pour arrêter : ferme-la.\n`);
  // Ouvre la fenêtre des réglages ; le bouton « Ouvrir l'écran du jeu » ouvre ensuite la fenêtre verticale à filmer.
  if (!process.env.NO_OPEN) exec(process.platform === 'win32' ? `start "" "${url}"` : process.platform === 'darwin' ? `open ${url}` : `xdg-open ${url}`);
  connect();
});
