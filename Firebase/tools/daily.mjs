// Secret Mot du jour: the word list lives in this public repository only encrypted, and the
// answers live in Firestore where the rules reveal them only to players who finished the day.
//
//   node tools/daily.mjs public-key          prints the public key of the service account (CI)
//   node tools/daily.mjs encrypt words.tsv   encrypts a list into daily/words.enc.json (local)
//   node tools/daily.mjs seed [--dry]        decrypts the list and publishes the days (CI)
//
// words.tsv: one word per line, tab separated: F|M|D, category, word, hint.
// Only the service account key (GitHub secret FIREBASE_SERVICE_ACCOUNT) can decrypt the list.
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { createPublicKey, publicEncrypt, privateDecrypt, randomBytes, createCipheriv, createDecipheriv, constants } from 'node:crypto';

const projectId = 'cnsnn-9ctosy';
const listFile = new URL('../daily/words.enc.json', import.meta.url);
const publicKeyFile = new URL('../daily/public.pem', import.meta.url);
// The first secret day. The schedule is computed from it, so it never changes.
export const firstDay = '2026-10-14';
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
export function parisDay(date = new Date()) {
  const p = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Paris', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date);
  const g = (t) => p.find((x) => x.type === t).value;
  return `${g('year')}-${g('month')}-${g('day')}`;
}

export function parseList(tsv) {
  const words = tsv.split('\n').filter((l) => l.trim()).map((line, i) => {
    const [d, category, word, hint] = line.split('\t');
    const entry = { word: word?.trim(), hint: hint?.trim(), category, difficulty: difficulties[d] };
    if (!entry.difficulty || !categories.includes(category) || !entry.word || !entry.hint) throw new Error(`Ligne ${i + 1} invalide`);
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

// Each difficulty walks its own shuffled pool, so the categories vary from day to day.
export function schedule(words, start = firstDay, days = scheduledDays) {
  const pools = {};
  for (const level of Object.values(difficulties)) pools[level] = shuffle(words.filter((w) => w.difficulty === level), level);
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

async function seed(dry) {
  const { private_key: privateKey } = await serviceAccount();
  const words = decrypt(JSON.parse(await readFile(listFile, 'utf8')), privateKey);
  validate(words);
  const today = parisDay();
  // Today and past days are never rewritten: someone may already be playing them.
  const days = schedule(words).filter((d) => d.day > today);
  console.log(`${words.length} mots, ${days.length} jours à publier, du ${days[0]?.day} au ${days.at(-1)?.day}.`);
  if (dry) return;
  const { initializeApp, applicationDefault } = await import('firebase-admin/app');
  const { getFirestore } = await import('firebase-admin/firestore');
  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();
  for (let i = 0; i < days.length; i += 150) {
    const batch = db.batch();
    for (const d of days.slice(i, i + 150)) {
      batch.set(db.doc(`dailyPuzzles/${d.day}`), { consonants: consonants(d.word), category: d.category, difficulty: d.difficulty });
      batch.set(db.doc(`dailyHints/${d.day}`), { hint: d.hint });
      batch.set(db.doc(`dailySecrets/${d.day}`), { answer: normalize(d.word), word: d.word, hint: d.hint, category: d.category, difficulty: d.difficulty });
    }
    await batch.commit();
  }
  console.log('Mots du jour publiés.');
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
  await writeFile(listFile, JSON.stringify(encrypt(words, await readFile(publicKeyFile, 'utf8')), null, 1) + '\n');
  console.log(`${words.length} mots chiffrés dans daily/words.enc.json`);
} else if (command === 'seed') {
  await seed(arg === '--dry');
} else if (command) {
  console.error(`Commande inconnue : ${command}`); process.exit(1);
}
