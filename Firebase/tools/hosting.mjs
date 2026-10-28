// Publishes the public site (Firebase/hosting) to Firebase Hosting, free plan, with the REST API:
// like tools/deploy.mjs, it does not need the permissions `firebase deploy` asks for.
// Needs GOOGLE_APPLICATION_CREDENTIALS. The site is https://cnsnn-9ctosy.web.app.
//
//   node tools/hosting.mjs [path/to/cnsnn.apk]
//
// The fonts come from the app (App/Resources/Fonts). Without an APK, the Android download block is left out.
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { applicationDefault } from 'firebase-admin/app';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { decrypt } from './daily.mjs';

const projectId = 'cnsnn-9ctosy';
const site = projectId;
const api = 'https://firebasehosting.googleapis.com/v1beta1';
const { access_token: token } = await applicationDefault().getAccessToken();
const auth = { Authorization: `Bearer ${token}` };

async function call(method, url, body, headers = {}) {
  const response = await fetch(url, { method, headers: { ...auth, ...(body && !(body instanceof Buffer) ? { 'Content-Type': 'application/json' } : {}), ...headers }, body: body instanceof Buffer ? body : body && JSON.stringify(body) });
  const text = await response.text();
  if (!response.ok) throw Object.assign(new Error(`${method} ${url} : ${response.status} ${text}`), { status: response.status });
  return text ? JSON.parse(text) : {};
}

// A web app gives the site its public configuration (/__/firebase/init.json), used by the deletion page.
async function ensureWebApp() {
  const { apps = [] } = await call('GET', `https://firebase.googleapis.com/v1beta1/projects/${projectId}/webApps`);
  if (apps.length) { console.log(`Application web déjà enregistrée : ${apps[0].appId}`); return; }
  let operation = await call('POST', `https://firebase.googleapis.com/v1beta1/projects/${projectId}/webApps`, { displayName: 'CNSNN site' });
  for (let i = 0; i < 20 && !operation.done; i++) {
    await new Promise((r) => setTimeout(r, 1500));
    operation = await call('GET', `https://firebase.googleapis.com/v1beta1/${operation.name}`);
  }
  console.log('Application web enregistrée.');
}

async function ensureSite() {
  try { await call('GET', `${api}/projects/${projectId}/sites/${site}`); return; } catch (error) { if (error.status !== 404) throw error; }
  try {
    await call('POST', `${api}/projects/${projectId}/sites?siteId=${site}`, {});
    console.log(`Site créé : ${site}`);
  } catch (error) {
    if (error.status === 409) return; // The site exists already.
    console.error('::error::Firebase Hosting n’est pas encore activé. Ouvrez la console Firebase > Hosting > Commencer, puis relancez.');
    throw error;
  }
}

const root = new URL('../hosting/', import.meta.url);
const fonts = new URL('../../App/Resources/Fonts/', import.meta.url);
const apk = process.argv[2];
const files = new Map();
// Android App Links: a challenge link (/d/CODE) opens the app directly once Android has checked this
// file, which names the app and the certificate it is signed with. The release key lives in the
// repository only encrypted (Android/signing); its fingerprint is read here. When Google Play signs
// the app (Play App Signing), add the fingerprint it shows in the Play Console to this list.
const playSigningSha256 = [];
function releaseSha256() {
  const credentials = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentials) return [];
  const dir = mkdtempSync(join(tmpdir(), 'cnsnn-'));
  try {
    const { private_key: privateKey } = JSON.parse(readFileSync(credentials, 'utf8'));
    const box = JSON.parse(readFileSync(new URL('../../Android/signing/release.enc.json', import.meta.url), 'utf8'));
    const [{ keystore, password }] = decrypt(box, privateKey);
    const file = join(dir, 'release.p12');
    writeFileSync(file, Buffer.from(keystore, 'base64'), { mode: 0o600 });
    const listing = execFileSync('keytool', ['-list', '-v', '-keystore', file, '-storetype', 'PKCS12', '-alias', 'cnsnn', '-storepass:env', 'CNSNN_STOREPASS'],
      { env: { ...process.env, CNSNN_STOREPASS: password, LC_ALL: 'C' } }).toString();
    const sha = listing.match(/SHA256:\s*([0-9A-F:]{95})/)?.[1];
    if (!sha) throw new Error('Empreinte SHA-256 introuvable');
    return [sha];
  } catch (error) {
    console.log(`::warning::Clé Android illisible (${error.message}) : les liens de défi ouvriront la page web au lieu de l’app.`);
    return [];
  } finally { rmSync(dir, { recursive: true, force: true }); }
}
const fingerprints = [...releaseSha256(), ...playSigningSha256];
const assetLinks = [{
  relation: ['delegate_permission/common.handle_all_urls'],
  target: { namespace: 'android_app', package_name: 'com.poupoutch.cnsnn', sha256_cert_fingerprints: fingerprints },
}];
// iOS universal links: same idea for the iPhone app, which lists this site in its Associated Domains
// entitlement (App/CNSNN.entitlements). Apple reads this file when the app is installed. The team
// id comes from the APPLE_TEAM_ID secret; without it the link keeps opening the web page.
const teamId = (process.env.APPLE_TEAM_ID || '').trim();
const appSiteAssociation = { applinks: { details: [{ appIDs: [`${teamId}.com.poupoutch.cnsnn`], components: [{ '/': '/d/*' }] }] } };
if (!teamId) console.log('::warning::APPLE_TEAM_ID absent : sur iPhone, les liens de défi ouvriront la page web au lieu de l’app.');

