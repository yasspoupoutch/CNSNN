// Shows, then deletes, player accounts by pseudo, the way the app's « Supprimer mon compte » does:
// profile, progress, leaderboard line, friends (both ways), codes, pseudo, daily history, sessions,
// reports, challenges, unapproved proposals; approved cards stay without the author. Then the
// Firebase Auth account. Never prints an email address (Actions logs are public with the repo).
// Usage: delete-users.mjs "Pseudo1,Pseudo2" [--delete]   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const names = (process.argv[2] ?? '').split(',').map((n) => n.trim()).filter(Boolean);
const doDelete = process.argv.includes('--delete');
if (!names.length || names.some((n) => !/^[\p{L}\p{N} _.-]{2,20}$/u.test(n))) { console.error('Pseudos invalides.'); process.exit(1); }
initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();
const auth = getAuth();

const day = (t) => (t ? new Date(t).toISOString().slice(0, 10) : 'jamais');
const query = async (collection, field, uid) => (await db.collection(collection).where(field, '==', uid).get()).docs;

const profiles = (await db.collection('users').select('username').get()).docs;
for (const name of names) {
  const twins = profiles.filter((p) => String(p.get('username') ?? '').toLowerCase() === name.toLowerCase());
  if (twins.length > 1) console.log(`« ${name} » : ${twins.length} profils portent ce pseudo (${twins.map((p) => p.id).join(', ')}) ; seul celui qui le réserve est traité.`);
  const reserved = await db.doc(`usernames/${name.toLowerCase()}`).get();
  const uid = reserved.data()?.uid;
  if (!uid) { console.log(`« ${name} » : aucun joueur avec ce pseudo.`); continue; }
  const profile = (await db.doc(`users/${uid}`).get()).data() ?? {};
  let account = null;
  try { account = await auth.getUser(uid); } catch { /* already gone from Auth */ }
  const results = await query('dailyResults', 'userId', uid);
  const friends = (await db.collection(`users/${uid}/friends`).get()).docs;
  console.log(`« ${profile.username ?? name} » : uid ${uid}, ${account ? (account.email ? 'compte avec email' : 'compte invité') : 'plus de compte Auth'}, `
    + `créé le ${day(account?.metadata.creationTime)}, dernière connexion ${day(account?.metadata.lastSignInTime)}, `
    + `${results.length} mots du jour, ${friends.length} amis${(await db.doc(`admins/${uid}`).get()).exists ? ', ADMINISTRATEUR' : ''}`);
  if (!doDelete) continue;
  if ((await db.doc(`admins/${uid}`).get()).exists) { console.error(`  refusé : « ${name} » est administrateur.`); process.exitCode = 1; continue; }

  const refs = [db.doc(`users/${uid}/private/progress`), db.doc(`leaderboard/${uid}`), db.doc(`sprintRecords/${uid}`), db.doc(`sprintRuns/${uid}`), db.doc(`banned/${uid}`), ...friends.map((d) => d.ref), ...results.map((d) => d.ref)];
  // Friends lists of other players pointing at this account.
  refs.push(...friends.map((d) => db.doc(`users/${d.id}/friends/${uid}`)));
  for (const [collection, field] of [['friendCodes', 'uid'], ['usernames', 'uid'], ['challengeInvites', 'from'], ['dailySessions', 'userId'],
    ['reports', 'userId'], ['playerReports', 'userId'], ['playerReports', 'playerId'], ['challenges', 'from'], ['challenges', 'to']]) {
    refs.push(...(await query(collection, field, uid)).map((d) => d.ref));
  }
  const authored = await query('cards', 'createdBy', uid);
  refs.push(...authored.filter((d) => d.data().status !== 'approved').map((d) => d.ref));
  const live = authored.filter((d) => d.data().status === 'approved');
  const writer = db.bulkWriter();
  writer.set(db.doc(`deletedUsers/${uid}`), { deletedAt: FieldValue.serverTimestamp() });
  writer.delete(db.doc(`users/${uid}`));
  for (const ref of refs) writer.delete(ref);
  for (const card of live) writer.update(card.ref, { createdBy: 'deleted', authorName: FieldValue.delete() });
  await writer.close();
  if (account) await auth.deleteUser(uid);
  console.log(`  supprimé : ${refs.length + 1} documents, ${live.length} cartes gardées sans auteur, compte Auth ${account ? 'effacé' : 'déjà absent'}.`);
}
