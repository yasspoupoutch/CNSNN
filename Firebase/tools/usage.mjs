// Firestore use against the free Spark quota (50,000 reads, 20,000 writes, 20,000 deletes a day). Google
// shows the real counts only in the Firebase console (Usage tab): its Monitoring API needs billing, which
// the project stays without. So this estimates them from activity: players of the daily word each day of
// the last week, times a pessimistic cost per player (leaderboards opened several times, friends,
// challenges, the cards catalogue when it changed). Counting costs about one read per 1,000 results.
// Prints counts only, never data: run logs become public whenever the repository is. Exits with an error
// past WARN of the daily read quota, so the run fails and GitHub sends its failure email.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { shiftDay } from './daily.mjs';

const WARN = 0.6;
const QUOTA = { read: 50_000, write: 20_000 };
// Per active player and day, on the high side.
const COST = { read: 250, write: 15 };

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();

const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Paris' });
const rows = [];
for (let i = 7; i >= 1; i--) {
    const day = shiftDay(today, -i);
    const snap = await db.collection('dailyResults').where('day', '==', day).count().get();
    rows.push({ day, players: snap.data().count });
}
const users = (await db.collection('users').count().get()).data().count;

const pct = (n, quota) => `${Math.round((n / quota) * 100)} %`;
console.log(`Comptes : ${users}`);
console.log('Jour        Joueurs  Lectures estimées    Écritures estimées');
for (const { day, players } of rows) {
    const reads = players * COST.read, writes = players * COST.write;
    console.log(`${day}  ${String(players).padStart(7)}  ${String(reads).padStart(7)} (${pct(reads, QUOTA.read).padStart(5)})  ${String(writes).padStart(7)} (${pct(writes, QUOTA.write).padStart(5)})`);
}
const peak = Math.max(...rows.map((row) => row.players));
const ceiling = Math.floor((QUOTA.read * WARN) / COST.read);
console.log(`Pic : ${peak} joueurs/jour. Seuil d'alerte : ~${ceiling} joueurs/jour (${WARN * 100} % des lectures gratuites).`);
console.log('Chiffres réels : console Firebase > Firestore > Utilisation.');
if (peak >= ceiling) {
    console.log(`::error::Firestore approche du quota gratuit : ${peak} joueurs/jour, alerte à ${ceiling}. Vérifier l'onglet Utilisation et préparer la suite.`);
    process.exit(2);
}
