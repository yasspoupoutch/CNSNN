// Publishes firestore.rules and the composite indexes of firestore.indexes.json to cnsnn-9ctosy
// with the Admin SDK and the Firestore REST API. Unlike `firebase deploy`, it does not need the
// Service Usage permission that the default Firebase Admin SDK service account lacks.
// Needs GOOGLE_APPLICATION_CREDENTIALS. Existing indexes are kept; missing ones are created.
import { readFile } from 'node:fs/promises';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getSecurityRules } from 'firebase-admin/security-rules';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { importSprintRecords } from './sprint.mjs';

const projectId = 'cnsnn-9ctosy';
const credential = applicationDefault();
initializeApp({ credential, projectId });

// Pseudos already taken before they were unique: each one is reserved for its oldest holder, before the
// rules start requiring reservations. Later duplicates keep their pseudo until they change it.
const db = getFirestore();
const reserved = new Set((await db.collection('usernames').select().get()).docs.map((d) => d.id));
const profiles = (await db.collection('users').select('username', 'createdAt').get()).docs
  .sort((a, b) => (a.get('createdAt')?.toMillis() ?? 0) - (b.get('createdAt')?.toMillis() ?? 0));
let added = 0;
for (const profile of profiles) {
  const name = profile.get('username');
  const key = typeof name === 'string' ? name.toLowerCase() : '';
  if (!key || key.includes('/') || key === '.' || key === '..' || /^__.*__$/.test(key) || reserved.has(key)) continue;
  await db.collection('usernames').doc(key).create({ uid: profile.id, createdAt: FieldValue.serverTimestamp() });
  reserved.add(key); added++;
}
console.log(`Pseudos réservés : ${added} nouveaux, ${reserved.size} au total`);

// Daily scores became times (2026-10): each result gets its scoreMs and rank, each leaderboard line its
// month total, and the old points go away. Already converted documents are left as they are.
const MISSED = 600000;
const dayIndex = (day) => Math.round(Date.parse(`${day}T00:00:00Z`) / 86400000);
const monthIndex = (day) => Number(day.slice(0, 4)) * 12 + Number(day.slice(5, 7)) - 1;
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Paris' }).format(new Date());
const results = (await db.collection('dailyResults').get()).docs;
const months = new Map();
let scored = 0;
for (const result of results) {
  const r = result.data();
  if (typeof r.day !== 'string' || typeof r.timeMs !== 'number') continue;
  const scoreMs = r.correct ? Math.min(r.timeMs + (r.usedHint ? 60000 : 0), MISSED) : MISSED;
  if (monthIndex(r.day) === monthIndex(today)) {
    const m = months.get(r.userId) ?? { saved: 0, played: 0 };
    m.saved += MISSED - scoreMs; m.played++;
    months.set(r.userId, m);
  }
  if ('scoreMs' in r && !('points' in r)) continue;
  await result.ref.update({ scoreMs, rank: dayIndex(r.day) * 1000000 + (r.correct ? scoreMs : 999999), points: FieldValue.delete() });
  scored++;
}
let lines = 0;
for (const line of (await db.collection('leaderboard').get()).docs) {
  if ('month' in line.data()) continue;
  const m = months.get(line.id);
  const month = m ? monthIndex(today) : 0;
  await line.ref.update({ month, monthSaved: m?.saved ?? 0, monthPlayed: m?.played ?? 0,
    monthRank: m ? month * 100000000 + m.saved : 0, points: FieldValue.delete() });
  lines++;
}
console.log(`Classement au temps : ${scored} résultats et ${lines} lignes converties`);

// Weekly ranking (2026-10, iOS 1.1): each line gets this week's words found and their time, from the
// results already saved this week (Monday to Sunday). Lines that have a week already are left alone.
const weekIndex = (day) => Math.floor((dayIndex(day) + 3) / 7);
const thisWeek = weekIndex(today);
const weeks = new Map();
for (const result of results) {
  const r = result.data();
  if (typeof r.day !== 'string' || typeof r.timeMs !== 'number' || weekIndex(r.day) !== thisWeek) continue;
  const scoreMs = r.correct ? Math.min(r.timeMs + (r.usedHint ? 60000 : 0), MISSED) : MISSED;
  const w = weeks.get(r.userId) ?? { found: 0, timeMs: 0, played: 0 };
  if (r.correct) { w.found++; w.timeMs += scoreMs; }
  w.played++;
  weeks.set(r.userId, w);
}
let weekLines = 0;
for (const line of (await db.collection('leaderboard').get()).docs) {
  if ('week' in line.data()) continue;
  const w = weeks.get(line.id);
  if (!w) continue;
  await line.ref.update({ week: thisWeek, weekFound: w.found, weekTimeMs: w.timeMs, weekPlayed: w.played,
    weekRank: thisWeek * 100000000 + w.found * 10000000 + (9999999 - w.timeMs) });
  weekLines++;
}
console.log(`Classement de la semaine : ${weekLines} lignes complétées`);

// Challenges need a friend both ways (2026-10): friends added before the code also filled the other
// side (or whose other side failed) get it now, so their challenges keep working.
const usernames = new Map(profiles.map((p) => [p.id, p.get('username')]));
let mutual = 0;
for (const friend of (await db.collectionGroup('friends').get()).docs) {
  const owner = friend.ref.parent.parent?.id;
  if (!owner || !usernames.has(owner) || !usernames.has(friend.id) || owner === friend.id) continue;
  const back = db.doc(`users/${friend.id}/friends/${owner}`);
  if ((await back.get()).exists) continue;
  await back.create({ username: usernames.get(owner), addedAt: FieldValue.serverTimestamp() });
  mutual++;
}
console.log(`Amitiés rendues réciproques : ${mutual}`);

// Sprint ranking (iOS 1.3.1): the best Sprints played until now, imported once (see tools/sprint.mjs).
const sprint = await importSprintRecords(db, Timestamp, FieldValue);
console.log(sprint.skipped ? 'Records Sprint : déjà importés' : `Records Sprint importés : ${sprint.imported}`);

const source = await readFile(new URL('../firestore.rules', import.meta.url), 'utf8');
const ruleset = await getSecurityRules().releaseFirestoreRulesetFromSource(source);
console.log(`Règles publiées : ${ruleset.name}`);

const { indexes } = JSON.parse(await readFile(new URL('../firestore.indexes.json', import.meta.url), 'utf8'));
const { access_token: token } = await credential.getAccessToken();
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups`;
const signature = (fields) => fields.map((f) => `${f.fieldPath}:${f.order ?? f.arrayConfig}`).join(',');
let failed = false;
for (const index of indexes) {
  const url = `${base}/${index.collectionGroup}/indexes`;
  const listed = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!listed.ok) { console.error(`Lecture des index ${index.collectionGroup} : ${listed.status} ${await listed.text()}`); failed = true; continue; }
  const existing = ((await listed.json()).indexes ?? [])
    .filter((i) => i.queryScope === index.queryScope)
    .map((i) => signature(i.fields.filter((f) => f.fieldPath !== '__name__')));
  const label = `${index.collectionGroup} (${signature(index.fields)})`;
  if (existing.includes(signature(index.fields))) { console.log(`Index déjà présent : ${label}`); continue; }
  const created = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ queryScope: index.queryScope, fields: index.fields }),
  });
  if (created.ok || created.status === 409) console.log(`Index demandé : ${label} (construction en cours côté Firebase)`);
  else { console.error(`Création de l'index ${label} : ${created.status} ${await created.text()}`); failed = true; }
}
if (failed) process.exit(1);
