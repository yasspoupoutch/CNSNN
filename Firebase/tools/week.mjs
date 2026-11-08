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

// Today's Mot du jour games (finished since midnight in Paris), and which ones are out of today's
// ranking: lost, caught-up day, suspended. One read per result finished today.
const parisOffset = (d) => { const p = new Intl.DateTimeFormat('en-US', { timeZone: 'Europe/Paris', timeZoneName: 'shortOffset' }).formatToParts(d).find((x) => x.type === 'timeZoneName').value; return Number(p.replace('GMT', '') || 0); };
const midnight = new Date(Date.parse(today + 'T00:00:00Z') - parisOffset(new Date(today + 'T12:00:00Z')) * 3600000);
const played = (await db.collection('dailyResults').where('finishedAt', '>=', midnight).get()).docs.map((d) => d.data())
  .filter((r) => r.finishedAt.toDate() < new Date(midnight.getTime() + 86400000));
const hour = (r) => new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', hour: '2-digit', minute: '2-digit' }).format(r.finishedAt.toDate());
const inRanking = played.filter((r) => r.day === today && r.catchUp !== true && r.correct && r.suspended !== true);
console.log(`\nAujourd'hui ${today} (heure de Paris) : ${played.length} parties de Mot du jour terminées, ${inRanking.length} dans le classement du jour.`);
console.log('Dans le classement : ' + inRanking.sort((a, b) => a.rank - b.rank).map((r) => r.username).join(', '));
for (const r of played.filter((x) => !inRanking.includes(x)).sort((a, b) => a.finishedAt.toMillis() - b.finishedAt.toMillis())) {
  const why = r.suspended === true ? 'suspendu' : r.catchUp === true ? `rattrapage du ${r.day} (${r.correct ? 'trouvé' : 'perdu'})` : r.day !== today ? `mot du ${r.day} (autre fuseau horaire)` : 'perdu';
  console.log(`- ${r.username} à ${hour(r)} : ${why}`);
}

// Daily sessions started today with no result: finished but not published (still on the phone), or
// abandoned (word open, no answer). One read per session started today.
const resultIds = new Set(played.map((r) => r.userId + '_' + r.day));
const sessions = (await db.collection('dailySessions').where('startedAt', '>=', midnight).get()).docs
  .filter((d) => d.get('startedAt').toDate() < new Date(midnight.getTime() + 86400000) && !resultIds.has(d.id));
const names = new Map();
for (const s of sessions) { const u = await db.doc('users/' + s.get('userId')).get(); names.set(s.id, u.get('username') ?? '(sans pseudo)'); }
console.log(`\nParties commencées aujourd'hui sans résultat publié : ${sessions.length}`);
for (const s of sessions) {
  const d = s.data(), at = new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', hour: '2-digit', minute: '2-digit' }).format(d.startedAt.toDate());
  const state = 'finishedAt' in d ? `terminée (${d.correct ? 'trouvé' : 'perdu'}) mais résultat pas publié` : `pas terminée (${d.wrongAnswers ?? 0} erreur(s), indice ${d.hintUsed ? 'oui' : 'non'})`;
  console.log(`- ${names.get(s.id)} : mot du ${d.day}${d.catchUp ? ' (rattrapage)' : ''}, commencée à ${at}, ${state}`);
}
