// The crowns on the home screen: last week's number 1 of the Mot du jour and the winner of the last
// tournament, written to meta/champions (every player reads it, nobody but this tool writes it).
// No dependency (Firestore REST API + node:crypto), like new-pseudos.mjs.
// Firestore cost per run: 1 read for meta/champions and 1-2 counts of tournament players. Once a week
// more: one read per Mot du jour result of last week (the week's number 1), and when a tournament ends a
// few reads (the runs of its last two rounds, the winner's name).
// Names are never printed in the logs (the repository can become public).
//
// Usage: node champions.mjs [--dry-run]   env FIREBASE_SERVICE_ACCOUNT (JSON)
import { createSign } from 'node:crypto';

const PROJECT = 'cnsnn-9ctosy';
const DOC = 'meta/champions';
const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const docsUrl = (project) => `${emulator ? `http://${emulator}` : 'https://firestore.googleapis.com'}/v1/projects/${project}/databases/(default)/documents`;
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
  const res = await fetch(`${DOCS}${path}`, { ...init, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Firestore ${path} : ${res.status} ${(await res.text()).slice(0, 300)}`);
  return res.json();
}
const value = (f) => f == null ? undefined
  : 'stringValue' in f ? f.stringValue
  : 'integerValue' in f ? Number(f.integerValue)
  : 'doubleValue' in f ? f.doubleValue
  : 'booleanValue' in f ? f.booleanValue
  : 'timestampValue' in f ? Date.parse(f.timestampValue)
  : 'nullValue' in f ? null : undefined;
const plain = (doc) => Object.fromEntries(Object.entries(doc?.fields ?? {}).map(([k, f]) => [k, value(f)]));
const field = (v) => v == null ? { nullValue: null } : typeof v === 'string' ? { stringValue: v } : Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };

// ---- Pure helpers, tested in tests/champions.test.mjs.

const DAY = 86_400_000;
export const parisDay = (ms) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Paris' }).format(new Date(ms));
const dayIndex = (key) => Math.floor(Date.parse(key + 'T00:00:00Z') / DAY);
// Weeks since Monday 1969-12-29, as DailyScore.weekIndex (Core/GameRules.swift).
export const weekIndex = (key) => Math.floor((dayIndex(key) + 3) / 7);
export const mondayOf = (week) => new Date((week * 7 - 3) * DAY).toISOString().slice(0, 10);
export const sundayOf = (week) => new Date((week * 7 + 3) * DAY).toISOString().slice(0, 10);

/** The week's number 1, as the week's ranking: the most words found, then the lowest total time. */
export function weekWinner(results) {
  const by = new Map();
  for (const r of results) {
    if (!r.userId || r.suspended === true) continue;
    const u = by.get(r.userId) ?? { uid: r.userId, name: r.username ?? 'Joueur', found: 0, timeMs: 0, last: '' };
    if (r.correct === true) { u.found++; u.timeMs += r.scoreMs ?? 0; }
    if ((r.day ?? '') >= u.last) { u.last = r.day ?? ''; u.name = r.username ?? u.name; }
    by.set(r.userId, u);
  }
  const best = [...by.values()].filter((u) => u.found > 0)
    .sort((a, b) => b.found - a.found || a.timeMs - b.timeMs || (a.uid < b.uid ? -1 : 1))[0];
  return best ? { uid: best.uid, name: best.name, found: best.found, timeMs: best.timeMs } : null;
}

// The tournament calendar, as Core/Tournament.swift.
export const EVERYONE_PLAYS_FROM = '2026-12-07';
export const tournamentStart = (week) => Date.parse(week + 'T08:00:00Z');
export function rounds(players, week) {
  const count = Math.min(players, 64);
  if (count < 2) return 0;
  let size = 1, n = 0;
  if (week >= EVERYONE_PLAYS_FROM) { while (size * 2 <= count) { size *= 2; n++; } } else { while (size < count) { size *= 2; n++; } }
  return n;
}
/** The tournament that started last (on Monday at 08:00 UTC, at or before now). */
export function lastStartedWeek(now) {
  const day = Math.floor((now - 8 * 3_600_000) / DAY);
  const monday = day - (((day + 3) % 7) + 7) % 7;
  return new Date(monday * DAY).toISOString().slice(0, 10);
}
const score = (r) => r.finishedAt - r.startedAt + (r.skips ?? 0) * 20_000;
/**
 * The winner of the final: the best run of the last round finished in time, among the players who
 * also played the round before (so only finalists count; in the old format, round 1 could be a bye).
 */
export function finalWinner({ total, finalRuns, semiRuns, endMs, byesBefore }) {
  const semis = new Set(semiRuns.filter((r) => r.finishedAt != null).map((r) => r.uid));
  const ok = finalRuns.filter((r) => r.round === total && r.finishedAt != null && r.finishedAt <= endMs
    && (total === 1 || semis.has(r.uid) || (byesBefore && total === 2)));
  ok.sort((x, y) => score(x) - score(y) || (x.errors ?? 0) - (y.errors ?? 0) || x.finishedAt - y.finishedAt || (x.uid < y.uid ? -1 : 1));
  return ok[0]?.uid ?? null;
}

// ---- The run.

async function query(token, parent, collection, where, select, limit = 1000) {
  const rows = await firestore(token, `${parent ? '/' + parent : ''}:runQuery`, {
    method: 'POST',
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: collection }], ...(select ? { select: { fields: select.map((f) => ({ fieldPath: f })) } } : {}), where, limit } }),
  });
  return rows.filter((r) => r.document).map((r) => plain(r.document));
}
async function count(token, parent, collection) {
  const agg = await firestore(token, `/${parent}:runAggregationQuery`, {
    method: 'POST',
    body: JSON.stringify({ structuredAggregationQuery: { structuredQuery: { from: [{ collectionId: collection }] }, aggregations: [{ alias: 'n', count: {} }] } }),
  });
  return Number(agg?.[0]?.result?.aggregateFields?.n?.integerValue ?? 0);
}
const eq = (path, v) => ({ fieldFilter: { field: { fieldPath: path }, op: 'EQUAL', value: field(v) } });

export async function run({ dryRun = false, project = PROJECT, now = Date.now() } = {}) {
  let token = 'owner';
  DOCS = docsUrl(project);
  if (!emulator) {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT absent.');
    const sa = JSON.parse(raw);
    if (sa.project_id !== PROJECT) throw new Error(`Clé pour un autre projet : ${sa.project_id}`);
    token = await accessToken(sa);
  }
  const state = plain(await firestore(token, `/${DOC}`));
  const update = {};

  // Last week's number 1, once the week is over (weeks end on Sunday at midnight, French time).
  const last = weekIndex(parisDay(now)) - 1;
  if (state.weekIndex !== last) {
    const results = await query(token, '', 'dailyResults', { compositeFilter: { op: 'AND', filters: [
      { fieldFilter: { field: { fieldPath: 'day' }, op: 'GREATER_THAN_OR_EQUAL', value: field(mondayOf(last)) } },
      { fieldFilter: { field: { fieldPath: 'day' }, op: 'LESS_THAN_OR_EQUAL', value: field(sundayOf(last)) } },
    ] } }, ['userId', 'username', 'day', 'correct', 'scoreMs', 'suspended'], 5000);
    const winner = weekWinner(results);
    Object.assign(update, { weekIndex: last, weekMonday: mondayOf(last), weekUid: winner?.uid ?? '', weekName: winner?.name ?? '',
      weekFound: winner?.found ?? 0, weekTimeMs: winner?.timeMs ?? 0 });
    console.log(`Semaine du ${mondayOf(last)} : ${results.length} résultats, ${winner ? 'un numéro 1' : 'personne'}.`);
  }

  // The last tournament over: this week's once its final has ended, otherwise last week's.
  const thisWeek = lastStartedWeek(now);
  for (const week of [thisWeek, new Date(tournamentStart(thisWeek) - 7 * DAY).toISOString().slice(0, 10)]) {
    const total = rounds(await count(token, `tournaments/${week}`, 'players'), week);
    if (!total) continue;
    const endMs = tournamentStart(week) + total * DAY;
    if (now < endMs) continue;
    if (state.tournamentWeek === week || state.tournamentChecked === week) break;
    const runs = async (round) => query(token, `tournaments/${week}`, 'runs', eq('round', round));
    const finalRuns = await runs(total);
    const semiRuns = total > 1 ? await runs(total - 1) : [];
    const uid = finalWinner({ total, finalRuns, semiRuns, endMs, byesBefore: week < EVERYONE_PLAYS_FROM });
    if (uid) {
      const player = plain(await firestore(token, `/tournaments/${week}/players/${uid}`));
      Object.assign(update, { tournamentWeek: week, tournamentUid: uid, tournamentName: player.name ?? 'Joueur' });
      console.log(`Tournoi du ${week} : vainqueur trouvé.`);
    } else {
      // Nobody played the final: the previous winner keeps the crown.
      console.log(`Tournoi du ${week} : finale sans vainqueur.`);
    }
    update.tournamentChecked = week;
    break;
  }

  if (!Object.keys(update).length) { console.log('Rien de nouveau.'); return { update, written: false }; }
  if (dryRun) { console.log('Essai à blanc : rien écrit.'); return { update, written: false }; }
  update.updatedAt = new Date(now).toISOString();
  const fields = Object.fromEntries(Object.entries(update).map(([k, v]) => [k, k === 'updatedAt' ? { timestampValue: v } : field(v)]));
  await firestore(token, `/${DOC}?${Object.keys(fields).map((f) => `updateMask.fieldPaths=${f}`).join('&')}`, { method: 'PATCH', body: JSON.stringify({ fields }) });
  console.log('Couronnes mises à jour.');
  return { update, written: true };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    await run({ dryRun: process.argv.includes('--dry-run') });
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
