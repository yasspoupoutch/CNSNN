// The Mot du jour ranking of one day, as the app orders it (rank: found words by score, then revealed
// words, then lost ones; catch-ups stay out). Read-only: one read per result of that day.
// Usage: day.mjs YYYY-MM-DD   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();
const day = process.argv[2] || process.env.DAY;
if (!/^\d{4}-\d{2}-\d{2}$/.test(day ?? '')) throw new Error('Jour attendu au format AAAA-MM-JJ');

const fmt = (ms) => { const s = Math.round(ms / 1000); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
const docs = (await db.collection('dailyResults').where('day', '==', day).get()).docs.map((d) => d.data());
const ranked = docs.filter((r) => r.rank > 0).sort((a, b) => a.rank - b.rank);
console.log(`Mot du jour du ${day} : ${ranked.length} joueurs classés, ${docs.length - ranked.length} rattrapage(s) hors classement.`);
ranked.forEach((r, i) => {
  const state = r.correct ? `${fmt(r.scoreMs)} (temps ${fmt(r.timeMs)})` : r.revealed ? `révélé, ${fmt(r.timeMs)}` : 'perdu';
  const help = [r.usedHint && 'phrase', r.usedVowels && 'voyelles', r.usedLetters && `${r.usedLetters} lettre(s)`].filter(Boolean).join(', ');
  console.log(`${i + 1}. ${r.username} — ${state}${help ? ` · aides : ${help}` : ''}`);
});
