// Every player who chose a pseudo, played or not: pseudo, account creation, last sign-in, guest or
// email account, daily words played, practice progress synced. Accounts that never chose a pseudo are
// only counted. Read-only. Printed only encrypted for the given public key (the logs may become public),
// never an email address. Costs about one read per player plus one per 1,000 daily results.
// Usage: players.mjs key.pem   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { readFile } from 'node:fs/promises';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { encrypt } from './daily.mjs';

const publicKey = await readFile(process.argv[2], 'utf8');
initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();

const accounts = new Map();
let pageToken;
do {
  const page = await getAuth().listUsers(1000, pageToken);
  for (const u of page.users) accounts.set(u.uid, u);
  pageToken = page.pageToken;
} while (pageToken);

const dailies = new Map();
for (const d of (await db.collection('dailyResults').select('userId').get()).docs) {
  const uid = d.get('userId');
  dailies.set(uid, (dailies.get(uid) ?? 0) + 1);
}
const profiles = (await db.collection('users').select('username', 'createdAt').get()).docs;
const progress = profiles.length ? await db.getAll(...profiles.map((p) => db.doc(`users/${p.id}/private/progress`)), { fieldMask: ['updatedAt'] }) : [];

const iso = (t) => (t ? new Date(t).toISOString() : null);
const players = profiles.map((p, i) => {
  const account = accounts.get(p.id);
  return {
    pseudo: p.get('username'),
    createdAt: iso(p.get('createdAt')?.toDate()) ?? iso(account?.metadata.creationTime),
    lastSignIn: iso(account?.metadata.lastSignInTime),
    account: account ? (account.email ? 'email' : 'invité') : 'supprimé',
    dailies: dailies.get(p.id) ?? 0,
    practice: progress[i].exists,
  };
}).sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));

const named = new Set(profiles.map((p) => p.id));
const withoutPseudo = [...accounts.keys()].filter((uid) => !named.has(uid)).length;
console.log(`Joueurs avec pseudo : ${players.length}. Comptes sans pseudo : ${withoutPseudo}.`);
console.log(JSON.stringify(encrypt({ players, withoutPseudo }, publicKey)));
