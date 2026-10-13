// Publishes firestore.rules and the composite indexes of firestore.indexes.json to cnsnn-9ctosy
// with the Admin SDK and the Firestore REST API. Unlike `firebase deploy`, it does not need the
// Service Usage permission that the default Firebase Admin SDK service account lacks.
// Needs GOOGLE_APPLICATION_CREDENTIALS. Existing indexes are kept; missing ones are created.
import { readFile } from 'node:fs/promises';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getSecurityRules } from 'firebase-admin/security-rules';

const projectId = 'cnsnn-9ctosy';
const credential = applicationDefault();
initializeApp({ credential, projectId });

const source = await readFile(new URL('../firestore.rules', import.meta.url), 'utf8');
const ruleset = await getSecurityRules().releaseFirestoreRulesetFromSource(source);
console.log(`Règles publiées : ${ruleset.name}`);

const { indexes } = JSON.parse(await readFile(new URL('../firestore.indexes.json', import.meta.url), 'utf8'));
const { access_token: token } = await credential.getAccessToken();
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups`;
const signature = (fields) => fields.map((f) => `${f.fieldPath}:${f.order ?? f.arrayConfig}`).join(',');
let failed = false;
for (const index of indexes) {
  const url = `${base}/${index.collectionGroup}/indexes`;
  const listed = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!listed.ok) { console.error(`Lecture des index ${index.collectionGroup} : ${listed.status} ${await listed.text()}`); failed = true; continue; }
  const existing = ((await listed.json()).indexes ?? [])
    .filter((i) => i.queryScope === index.queryScope)
    .map((i) => signature(i.fields.filter((f) => f.fieldPath !== '__name__')));
  const label = `${index.collectionGroup} (${signature(index.fields)})`;
  if (existing.includes(signature(index.fields))) { console.log(`Index déjà présent : ${label}`); continue; }
  const created = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ queryScope: index.queryScope, fields: index.fields }),
  });
  if (created.ok || created.status === 409) console.log(`Index demandé : ${label} (construction en cours côté Firebase)`);
  else { console.error(`Création de l'index ${label} : ${created.status} ${await created.text()}`); failed = true; }
}
if (failed) process.exit(1);
