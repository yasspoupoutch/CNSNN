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
  try { await call('GET', `${api}/sites/${site}`); return; } catch (error) { if (error.status !== 404) throw error; }
  try {
    await call('POST', `${api}/projects/${projectId}/sites?siteId=${site}`, {});
    console.log(`Site créé : ${site}`);
  } catch (error) {
    console.error('::error::Firebase Hosting n’est pas encore activé. Ouvrez la console Firebase > Hosting > Commencer, puis relancez.');
    throw error;
  }
}

const root = new URL('../hosting/', import.meta.url);
const fonts = new URL('../../App/Resources/Fonts/', import.meta.url);
const apk = process.argv[2];
const files = new Map();
for (const name of await readdir(root)) {
  let content = await readFile(new URL(name, root));
  if (name === 'index.html' && !apk) content = Buffer.from(content.toString('utf8').replace(/<!--ANDROID-->[\s\S]*<!--\/ANDROID-->\n?/, ''));
  files.set('/' + name, content);
}
for (const name of ['Fraunces-Black.ttf', 'InstrumentSerif-Italic.ttf']) files.set('/fonts/' + name, await readFile(new URL(name, fonts)));
if (apk) files.set('/cnsnn.apk', await readFile(apk));

await ensureWebApp();
await ensureSite();
const version = await call('POST', `${api}/sites/${site}/versions`, {
  config: {
    cleanUrls: true,
    trailingSlashBehavior: 'REMOVE',
    headers: [
      { glob: '**', headers: { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'strict-origin-when-cross-origin', 'X-Frame-Options': 'DENY' } },
      { glob: '/cnsnn.apk', headers: { 'Content-Type': 'application/vnd.android.package-archive', 'Cache-Control': 'no-cache' } },
      { glob: '/fonts/**', headers: { 'Cache-Control': 'public, max-age=31536000' } },
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
