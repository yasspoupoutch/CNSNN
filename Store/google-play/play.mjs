// Google Play Developer API, with the project's service account (GOOGLE_APPLICATION_CREDENTIALS).
//   node play.mjs verifier             access check: account, API, app
//   node play.mjs fiche <captures>     texts, icon, banner and phone screenshots of the fr-FR listing
//   node play.mjs test-ferme <aab>     the AAB as a draft release of the closed test (track "alpha")
// No dependency: Node 22 (fetch, crypto). Nothing is printed from the key.
import { createSign } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const pkg = 'com.poupoutch.cnsnn';
const api = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}`;
const upload = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${pkg}`;
const listing = JSON.parse(readFileSync(join(here, 'listing-fr.json'), 'utf8'));
const account = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));

const b64 = (data) => Buffer.from(data).toString('base64url');

async function token() {
  const now = Math.floor(Date.now() / 1000);
  const claims = { iss: account.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: account.token_uri, iat: now, exp: now + 3600 };
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify(claims))}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(account.private_key, 'base64url');
  const res = await fetch(account.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
  });
  if (!res.ok) throw new Error(`Jeton refusé (${res.status})`);
  return (await res.json()).access_token;
}

const auth = { Authorization: `Bearer ${await token()}` };

async function call(method, url, body, type = 'application/json') {
  let res, text;
  // Google Play answers 503 now and then: try again a few times before giving up.
  for (let attempt = 1; ; attempt++) {
    res = await fetch(url, {
      method,
      headers: { ...auth, ...(body === undefined ? {} : { 'Content-Type': type }) },
      body: body === undefined ? undefined : type === 'application/json' ? JSON.stringify(body) : body,
    });
    text = await res.text();
    if (res.status < 500 || attempt === 4) break;
    console.log(`${method} : ${res.status}, nouvel essai dans ${attempt * 10} s`);
    await new Promise((r) => setTimeout(r, attempt * 10_000));
  }
  if (!res.ok) throw Object.assign(new Error(`${method} ${url.replace(/^.*applications\//, '')} : ${res.status} ${text.slice(0, 600)}`), { status: res.status, text });
  return text ? JSON.parse(text) : {};
}

/** One edit: changes are only visible in the Play Console once committed. */
async function edit(work) {
  const { id } = await call('POST', `${api}/edits`, {});
  try {
    await work(id);
    await call('POST', `${api}/edits/${id}:commit`);
  } catch (e) {
    await call('DELETE', `${api}/edits/${id}`).catch(() => {});
    throw e;
  }
}

async function verifier() {
  console.log(`Compte de service : ${account.client_email}`);
  try {
    await edit(async (id) => {
      const details = await call('GET', `${api}/edits/${id}/details`);
      console.log(`Appli trouvée : ${pkg} (langue par défaut ${details.defaultLanguage ?? 'non définie'}).`);
      const tracks = await call('GET', `${api}/edits/${id}/tracks`);
      for (const t of tracks.tracks ?? []) console.log(`Canal ${t.track} : ${(t.releases ?? []).map((r) => `${r.name ?? '?'} (${r.status})`).join(', ') || 'vide'}`);
      throw Object.assign(new Error('fin'), { done: true });
    });
  } catch (e) {
    if (e.done) { console.log('Accès à Google Play : OK'); return; }
    if (/SERVICE_DISABLED|has not been used|is disabled/.test(e.text ?? '')) {
      console.log(`::error::L'API Google Play Android Developer n'est pas activée sur le projet Google Cloud : https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com?project=${account.project_id}`);
    } else if (e.status === 401 || e.status === 403) {
      console.log(`::error::Google Play refuse l'accès : invitez ${account.client_email} dans Play Console > Utilisateurs et autorisations, avec l'accès à l'appli CNSNN.`);
    } else if (e.status === 404) {
      console.log(`::error::Appli ${pkg} introuvable dans ce compte Play Console.`);
    }
    throw e;
  }
}

async function fiche(shots) {
  const screenshots = readdirSync(shots).filter((f) => f.endsWith('.png')).sort();
  if (screenshots.length < 2) throw new Error(`Il faut au moins 2 captures (trouvées : ${screenshots.length}).`);
  await edit(async (id) => {
    await call('PUT', `${api}/edits/${id}/details`, { defaultLanguage: 'fr-FR', contactEmail: listing.contactEmail, contactWebsite: listing.contactWebsite });
    await call('PUT', `${api}/edits/${id}/listings/fr-FR`, { language: 'fr-FR', title: listing.title, shortDescription: listing.shortDescription, fullDescription: listing.fullDescription });
    const images = { icon: [join(here, 'icon.png')], featureGraphic: [join(here, 'feature.png')], phoneScreenshots: screenshots.map((f) => join(shots, f)) };
    for (const [type, files] of Object.entries(images)) {
      await call('DELETE', `${api}/edits/${id}/listings/fr-FR/${type}`);
      for (const file of files) await call('POST', `${upload}/edits/${id}/listings/fr-FR/${type}?uploadType=media`, readFileSync(file), 'image/png');
      console.log(`${type} : ${files.length} image(s)`);
    }
  });
  console.log('Fiche fr-FR envoyée : titre, descriptions, icône, bannière et captures.');
}

async function testFerme(aab) {
  await edit(async (id) => {
    const bundle = await call('POST', `${upload}/edits/${id}/bundles?uploadType=media`, readFileSync(aab), 'application/octet-stream');
    console.log(`AAB envoyé : version ${bundle.versionCode}`);
    // An app never published only takes draft releases: Yasin sends it for review from the Play Console.
    await call('PUT', `${api}/edits/${id}/tracks/alpha`, {
      track: 'alpha',
      releases: [{ name: listing.releaseName, versionCodes: [String(bundle.versionCode)], status: 'draft', releaseNotes: [{ language: 'fr-FR', text: listing.releaseNotes }] }],
    });
  });
  console.log('Version brouillon créée dans le test fermé (canal alpha).');
}

const [action, arg] = process.argv.slice(2);
if (action === 'verifier') await verifier();
else if (action === 'fiche') await fiche(arg);
else if (action === 'test-ferme') await testFerme(arg);
else throw new Error(`Action inconnue : ${action}`);
