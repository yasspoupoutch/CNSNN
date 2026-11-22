// Sprint: players whose own record (on their phone, synced in their progress) is above their line in
// the Sprint ranking, and why it may be. Read-only. Prints only pseudos (already shown in the rankings),
// numbers, dates and the kind of phone (iPhone ids are upper case, Android ids lower case).
// Costs about one read per player with a pseudo plus one per Sprint ranking line.
// Usage: sprint-check.mjs   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();
const paris = (t) => t ? new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', dateStyle: 'short', timeStyle: 'medium' }).format(t.toDate()) : '-';
const kind = (id) => /[A-F]/.test(id) ? 'iPhone' : /[a-f]/.test(id) ? 'Android' : '?';

const banned = new Set((await db.collection('banned').select().get()).docs.map((d) => d.id));
const accounts = new Map();
let pageToken;
do { const page = await getAuth().listUsers(1000, pageToken); for (const a of page.users) accounts.set(a.uid, a); pageToken = page.pageToken; } while (pageToken);
const day = (t) => t ? new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', dateStyle: 'short', timeStyle: 'short' }).format(new Date(t)) : '-';
const records = new Map((await db.collection('sprintRecords').get()).docs.map((d) => [d.id, d.data()]));
const users = (await db.collection('users').select('username').get()).docs.filter((d) => d.get('username'));
let shown = 0;
for (const u of users) {
  const progress = await db.doc(`users/${u.id}/private/progress`).get();
  let modes, saved;
  try { saved = JSON.parse(progress.get('json') ?? '{}'); modes = saved?.modes; } catch { continue; }
  const sprint = modes?.sprint;
  const own = sprint?.best?.words ?? 0;
  const line = records.get(u.id);
  if (!own && !line) continue;
  if (own <= (line?.best ?? 0)) continue;
  shown++;
  const games = Object.entries(sprint?.counts?.games ?? {}).map(([id, n]) => `${kind(id)} ${n}`).join(', ');
  const run = (await db.doc(`sprintRuns/${u.id}`).get()).get('startedAt');
  const a = accounts.get(u.id);
  const classic = (saved?.attempts ?? []).map((t) => Date.parse(t.date ?? '') || (typeof t.date === 'number' ? (t.date + 978307200) * 1000 : NaN)).filter((t) => t > 0).sort((x, y) => x - y);
  console.log(`${u.get('username')} : record sur le téléphone ${own}, au classement ${line?.best ?? 'aucun'}`
    + ` | ligne du ${paris(line?.at)}${line && line.at?.isEqual?.(line.startedAt) ? ' (importée)' : ''}`
    + ` | pseudo du téléphone ${saved?.username === u.get('username') ? 'identique' : 'DIFFÉRENT (le classement refuse alors tout envoi)'}`
    + ` | compte ${a ? (a.providerData.length ? 'e-mail' : 'invité') : 'introuvable'}, créé le ${day(a?.metadata.creationTime)}, dernière connexion ${day(a?.metadata.lastSignInTime)}${banned.has(u.id) ? ', SUSPENDU' : ''}`
    + ` | parties Classique ${classic.length} (du ${day(classic[0])} au ${day(classic.at(-1))})`
    + ` | parties Sprint par appareil : ${games || '-'} | dernière partie lancée ${paris(run)} | progression du ${paris(progress.get('updatedAt'))}`);
}
const runs = (await db.collection('sprintRuns').select().get()).docs.map((d) => d.id);
const named = new Set(users.map((u) => u.id));
console.log(`Parties Sprint notées par le serveur : ${runs.length} joueurs, dont ${runs.filter((id) => !named.has(id)).length} sans pseudo (invités ou comptes supprimés).`);
console.log(`${shown} joueur(s) avec un record Sprint plus haut que sa ligne du classement, sur ${users.length} pseudos et ${records.size} lignes.`);