for (const name of await readdir(root)) {
  let content = await readFile(new URL(name, root));
  if (name === 'index.html' && !apk) content = Buffer.from(content.toString('utf8').replace(/<!--ANDROID-->[\s\S]*<!--\/ANDROID-->\n?/, ''));
  files.set('/' + name, content);
}
for (const name of ['Fraunces-Black.ttf', 'InstrumentSerif-Italic.ttf']) files.set('/fonts/' + name, await readFile(new URL(name, fonts)));
if (apk) files.set('/cnsnn.apk', await readFile(apk));
if (fingerprints.length) files.set('/.well-known/assetlinks.json', Buffer.from(JSON.stringify(assetLinks, null, 1) + '\n'));
if (teamId) files.set('/.well-known/apple-app-site-association', Buffer.from(JSON.stringify(appSiteAssociation, null, 1) + '\n'));

await ensureWebApp();
await ensureSite();
const version = await call('POST', `${api}/sites/${site}/versions`, {
  config: {
    cleanUrls: true,
    trailingSlashBehavior: 'REMOVE',
    // Challenge links: one page reads the code from the address.
    rewrites: [{ glob: '/d/**', path: '/defi.html' }],
    headers: [
      { glob: '**', headers: { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'strict-origin-when-cross-origin', 'X-Frame-Options': 'DENY' } },
      { glob: '/cnsnn.apk', headers: { 'Content-Type': 'application/vnd.android.package-archive', 'Cache-Control': 'no-cache' } },
      { glob: '/fonts/**', headers: { 'Cache-Control': 'public, max-age=31536000' } },
      { glob: '/.well-known/assetlinks.json', headers: { 'Content-Type': 'application/json' } },
      { glob: '/.well-known/apple-app-site-association', headers: { 'Content-Type': 'application/json' } },
    ],
  },
});
const gz = new Map([...files].map(([path, content]) => [path, gzipSync(content, { level: 9 })]));
const hashes = Object.fromEntries([...gz].map(([path, data]) => [path, createHash('sha256').update(data).digest('hex')]));
const { uploadUrl, uploadRequiredHashes = [] } = await call('POST', `https://firebasehosting.googleapis.com/v1beta1/${version.name}:populateFiles`, { files: hashes });
for (const [path, data] of gz) {
  if (uploadRequiredHashes.includes(hashes[path])) await call('POST', `${uploadUrl}/${hashes[path]}`, data, { 'Content-Type': 'application/octet-stream' });
}
await call('PATCH', `https://firebasehosting.googleapis.com/v1beta1/${version.name}?update_mask=status`, { status: 'FINALIZED' });
await call('POST', `${api}/sites/${site}/releases?versionName=${encodeURIComponent(version.name)}`, {});
console.log(`Site publié (${files.size} fichiers${apk ? ', avec l’APK Android' : ''}) : https://${site}.web.app`);
