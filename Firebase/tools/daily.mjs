// Secret Mot du jour: the word list lives in this public repository only encrypted, and the
// answers live in Firestore where the rules reveal them only to players who finished the day.
//
//   node tools/daily.mjs public-key                 prints the public key of the service account (CI)
//   node tools/daily.mjs encrypt words.tsv [name]   encrypts a list into daily/<name>.enc.json (local, default words)
//   node tools/daily.mjs seed [--dry]               decrypts the lists and publishes the next 364 days (CI)
//   node tools/daily.mjs overlap words.txt [key.pem] fails if a card or duo of the app is a secret word (CI)
//   node tools/daily.mjs encrypt-changes changes.json  encrypts day replacements into daily/changes.enc.json (local)
//   node tools/daily.mjs preview key.pem            prints today and the next 14 days, encrypted for key.pem (CI)
//   node tools/daily.mjs replace                    publishes the replacements of daily/changes.enc.json (CI)
//
// words.tsv: one word per line, tab separated: F|M|D, category, word, hint. Every daily/words*.enc.json
// is used: a new list adds words without needing the older ones in clear. The monthly run of the
// Firebase workflow keeps 364 days published ahead, preferring words never played.
// Only the service account key (GitHub secret FIREBASE_SERVICE_ACCOUNT) can decrypt the list.
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { createPublicKey, publicEncrypt, privateDecrypt, randomBytes, createCipheriv, createDecipheriv, constants } from 'node:crypto';

const projectId = 'cnsnn-9ctosy';
const listDir = new URL('../daily/', import.meta.url);
const publicKeyFile = new URL('../daily/public.pem', import.meta.url);
// The first secret day (firestore.rules refuses free wins from it on).
export const firstDay = '2026-10-14';
// Days published ahead of today.
export const scheduledDays = 364;
const categories = ['Général', 'Football', 'Cinéma', 'Géographie', 'Animaux', 'Objets'];
const difficulties = { F: 'Facile', M: 'Moyen', D: 'Difficile' };

// Same as Core/WordEngine.swift: accents dropped, Œ and Æ expanded, letters only, Y is a vowel.
export function normalize(value) {
  return value.replace(/œ/g, 'oe').replace(/Œ/g, 'OE').replace(/æ/g, 'ae').replace(/Æ/g, 'AE')
    .normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z]/g, '');
}
export const consonants = (value) => normalize(value).replace(/[AEIOUY]/g, '');

