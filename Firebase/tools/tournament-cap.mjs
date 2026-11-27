// Tournament of 2026-11-30 (old bracket, before everyone plays): with a number of players that is not a
// power of 2, the apps of that time leave many players alone in round 1 ("contre personne"). Run once
// right after sign-ups close (Monday 08:00 UTC), it keeps the first signed up, as many as the largest
// power of 2 (35 -> 32), so everyone has an opponent on Monday. The others' sign-ups are deleted.
// Yasin's decision of 2026-11-28. Names are never printed (the repository can be public).
//
// Usage: node tournament-cap.mjs <week> [--dry-run]   env FIREBASE_SERVICE_ACCOUNT (JSON)
import { createSign } from 'node:crypto';

const PROJECT = 'cnsnn-9ctosy';
const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const DOCS = `${emulator ? `http://${emulator}` : 'https://firestore.googleapis.com'}/v1/projects/${process.env.PROJECT ?? PROJECT}/databases/(default)/documents`;
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

/** The players kept, in the apps' order (sign-up time, then uid): the largest power of 2, at most 64. */
export function keep(players) {
  const sorted = [...players].sort((a, b) => a.atMs - b.atMs || (a.uid < b.uid ? -1 : 1));
  let size = 1;
  while (size * 2 <= Math.min(sorted.length, 64)) size *= 2;
  return sorted.length < 2 ? { kept: sorted, removed: [] } : { kept: sorted.slice(0, size), removed: sorted.slice(size) };
}

export async function run(week, { dryRun = false, now = Date.now() } = {}) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(week) || week >= '2026-12-07') throw new Error(`Semaine invalide : ${week}`);
  const start = Date.parse(week + 'T08:00:00Z');
  if (!dryRun && (now < start || now > start + 3_600_000)) throw new Error('À lancer dans l\'heure qui suit la clôture des inscriptions (lundi 8 h UTC).');
  let token = 'owner';
  if (!emulator) {
    const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT ?? '{}');
    if (sa.project_id !== PROJECT) throw new Error('FIREBASE_SERVICE_ACCOUNT absent ou pour un autre projet.');
    token = await accessToken(sa);
  }
  const call = async (path, init = {}) => {
    const res = await fetch(`${DOCS}${path}`, { ...init, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' } });
    if (!res.ok) throw new Error(`Firestore ${path} : ${res.status} ${(await res.text()).slice(0, 300)}`);
    return res.json();
  };
  const rows = await call(`/tournaments/${week}:runQuery`, { method: 'POST', body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'players' }], limit: 500 } }) });
  const players = rows.filter((r) => r.document).map((r) => ({
    path: r.document.name.split('/documents')[1],
    uid: r.document.name.split('/').pop(),
    atMs: Date.parse(r.document.fields?.at?.timestampValue ?? '1970-01-01T00:00:00Z'),
  }));
  const { kept, removed } = keep(players);
  // Nobody has played yet in a kept tournament: no run of round 1 from a removed player.
  console.log(`Tournoi du ${week} : ${players.length} inscrits, ${kept.length} gardés, ${removed.length} retirés.`);
  if (dryRun) { console.log('Essai à blanc : rien supprimé.'); return { kept, removed }; }
  for (const p of removed) await call(p.path, { method: 'DELETE' });
  console.log('Inscriptions en trop supprimées.');
  return { kept, removed };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    await run(process.argv[2], { dryRun: process.argv.includes('--dry-run') });
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
