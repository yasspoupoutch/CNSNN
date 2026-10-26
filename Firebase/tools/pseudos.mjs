// The pseudos one account has carried: is a player new, or someone who renamed? Looks up the account
// holding the pseudo, then the names saved on its daily results, challenges, reports and proposals
// (each keeps the pseudo of when it was written). Read-only, a few dozen reads. Printed only
// encrypted for the given public key (the logs may become public), never an email address.
// Usage: pseudos.mjs key.pem pseudo   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { readFile } from 'node:fs/promises';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { encrypt } from './daily.mjs';

const publicKey = await readFile(process.argv[2], 'utf8');
const pseudo = (process.argv[3] ?? '').trim();
if (!pseudo) throw new Error('Pseudo manquant');
initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();

const iso = (t) => (t ? new Date(t).toISOString() : null);
let uid = (await db.doc(`usernames/${pseudo.toLowerCase()}`).get()).get('uid');
if (!uid) uid = (await db.collection('users').where('username', '==', pseudo).limit(1).get()).docs[0]?.id;
let report = { pseudo, found: false };
if (uid) {
  const profile = await db.doc(`users/${uid}`).get();
  const account = await getAuth().getUser(uid).catch(() => null);
  // name -> first and last time it was seen
  const seen = new Map();
  const note = (name, when, where) => {
    if (!name) return;
    const s = seen.get(name) ?? { first: when, last: when, where: new Set() };
    if (when && (!s.first || when < s.first)) s.first = when;
    if (when && (!s.last || when > s.last)) s.last = when;
    s.where.add(where);
    seen.set(name, s);
  };
  const dailies = (await db.collection('dailyResults').where('userId', '==', uid).select('username', 'day').get()).docs;
  for (const d of dailies) note(d.get('username'), d.get('day'), 'mot du jour');
  for (const [field, name] of [['from', 'fromName'], ['to', 'toName']]) {
    for (const c of (await db.collection('challenges').where(field, '==', uid).select(name, 'createdAt').get()).docs) {
      note(c.get(name), iso(c.get('createdAt')?.toDate())?.slice(0, 10), 'défi');
    }
  }
  for (const r of (await db.collection('playerReports').where('playerId', '==', uid).select('username', 'createdAt').get()).docs) {
    note(r.get('username'), iso(r.get('createdAt')?.toDate())?.slice(0, 10), 'signalement');
  }
  for (const c of (await db.collection('cards').where('createdBy', '==', uid).select('authorName', 'createdAt').get()).docs) {
    note(c.get('authorName'), iso(c.get('createdAt')?.toDate())?.slice(0, 10), 'mot proposé');
  }
  const board = await db.doc(`leaderboard/${uid}`).get();
  report = {
    pseudo, found: true,
    current: profile.get('username') ?? null,
    createdAt: iso(profile.get('createdAt')?.toDate()) ?? iso(account?.metadata.creationTime),
    lastSignIn: iso(account?.metadata.lastSignInTime),
    account: account ? (account.email ? 'email' : 'invité') : 'supprimé',
    renamedAt: iso(profile.get('updatedAt')?.toDate()),
    dailies: dailies.length,
    played: board.get('played') ?? 0,
    names: [...seen].map(([name, s]) => ({ name, first: s.first, last: s.last, where: [...s.where] }))
      .sort((a, b) => String(a.first).localeCompare(String(b.first))),
  };
}
console.log(`Pseudo cherché : trouvé = ${report.found}.`);
console.log(JSON.stringify(encrypt(report, publicKey)));
