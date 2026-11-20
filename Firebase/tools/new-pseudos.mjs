// Push notification (ntfy app) when new players chose a pseudo since the last check.
// No dependency (Firestore REST API + node:crypto), so the scheduled run stays short and free.
// Firestore cost per run: 1 read for the last check time, 1 read per new pseudo (at least 1),
// about 1 read for the total count, 3 reads for the last players, 1 write to save the check time. About 50 reads a day.
// Pseudos are never printed in the logs (the repository can become public), only sent to ntfy.
//
// Usage: node new-pseudos.mjs [--dry-run] [--test]
//   env FIREBASE_SERVICE_ACCOUNT (JSON), NTFY_TOPIC (secret topic name; without it nothing is sent)
//   --dry-run  reads only: no save, no notification (pull request check)
//   --test     always sends a notification, even with no new pseudo
//   --daily    the scheduled daily summary: sent once per French day, even with no new pseudo (so a
//              silent day shows the alert still works). GitHub often skips scheduled runs, so the
//              workflow tries several times in the morning; the tries after the first one that ran
//              only read the state (1 read) and stop.
import { createSign } from 'node:crypto';

const PROJECT = 'cnsnn-9ctosy';
const STATE = 'ops/newPseudos'; // admin-only: the rules deny every client access to "ops"
// Tests point these at the Firestore emulator and a local fake ntfy server.
const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const docsUrl = (project) => `${emulator ? `http://${emulator}` : 'https://firestore.googleapis.com'}/v1/projects/${project}/databases/(default)/documents`;
const NTFY_URL = process.env.NTFY_URL ?? 'https://ntfy.sh/';

const b64url = (data) => Buffer.from(data).toString('base64url');

async function accessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email, scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 600,
  }));
  const signature = createSign('RSA-SHA256').update(`${header}.${claims}`).sign(sa.private_key, 'base64url');
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${header}.${claims}.${signature}` }),
  });
  if (!res.ok) throw new Error(`Jeton Google refusé : ${res.status}`);
  return (await res.json()).access_token;
}

let DOCS = docsUrl(PROJECT);
async function firestore(token, path, init = {}) {
  const res = await fetch(`${DOCS}${path}`, {
    ...init, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Firestore ${path} : ${res.status} ${(await res.text()).slice(0, 300)}`);
  return res.json();
}

// Pure helpers, tested in new-pseudos.test.mjs.
// French time, e.g. "lundi 14 h 05".
export function parisTime(iso) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', weekday: 'long', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date(iso)).map((p) => [p.type, p.value]));
  return `${parts.weekday} ${parts.hour} h ${parts.minute}`;
}

// French calendar day, e.g. "2026-11-17", to send the daily summary once a day.
export function parisDay(ms) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Paris' }).format(new Date(ms));
}

// Date and time in French time, e.g. "jeudi 19/11 02 h 16".
export function parisDate(iso) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', weekday: 'long', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date(iso)).map((p) => [p.type, p.value]));
  return `${parts.weekday} ${parts.day}/${parts.month} ${parts.hour} h ${parts.minute}`;
}

// latest: the last players who chose a pseudo, repeated in every message, so a notification the
// phone missed (ntfy keeps them only 12 h) never loses a name.
export function message(pseudos, total, checkedAt, latest = []) {
  const n = pseudos.length;
  const title = n === 0 ? 'CNSNN : aucun nouveau pseudo' : n === 1 ? 'CNSNN : 1 nouveau pseudo' : `CNSNN : ${n} nouveaux pseudos`;
  const lines = pseudos.slice(0, 30).map((p) => `• ${p.pseudo} (${parisTime(p.createdAt)})`);
  if (n > 30) lines.push(`… et ${n - 30} autres`);
  if (total != null) lines.push(`Total : ${total} joueur${total > 1 ? "s" : ""} avec un pseudo`);
  if (latest.length) lines.push(`Derniers inscrits : ${latest.map((p) => `${p.pseudo} (${parisDate(p.createdAt)})`).join(', ')}`);
  if (checkedAt) lines.push(`Vérifié ${parisTime(checkedAt)} (heure française)`);
  return { title, body: lines.join('\n') || 'Rien de nouveau.' };
}

