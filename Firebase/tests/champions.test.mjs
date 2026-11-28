// The crowns (tools/champions.mjs): last week's number 1 and the last tournament's winner, run against the emulator.
import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, Timestamp } from 'firebase/firestore';

const PROJECT = 'demo-cnsnn-champions';
let env, tool;
before(async () => {
  env = await initializeTestEnvironment({ projectId: PROJECT, firestore: { rules: readFileSync('firestore.rules', 'utf8') } });
  tool = await import('../tools/champions.mjs');
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const seed = (path, data) => env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), path), data));
const read = async (path) => { let d; await env.withSecurityRulesDisabled(async (c) => { d = (await getDoc(doc(c.firestore(), path))).data(); }); return d; };
const DAY = 86_400_000;

test('pure helpers: weeks, number 1, rounds, final', () => {
  assert.equal(tool.mondayOf(tool.weekIndex('2026-11-25')), '2026-11-23');
  assert.equal(tool.sundayOf(tool.weekIndex('2026-11-25')), '2026-11-29');
  const w = tool.weekWinner([
    { userId: 'a', username: 'Ana', day: '2026-11-16', correct: true, scoreMs: 50_000 },
    { userId: 'a', username: 'Anna', day: '2026-11-17', correct: true, scoreMs: 50_000 },
    { userId: 'b', username: 'Bob', day: '2026-11-16', correct: true, scoreMs: 30_000 },
    { userId: 'b', username: 'Bob', day: '2026-11-17', correct: true, scoreMs: 40_000 },
    { userId: 'c', username: 'Cy', day: '2026-11-16', correct: true, scoreMs: 1_000, suspended: true },
    { userId: 'c', username: 'Cy', day: '2026-11-17', correct: true, scoreMs: 1_000, suspended: true },
    { userId: 'd', username: 'Dé', day: '2026-11-16', correct: false, scoreMs: 600_000 },
  ]);
  assert.deepEqual(w, { uid: 'b', name: 'Bob', found: 2, timeMs: 70_000 });
  assert.equal(tool.weekWinner([{ userId: 'x', correct: false }]), null);
  assert.deepEqual([2, 3, 10, 64, 200].map((n) => tool.rounds(n, '2026-12-07')), [1, 1, 3, 6, 6]);
  assert.deepEqual([2, 3, 10].map((n) => tool.rounds(n, '2026-11-16')), [1, 2, 4]);
  assert.equal(tool.lastStartedWeek(Date.parse('2026-11-23T07:59:00Z')), '2026-11-16');
  assert.equal(tool.lastStartedWeek(Date.parse('2026-11-23T08:00:00Z')), '2026-11-23');
  const run = (uid, round, s, f, extra = {}) => ({ uid, round, startedAt: s, finishedAt: f, ...extra });
  // Only finalists count (a run in the round before), finished in time; the best time wins.
  assert.equal(tool.finalWinner({ total: 3, endMs: 1000, byesBefore: false,
    finalRuns: [run('a', 3, 0, 100), run('b', 3, 0, 90, { skips: 1 }), run('x', 3, 0, 10), run('c', 3, 0, 2000)],
    semiRuns: [run('a', 2, 0, 1), run('b', 2, 0, 1), run('c', 2, 0, 1)] }), 'a');
  assert.equal(tool.finalWinner({ total: 2, endMs: 1000, byesBefore: false, finalRuns: [], semiRuns: [] }), null);
});

test('rules: every player reads the crowns, nobody writes them', async () => {
  await seed('meta/champions', { weekUid: 'b' });
  const a = env.authenticatedContext('alice').firestore();
  await assertSucceeds(getDoc(doc(a, 'meta/champions')));
  await assertFails(setDoc(doc(a, 'meta/champions'), { weekUid: 'alice' }));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'meta/champions')));
});

test('writes last week\'s number 1 and the last tournament\'s winner, once', async () => {
  // Wednesday 2 Dec 2026, 12:00 UTC: last week is 23-29 Nov; the tournament of 23 Nov (3 players,
  // old format: 2 rounds) ended on Wednesday 25 Nov at 08:00 UTC.
  const now = Date.parse('2026-12-02T12:00:00Z');
  await seed('dailyResults/a_2026-11-23', { userId: 'a', username: 'Ana', day: '2026-11-23', correct: true, scoreMs: 40_000 });
  await seed('dailyResults/b_2026-11-24', { userId: 'b', username: 'Bob', day: '2026-11-24', correct: true, scoreMs: 30_000 });
  await seed('dailyResults/b_2026-11-30', { userId: 'b', username: 'Bob', day: '2026-11-30', correct: true, scoreMs: 30_000 });
  await seed('dailyResults/a_2026-11-16', { userId: 'a', username: 'Ana', day: '2026-11-16', correct: true, scoreMs: 1_000 });
  const week = '2026-11-23', start = Date.parse(week + 'T08:00:00Z');
  for (const [uid, name] of [['a', 'Ana'], ['b', 'Bob'], ['c', 'Cy']]) await seed(`tournaments/${week}/players/${uid}`, { uid, name, at: Timestamp.fromMillis(start - 1000) });
  const t = (ms) => Timestamp.fromMillis(ms);
  await seed(`tournaments/${week}/runs/1_a`, { uid: 'a', round: 1, startedAt: t(start + 10), finishedAt: t(start + 50_000), skips: 0, errors: 0 });
  await seed(`tournaments/${week}/runs/1_b`, { uid: 'b', round: 1, startedAt: t(start + 10), finishedAt: t(start + 60_000), skips: 0, errors: 0 });
  await seed(`tournaments/${week}/runs/2_a`, { uid: 'a', round: 2, startedAt: t(start + DAY), finishedAt: t(start + DAY + 70_000), skips: 0, errors: 0 });
  await seed(`tournaments/${week}/runs/2_c`, { uid: 'c', round: 2, startedAt: t(start + DAY), finishedAt: t(start + DAY + 40_000), skips: 0, errors: 0 });
  const r = await tool.run({ project: PROJECT, now });
  assert.equal(r.written, true);
  const d = await read('meta/champions');
  assert.equal(d.weekMonday, '2026-11-23');
  assert.equal(d.weekUid, 'b'); // 1 word each that week: Bob was faster (his Monday 30 Nov is next week)
  assert.equal(d.tournamentWeek, week);
  assert.equal(d.tournamentName, 'Cy');
  // Nothing new the next time.
  assert.equal((await tool.run({ project: PROJECT, now: now + 3_600_000 })).written, false);
});
