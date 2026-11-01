// Who played the Mot du jour this week but is missing from the week's ranking, and why. Read-only.
// Prints only pseudos (already shown to every player in the rankings) and counts. Costs one read per
// result of the week plus one per leaderboard line.
// Usage: week.mjs [YYYY-MM-DD]   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();

const today = process.argv[2] || new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Paris' }).format(new Date());
const dayIndex = (key) => Math.floor(Date.parse(key + 'T00:00:00Z') / 86400000);
const week = Math.floor((dayIndex(today) + 3) / 7);
const monday = new Date((week * 7 - 3) * 86400000).toISOString().slice(0, 10);
const sunday = new Date((week * 7 + 3) * 86400000).toISOString().slice(0, 10);
const low = week * 100000000, high = (week + 1) * 100000000;

const results = (await db.collection('dailyResults').where('day', '>=', monday).where('day', '<=', sunday).get()).docs;
const byUser = new Map();
for (const r of results) {
  const u = byUser.get(r.get('userId')) ?? { name: r.get('username'), days: [], found: 0, catchUp: 0 };
  u.days.push(r.get('day')); if (r.get('correct')) u.found++; if (r.get('catchUp')) u.catchUp++;
  byUser.set(r.get('userId'), u);
}
const board = new Map((await db.collection('leaderboard').get()).docs.map((d) => [d.id, d.data()]));
const ranked = [...board.entries()].filter(([, b]) => b.weekRank >= low && b.weekRank < high && b.suspended !== true)
  .sort((a, b) => b[1].weekRank - a[1].weekRank).map(([uid]) => uid);

console.log(`Semaine du ${monday} au ${sunday} (aujourd'hui ${today}) : ${results.length} résultats, ${byUser.size} joueurs, ${ranked.length} lignes dans le classement de la semaine (l'appli en lit 60, en montre 50).`);
let missing = 0;
for (const [uid, u] of byUser) {
  const b = board.get(uid);
  const place = ranked.indexOf(uid);
  if (place >= 0 && place < 50) continue;
  missing++;
  const why = !b ? 'aucune ligne de classement'
    : b.suspended === true ? 'suspendu'
    : place >= 50 ? `rang ${place + 1}, au-delà des 50 lignes`
    : !('weekRank' in b) ? 'ligne sans champs semaine (écrite par une appli sans classement semaine : Android ou iOS 1.0)'
    : `semaine enregistrée ${b.week} au lieu de ${week}`;
  console.log(`- ${u.name} : ${u.days.length} jour(s) joué(s) (${u.days.sort().join(', ')}), ${u.found} trouvé(s), ${u.catchUp} rattrapage(s) ; ligne : lastResult ${b?.lastResult ?? '—'}, week ${b?.week ?? '—'}/${b?.weekPlayed ?? '—'} joués, monthPlayed ${b?.monthPlayed ?? '—'} → ${why}`);
}
console.log(missing ? `${missing} joueur(s) absent(s).` : 'Personne ne manque.');
