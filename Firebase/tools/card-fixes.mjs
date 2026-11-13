// Corrects approved community cards (cards/{normalizedAnswer}) from card-fixes.json:
// - rename: a new answer means a new document id, so the card is copied under the new id (author,
//   dates and status kept) and the old document is deleted;
// - update: hint, category or difficulty changed in place.
// Then meta/cards moves, so the apps download the catalogue again. Already applied fixes are skipped.
// Usage: card-fixes.mjs [--apply]   Without --apply it only prints what it would do.
// Needs GOOGLE_APPLICATION_CREDENTIALS.
import { readFile } from 'node:fs/promises';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { normalize, consonants } from './daily.mjs';

const apply = process.argv.includes('--apply');
const fixes = JSON.parse(await readFile(new URL('card-fixes.json', import.meta.url), 'utf8'));
const categories = ['Général', 'Football', 'Cinéma', 'Géographie', 'Animaux', 'Objets'];
const difficulties = ['Facile', 'Moyen', 'Difficile'];
const editable = ['hint', 'category', 'difficulty'];
function check(card) {
  const id = card.normalizedAnswer;
  if (!/^[A-Z]{3,40}$/.test(id) || card.wordFull.length < 3 || card.wordFull.length > 80 || !card.wordNoVowels) throw new Error(`Réponse invalide : ${card.wordFull}`);
  if (card.hint.length < 5 || card.hint.length > 160) throw new Error(`Indice invalide : ${card.hint}`);
  if (!categories.includes(card.category) || !difficulties.includes(card.difficulty)) throw new Error(`Catégorie ou difficulté invalide : ${id}`);
}

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();
const batch = db.batch();
let changes = 0;

for (const r of fixes.rename ?? []) {
  const to = normalize(r.wordFull);
  const [from, target] = await Promise.all([db.doc(`cards/${r.from}`).get(), db.doc(`cards/${to}`).get()]);
  if (!from.exists) { console.log(`${r.from} : déjà absente${target.exists ? `, ${to} existe` : ''}`); continue; }
  if (target.exists) throw new Error(`${to} existe déjà : on ne l'écrase pas`);
  const card = { ...from.data(), wordFull: r.wordFull, wordNoVowels: consonants(r.wordFull), normalizedAnswer: to };
  for (const k of editable) if (r[k] !== undefined) card[k] = r[k];
  check(card);
  console.log(`${r.from} -> ${to} : « ${card.wordFull} », ${card.category} ${card.difficulty}, indice « ${card.hint} »`);
  batch.set(db.doc(`cards/${to}`), card);
  batch.delete(from.ref);
  changes++;
}
for (const u of fixes.update ?? []) {
  const doc = await db.doc(`cards/${u.id}`).get();
  if (!doc.exists) throw new Error(`Carte introuvable : ${u.id}`);
  const fields = Object.fromEntries(editable.filter((k) => u[k] !== undefined && u[k] !== doc.get(k)).map((k) => [k, u[k]]));
  if (!Object.keys(fields).length) { console.log(`${u.id} : déjà à jour`); continue; }
  check({ ...doc.data(), ...fields });
  console.log(`${u.id} : ${Object.entries(fields).map(([k, v]) => `${k} « ${doc.get(k)} » -> « ${v} »`).join(', ')}`);
  batch.update(doc.ref, fields);
  changes++;
}

if (!changes) console.log('Rien à changer.');
else if (!apply) console.log(`${changes} changement(s) prévus (aperçu : rien n'est écrit).`);
else {
  batch.set(db.doc('meta/cards'), { updatedAt: FieldValue.serverTimestamp() });
  await batch.commit();
  console.log(`${changes} changement(s) écrits, catalogue des cartes mis à jour.`);
}