// Same table as Core/GameRules.swift DailySchedule.difficulty and firestore.rules dailyBase.
export function difficultyOf(day) {
  const n = Math.round((Date.parse(`${day}T12:00:00Z`) - Date.parse('2024-01-01T12:00:00Z')) / 86400000);
  const w = ((n % 7) + 7) % 7;
  return w <= 1 ? 'Facile' : w <= 4 ? 'Moyen' : 'Difficile';
}
export function shiftDay(day, offset) {
  const d = new Date(`${day}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + offset); return d.toISOString().slice(0, 10);
}
// The word changes at each player's local midnight: the furthest ahead (UTC+14) plays first.
export function latestDay(date = new Date()) {
  return new Date(date.getTime() + 14 * 3600000).toISOString().slice(0, 10);
}

export function parseList(tsv) {
  const words = tsv.split('\n').filter((l) => l.trim()).map((line, i) => {
    const [d, category, word, hint] = line.split('\t');
    const entry = { word: word?.trim(), hint: hint?.trim(), category, difficulty: difficulties[d] };
    if (!entry.difficulty || !categories.includes(category) || !entry.word || !entry.hint) throw new Error(`Ligne ${i + 1} invalide`);
    if (!singleWord(entry)) throw new Error(`Ligne ${i + 1} : un seul mot par mot du jour`);
    return entry;
  });
  validate(words);
  return words;
}
export function validate(words) {
  const seen = new Set();
  for (const w of words) {
    const answer = normalize(w.word);
    if (answer.length < 3 || answer.length > 40 || !consonants(w.word)) throw new Error(`Mot invalide : ${w.word}`);
    if (w.hint.length < 5 || w.hint.length > 160) throw new Error(`Indice invalide : ${w.word}`);
    if (seen.has(answer)) throw new Error(`Doublon : ${w.word}`);
    seen.add(answer);
  }
}

// The Mot du jour is one word: an answer with a space (an expression) stays out of the schedule.
export const singleWord = (w) => !/\s/.test(w.word.trim());

// The game is general knowledge: football keeps at most one word in ten of each difficulty.
export const footballShare = 0.1;
export function limitFootball(words) {
  const out = [];
  for (const level of Object.values(difficulties)) {
    const pool = words.filter((w) => w.difficulty === level);
    const others = pool.filter((w) => w.category !== 'Football');
    const allowed = Math.floor(others.length * footballShare / (1 - footballShare));
    out.push(...others, ...shuffle(pool.filter((w) => w.category === 'Football'), `${level} football`).slice(0, allowed));
  }
  return out;
}

// A word judged too hard can be replaced on a given day without an app update.
// changes.json: { "days": [{ day, word, hint, category, difficulty }], "drop": ["word"] }. A replaced
// or dropped word never comes back, and the monthly seed keeps the replacements of the days ahead.
export function parseChanges(changes) {
  const days = changes.days ?? [], drop = changes.drop ?? [];
  for (const d of days) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d.day ?? '') || !singleWord(d) || !categories.includes(d.category)
      || d.difficulty !== difficultyOf(d.day)) throw new Error(`Remplacement invalide : ${d.day}`);
  }
  validate(days);
  if (new Set(days.map((d) => d.day)).size !== days.length) throw new Error('Deux remplacements le même jour');
  return { days, drop: new Set([...drop.map(normalize), ...days.map((d) => normalize(d.word))]) };
}
export function applyChanges(words, days, changes) {
  const kept = words.filter((w) => !changes.drop.has(normalize(w.word)));
  const byDay = new Map(changes.days.map((d) => [d.day, d]));
  return { words: kept, days: days.map((d) => (byDay.has(d.day) ? { ...byDay.get(d.day) } : d)) };
}

// Several lists become one; a word already in an earlier list is skipped.
export function combine(lists) {
  const seen = new Set(), words = [];
  let skipped = 0;
  for (const w of lists.flat()) {
    const answer = normalize(w.word);
    if (seen.has(answer)) { skipped++; continue; }
    seen.add(answer); words.push(w);
  }
  return { words, skipped };
}

// Each difficulty walks its own shuffled pool, so the categories vary from day to day. Words never
// played come first; played ones (answer -> last day) come back last, the longest ago first.
export function schedule(words, start = firstDay, days = scheduledDays, played = new Map()) {
  const pools = {};
  for (const level of Object.values(difficulties)) {
    const shuffled = shuffle(words.filter((w) => w.difficulty === level), level);
    const fresh = shuffled.filter((w) => !played.has(normalize(w.word)));
    const again = shuffled.filter((w) => played.has(normalize(w.word))).sort((a, b) => played.get(normalize(a.word)).localeCompare(played.get(normalize(b.word))));
    pools[level] = [...fresh, ...again];
  }
  const used = { Facile: 0, Moyen: 0, Difficile: 0 };
  const out = [];
  for (let i = 0; i < days; i++) {
    const day = shiftDay(start, i), level = difficultyOf(day), pool = pools[level];
    if (!pool.length) throw new Error(`Aucun mot ${level}`);
    out.push({ day, ...pool[used[level]++ % pool.length] });
  }
  return out;
}
function shuffle(list, seedText) {
  let seed = [...seedText].reduce((h, c) => (Math.imul(h, 31) + c.charCodeAt(0)) >>> 0, 2026);
  const random = () => { seed = (seed + 0x6d2b79f5) >>> 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) { const j = Math.floor(random() * (i + 1)); [out[i], out[j]] = [out[j], out[i]]; }
  return out;
}

// Hybrid encryption: AES-256-GCM for the list, RSA-OAEP-SHA256 for the AES key.
export function encrypt(words, publicKey) {
  const key = randomBytes(32), iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(words), 'utf8'), cipher.final()]);
  const wrapped = publicEncrypt({ key: publicKey, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, key);
  return { version: 1, count: words.length, key: wrapped.toString('base64'), iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64') };
}
export function decrypt(box, privateKey) {
  const key = privateDecrypt({ key: privateKey, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, Buffer.from(box.key, 'base64'));
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(box.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(box.tag, 'base64'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(box.data, 'base64')), decipher.final()]).toString('utf8'));
}

async function serviceAccount() {
  const path = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!path) throw new Error('GOOGLE_APPLICATION_CREDENTIALS manquant');
  return JSON.parse(await readFile(path, 'utf8'));
}

async function readChanges(privateKey) {
  const file = new URL('changes.enc.json', listDir);
  const box = await readFile(file, 'utf8').catch(() => null);
  return parseChanges(box ? decrypt(JSON.parse(box), privateKey) : {});
}
async function firestore() {
  const { initializeApp, applicationDefault } = await import('firebase-admin/app');
  const { getFirestore } = await import('firebase-admin/firestore');
  initializeApp({ credential: applicationDefault(), projectId });
  return getFirestore();
}
function publish(batch, db, d) {
  batch.set(db.doc(`dailyPuzzles/${d.day}`), { consonants: consonants(d.word), category: d.category, difficulty: d.difficulty });
  batch.set(db.doc(`dailyHints/${d.day}`), { hint: d.hint });
  batch.set(db.doc(`dailySecrets/${d.day}`), { answer: normalize(d.word), word: d.word, hint: d.hint, category: d.category, difficulty: d.difficulty });
}

async function seed(dry) {
  const { private_key: privateKey } = await serviceAccount();
  const files = (await readdir(listDir)).filter((name) => /^words.*\.enc\.json$/.test(name)).sort();
  const lists = await Promise.all(files.map(async (name) => decrypt(JSON.parse(await readFile(new URL(name, listDir), 'utf8')), privateKey)));
  const { words: all, skipped } = combine(lists);
  const single = all.filter(singleWord);
  const changes = await readChanges(privateKey);
  const words = applyChanges(limitFootball(single), [], changes).words;
  validate(words);
  const { FieldPath } = await import('firebase-admin/firestore');
  const db = await firestore();
  const today = latestDay();
  // Words already played (today included) wait for the others before coming back.
  const past = await db.collection('dailySecrets').where(FieldPath.documentId(), '<=', today).get();
  const played = new Map(past.docs.map((d) => [d.get('answer'), d.id]));
  // Today (in the time zone furthest ahead) and past days are never rewritten: someone may be playing them.
  const days = applyChanges(words, schedule(words, shiftDay(today, 1), scheduledDays, played), changes).days;
  const repeats = days.filter((d) => played.has(normalize(d.word))).length;
  console.log(`${files.length} liste(s), ${words.length} mots (${skipped} doublon(s), ${all.length - single.length} expression(s) de plusieurs mots et ${single.length - words.length} mot(s) de football écartés), ${played.size} déjà joués.`);
  console.log(`${days.length} jours à publier, du ${days[0]?.day} au ${days.at(-1)?.day}, dont ${repeats} mot(s) déjà joué(s).`);
  if (dry) return;
  for (let i = 0; i < days.length; i += 150) {
    const batch = db.batch();
    for (const d of days.slice(i, i + 150)) publish(batch, db, d);
    await batch.commit();
  }
  console.log('Mots du jour publiés.');
}

// The days still being played somewhere (the earliest time zone's today) and the next 14, with how many
// players finished each one, printed only encrypted for the given public key (the logs may become public).
async function preview(keyFile) {
  const db = await firestore();
  const start = shiftDay(latestDay(), -1);
  const out = [];
  for (let i = 0; i < 16; i++) {
    const day = shiftDay(start, i);
    const secret = (await db.doc(`dailySecrets/${day}`).get()).data();
    const results = i < 3 ? (await db.collection('dailyResults').where('day', '==', day).count().get()).data().count : 0;
    out.push({ day, word: secret?.word, hint: secret?.hint, category: secret?.category, difficulty: secret?.difficulty, results });
  }
  console.log(JSON.stringify(encrypt(out, await readFile(keyFile, 'utf8'))));
}

// Publishes the replacements of the days not over yet. Who started a replaced day without finishing
// it starts again on the new word (the old consonants would no longer accept any answer).
async function replace() {
  const { private_key: privateKey } = await serviceAccount();
  const changes = await readChanges(privateKey);
  const days = changes.days.filter((d) => d.day >= shiftDay(latestDay(), -1));
  if (!days.length) { console.log('Aucun remplacement à publier.'); return; }
  const db = await firestore();
  const answers = new Map((await db.collection('dailySecrets').get()).docs.map((d) => [d.get('answer'), d.id]));
  for (const d of days) {
    const other = answers.get(normalize(d.word));
    if (other && other !== d.day) throw new Error(`Le remplacement du ${d.day} est déjà le mot du ${other}`);
  }
  for (const d of days) {
    const batch = db.batch();
    publish(batch, db, d);
    const sessions = await db.collection('dailySessions').where('day', '==', d.day).get();
    const open = sessions.docs.filter((s) => !s.get('finishedAt'));
    for (const s of open) batch.delete(s.ref);
    await batch.commit();
    console.log(`${d.day} remplacé : ${open.length} partie(s) en cours relancée(s), ${sessions.size - open.length} terminée(s) gardée(s).`);
  }
}

// The app ships its Classique cards and Double sens words in clear: none of them may be a secret
// daily word, or anyone could read the answer of that day. Only the number of clashes is printed
// (the logs may become public); with a public key, the clashing words are printed encrypted for it.
async function overlap(wordsFile, reportKeyFile) {
  const { private_key: privateKey } = await serviceAccount();
  const files = (await readdir(listDir)).filter((name) => /^words.*\.enc\.json$/.test(name)).sort();
  const lists = await Promise.all(files.map(async (name) => decrypt(JSON.parse(await readFile(new URL(name, listDir), 'utf8')), privateKey)));
  const secret = new Set(combine(lists).words.map((w) => normalize(w.word)));
  const shipped = (await readFile(wordsFile, 'utf8')).split('\n').map((line) => line.trim().split(' ').at(-1)).filter(Boolean);
  const clashes = [...new Set(shipped.filter((word) => secret.has(normalize(word))))];
  console.log(`${shipped.length} mots de l'app comparés à ${secret.size} mots du jour secrets : ${clashes.length} en commun.`);
  if (!clashes.length) return;
  if (reportKeyFile) console.log(JSON.stringify(encrypt(clashes, await readFile(reportKeyFile, 'utf8'))));
  process.exitCode = 1;
}

// Command line only when run directly, not when another tool imports the functions above.
const direct = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
const [command, arg] = direct ? process.argv.slice(2) : [];
if (command === 'public-key') {
  const { private_key: privateKey, client_email: email } = await serviceAccount();
  console.log(`Clé publique de ${email} :`);
  console.log(createPublicKey(privateKey).export({ type: 'spki', format: 'pem' }));
} else if (command === 'encrypt') {
  const words = parseList(await readFile(arg, 'utf8'));
  const name = `${process.argv[4] ?? 'words'}.enc.json`;
  if (!/^words[\w-]*\.enc\.json$/.test(name)) throw new Error('Le nom doit commencer par words');
  await writeFile(new URL(name, listDir), JSON.stringify(encrypt(words, await readFile(publicKeyFile, 'utf8')), null, 1) + '\n');
  console.log(`${words.length} mots chiffrés dans daily/${name}`);
} else if (command === 'seed') {
  await seed(arg === '--dry');
} else if (command === 'overlap') {
  await overlap(arg, process.argv[4]);
} else if (command === 'encrypt-changes') {
  const changes = JSON.parse(await readFile(arg, 'utf8'));
  parseChanges(changes);
  await writeFile(new URL('changes.enc.json', listDir), JSON.stringify(encrypt(changes, await readFile(publicKeyFile, 'utf8')), null, 1) + '\n');
  console.log(`${changes.days?.length ?? 0} remplacement(s) chiffré(s) dans daily/changes.enc.json`);
} else if (command === 'preview') {
  await preview(arg);
} else if (command === 'replace') {
  await replace();
} else if (command) {
  console.error(`Commande inconnue : ${command}`); process.exit(1);
}
