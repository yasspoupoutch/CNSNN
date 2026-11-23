// Copies one player's Sprint record from their synced progress onto the Sprint ranking, once, when
// they have no line yet (a record played on an app version without the ranking). Not checked by the
// server, like the import of 30 October 2026. Asked by Yasin for each player by pseudo.
// Usage: sprint-copy.mjs "pseudo"   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { legacySprintRecord } from './sprint.mjs';

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();
const pseudo = (process.argv[2] ?? '').trim();
if (!pseudo) { console.error('Pseudo manquant.'); process.exit(1); }
const users = (await db.collection('users').where('username', '==', pseudo).get()).docs;
if (users.length !== 1) { console.error(`${users.length} compte(s) avec ce pseudo : rien fait.`); process.exit(1); }
const uid = users[0].id;
const ref = db.doc(`sprintRecords/${uid}`);
if ((await ref.get()).exists) { console.log(`${pseudo} a déjà une ligne Sprint : rien fait.`); process.exit(0); }
const progress = await db.doc(`users/${uid}/private/progress`).get();
const now = Date.now();
const record = legacySprintRecord(uid, pseudo, progress.get('json') ?? '', now);
if (!record) { console.log(`${pseudo} n'a aucun record Sprint dans sa progression : rien fait.`); process.exit(0); }
const { startedAtMs, ...line } = record;
const at = Timestamp.fromMillis(startedAtMs);
const banned = (await db.doc(`banned/${uid}`).get()).exists;
await ref.create({ ...line, startedAt: at, at, ...(banned ? { suspended: true } : {}) });
console.log(`${pseudo} : ligne Sprint créée avec ${line.best} mots.`);
