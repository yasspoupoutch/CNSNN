// Puts a player's Sprint record from their synced progress (the number on their home screen) onto the
// Sprint ranking when it is higher than their line, or when they have none (a record played on an app
// version without the ranking, or a game whose score never reached the server). Not checked by the
// server, like the import of 30 October 2026. Asked by Yasin on 23 November 2026.
// Usage: sprint-copy.mjs "pseudo" | sprint-copy.mjs tous   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { legacySprintRecord } from './sprint.mjs';

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();
const wanted = (process.argv[2] ?? '').trim();
if (!wanted) { console.error('Pseudo (ou « tous ») manquant.'); process.exit(1); }
const users = wanted === 'tous'
  ? (await db.collection('users').select('username').get()).docs.filter((d) => d.get('username'))
  : (await db.collection('users').where('username', '==', wanted).get()).docs;
if (wanted !== 'tous' && users.length !== 1) { console.error(`${users.length} compte(s) avec ce pseudo : rien fait.`); process.exit(1); }
let changed = 0;
for (const u of users) {
  const pseudo = u.get('username');
  const ref = db.doc(`sprintRecords/${u.id}`);
  const line = await ref.get();
  const progress = await db.doc(`users/${u.id}/private/progress`).get();
  const record = legacySprintRecord(u.id, pseudo, progress.get('json') ?? '', Date.now());
  if (!record || record.best <= (line.get('best') ?? 0)) continue;
  const { startedAtMs, ...fields } = record;
  const at = Timestamp.fromMillis(startedAtMs);
  const banned = line.exists ? line.get('suspended') === true : (await db.doc(`banned/${u.id}`).get()).exists;
  await ref.set({ ...fields, startedAt: at, at, ...(banned ? { suspended: true } : {}) });
  console.log(`${pseudo} : ${line.exists ? `ligne passée de ${line.get('best')} à` : 'ligne créée avec'} ${fields.best} mots.`);
  changed++;
}
console.log(`${changed} ligne(s) Sprint changée(s).`);