// Returns what happened; throws on a Firestore or ntfy error (the run then fails and GitHub emails).
export async function run({ dryRun = false, test = false, daily = false, topic = process.env.NTFY_TOPIC?.trim(), project = PROJECT, now = Date.now() } = {}) {
  let token = 'owner';
  DOCS = docsUrl(project);
  if (!emulator) {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT absent.');
    const sa = JSON.parse(raw);
    if (sa.project_id !== PROJECT) throw new Error(`Clé pour un autre projet : ${sa.project_id}`);
    token = await accessToken(sa);
  }

  // A profile is written with createdAt = server time; one written in the last minute may not be
  // visible yet, so stop one minute ago and start from there next time.
  const until = new Date(now - 60_000).toISOString();
  const state = await firestore(token, `/${STATE}`);
  const first = !state;
  const since = state?.fields?.lastCheck?.timestampValue ?? new Date(now - 24 * 3600_000).toISOString();
  const day = parisDay(now);
  if (daily && state?.fields?.lastSentDay?.stringValue === day) {
    console.log(`Résumé du jour déjà envoyé (${day}) : rien à faire.`);
    return { pseudos: [], total: null, sent: false, skipped: true };
  }
  const always = test || daily;

  const rows = await firestore(token, ':runQuery', {
    method: 'POST',
    body: JSON.stringify({ structuredQuery: {
      from: [{ collectionId: 'users' }],
      select: { fields: [{ fieldPath: 'username' }, { fieldPath: 'createdAt' }] },
      where: { compositeFilter: { op: 'AND', filters: [
        { fieldFilter: { field: { fieldPath: 'createdAt' }, op: 'GREATER_THAN', value: { timestampValue: since } } },
        { fieldFilter: { field: { fieldPath: 'createdAt' }, op: 'LESS_THAN_OR_EQUAL', value: { timestampValue: until } } },
      ] } },
      orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'ASCENDING' }],
      limit: 500,
    } }),
  });
  const pseudos = rows.filter((r) => r.document).map((r) => ({
    pseudo: r.document.fields?.username?.stringValue ?? '?',
    createdAt: r.document.fields?.createdAt?.timestampValue,
  }));

  let total = null;
  if (pseudos.length || always) {
    const agg = await firestore(token, ':runAggregationQuery', {
      method: 'POST',
      body: JSON.stringify({ structuredAggregationQuery: {
        structuredQuery: { from: [{ collectionId: 'users' }] },
        aggregations: [{ alias: 'n', count: {} }],
      } }),
    });
    total = Number(agg?.[0]?.result?.aggregateFields?.n?.integerValue ?? NaN);
    if (Number.isNaN(total)) total = null;
  }

  console.log(`Depuis ${since} : ${pseudos.length} nouveau(x) pseudo(s).${total != null ? ` Total : ${total}.` : ''}`);

  if (dryRun) { console.log('Essai à blanc : rien enregistré, rien envoyé.'); return { pseudos, total, sent: false }; }

  let sent = false;
  if ((pseudos.length || always) && topic) {
    const recent = await firestore(token, ':runQuery', {
      method: 'POST',
      body: JSON.stringify({ structuredQuery: {
        from: [{ collectionId: 'users' }],
        select: { fields: [{ fieldPath: 'username' }, { fieldPath: 'createdAt' }] },
        orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
        limit: 3,
      } }),
    });
    const latest = recent.filter((r) => r.document).map((r) => ({
      pseudo: r.document.fields?.username?.stringValue ?? '?',
      createdAt: r.document.fields?.createdAt?.timestampValue,
    }));
    const { title, body } = message(pseudos, total, new Date(now).toISOString(), latest);
    const res = await fetch(NTFY_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ topic, title: test && !pseudos.length ? 'CNSNN : alerte pseudos activée ✅' : title, message: body, tags: ['tada'], priority: pseudos.length ? 4 : 3 }),
    });
    if (!res.ok) throw new Error(`ntfy a refusé : ${res.status}`);
    sent = true;
    console.log('Notification envoyée.');
  } else if (!topic) {
    // Not saved, so these pseudos are announced once the topic is set.
    console.log('::warning::Le secret NTFY_TOPIC est absent : rien envoyé, rien enregistré.');
    return { pseudos, total, sent };
  }

  // Saved after sending, so a failed send is retried next time (at worst a pseudo is announced twice).
  const fields = { lastCheck: { timestampValue: until } };
  if (daily) fields.lastSentDay = { stringValue: day };
  await firestore(token, `/${STATE}?${Object.keys(fields).map((f) => `updateMask.fieldPaths=${f}`).join('&')}`, {
    method: 'PATCH',
    body: JSON.stringify({ fields }),
  });
  if (first) console.log('Première vérification : heure enregistrée.');
  return { pseudos, total, sent };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    await run({ dryRun: process.argv.includes('--dry-run'), test: process.argv.includes('--test'), daily: process.argv.includes('--daily') });
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
