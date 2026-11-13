import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import * as fs from 'firebase/firestore';
import { deleteAccountData } from '../hosting/account.mjs';

const { doc, setDoc, updateDoc, getDoc, getDocs, deleteDoc, collection, serverTimestamp, Timestamp, writeBatch } = fs;
let env;
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-cnsnn-tournaments', firestore: { rules: readFileSync('firestore.rules', 'utf8') } }); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const user = (uid) => env.authenticatedContext(uid).firestore();
const seed = (path, data) => env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), path), data); });
const patch = (path, data) => env.withSecurityRulesDisabled(async (c) => { await updateDoc(doc(c.firestore(), path), data); });
const read = async (path) => { let d; await env.withSecurityRulesDisabled(async (c) => { d = (await getDoc(doc(c.firestore(), path))).data(); }); return d; };
const cards = ['CLAFOUTIS', 'GIRAFE', 'PARAPLUIE', 'MARSEILLE', 'TITANIC'];
const DAY = 86_400_000;
// Same calendar as Core/Tournament.swift: a week is its Monday, sign-ups close at 08:00 UTC.
const iso = (ms) => new Date(ms).toISOString().slice(0, 10);
function nextWeek(now = Date.now()) {
  const day = Math.floor((now - 8 * 3_600_000) / DAY);
  let monday = day - (((day + 3) % 7) + 7) % 7;
  if (monday * DAY + 8 * 3_600_000 <= now) monday += 7;
  return iso(monday * DAY);
}
const start = (week) => Date.parse(week + 'T08:00:00Z');
const upcoming = nextWeek();
const current = iso(start(upcoming) - 7 * DAY);
// The round open now in the current tournament (none from Sunday 08:00 to Monday 08:00 UTC).
const openRound = (() => { const r = Math.floor((Date.now() - start(current)) / DAY) + 1; return r >= 1 && r <= 6 ? r : null; })();

async function players() {
  await seed('users/alice', { uid: 'alice', username: 'Alice' });
  await seed('users/bob', { uid: 'bob', username: 'Bob' });
}
const signUp = (uid, name, over = {}) => ({ uid, name, at: serverTimestamp(), ...over });

test('sign-ups: own place, real name, server time, only before Monday 08:00 UTC', async () => {
  await players();
  const a = user('alice');
  await assertFails(setDoc(doc(a, `tournaments/${upcoming}/players/bob`), signUp('bob', 'Bob')));
  await assertFails(setDoc(doc(a, `tournaments/${upcoming}/players/alice`), signUp('alice', 'Alicia')));
  await assertFails(setDoc(doc(a, `tournaments/${upcoming}/players/alice`), signUp('alice', 'Alice', { at: Timestamp.now() })));
  // Not a Monday, already started, or not open yet.
  await assertFails(setDoc(doc(a, `tournaments/${iso(start(upcoming) + DAY)}/players/alice`), signUp('alice', 'Alice')));
  await assertFails(setDoc(doc(a, `tournaments/${current}/players/alice`), signUp('alice', 'Alice')));
  await assertFails(setDoc(doc(a, `tournaments/${iso(start(upcoming) + 7 * DAY)}/players/alice`), signUp('alice', 'Alice')));
  await assertSucceeds(setDoc(doc(a, `tournaments/${upcoming}/players/alice`), signUp('alice', 'Alice')));
  // Everyone sees who signed up; withdrawing is possible before the draw.
  assert.equal((await getDocs(collection(user('bob'), `tournaments/${upcoming}/players`))).size, 1);
  await assertFails(deleteDoc(doc(user('bob'), `tournaments/${upcoming}/players/alice`)));
  await assertSucceeds(deleteDoc(doc(a, `tournaments/${upcoming}/players/alice`)));
  await seed('banned/bob', { username: 'Bob', reason: 'Test' });
  await assertFails(setDoc(doc(user('bob'), `tournaments/${upcoming}/players/bob`), signUp('bob', 'Bob')));
});

test('a round is played by players signed up, in its 24 hours, timed by the server', async () => {
  await players();
  await seed(`tournaments/${current}/players/alice`, { uid: 'alice', name: 'Alice', at: Timestamp.fromMillis(start(current) - DAY) });
  const a = user('alice'), b = user('bob');
  const r = openRound ?? 1;
  const run = (uid, round = r) => ({ uid, round, startedAt: serverTimestamp() });
  if (openRound == null) {
    // Sunday 08:00 to Monday 08:00 UTC: no round is open.
    await assertFails(setDoc(doc(a, `tournaments/${current}/runs/1_alice`), run('alice', 1)));
    return;
  }
  // Bob is not signed up; wrong id, round or time.
  await assertFails(setDoc(doc(b, `tournaments/${current}/runs/${r}_bob`), run('bob')));
  await assertFails(setDoc(doc(a, `tournaments/${current}/runs/${r}_bob`), run('alice')));
  await assertFails(setDoc(doc(a, `tournaments/${current}/runs/${r + 1}_alice`), run('alice', r + 1)));
  await assertFails(setDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), { ...run('alice'), startedAt: Timestamp.now() }));
  // The words: read only once one's own run has started; created once, valid.
  await assertFails(setDoc(doc(a, `tournaments/${current}/rounds/${r}`), { cardIds: cards.slice(0, 4), at: serverTimestamp() }));
  await assertFails(setDoc(doc(b, `tournaments/${current}/rounds/${r}`), { cardIds: cards, at: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(a, `tournaments/${current}/rounds/${r}`), { cardIds: cards, at: serverTimestamp() }));
  await assertFails(setDoc(doc(a, `tournaments/${current}/rounds/${r}`), { cardIds: cards, at: serverTimestamp() }));
  await assertFails(getDoc(doc(a, `tournaments/${current}/rounds/${r}`)));
  await assertSucceeds(setDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), run('alice')));
  await assertSucceeds(getDoc(doc(a, `tournaments/${current}/rounds/${r}`)));
  await assertFails(setDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), run('alice')));
  // Finish: once, server time, at least 2 s per word found (5 passes need no minimum).
  const finish = (skips = 0, errors = 0) => ({ finishedAt: serverTimestamp(), skips, errors });
  await assertFails(updateDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), finish()));
  await assertFails(updateDoc(doc(b, `tournaments/${current}/runs/${r}_alice`), finish(5)));
  await patch(`tournaments/${current}/runs/${r}_alice`, { startedAt: Timestamp.fromMillis(Date.now() - 30_000) });
  await assertFails(updateDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), finish(6)));
  await assertFails(updateDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), { ...finish(), startedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), finish(1, 2)));
  await assertFails(updateDoc(doc(a, `tournaments/${current}/runs/${r}_alice`), finish(0, 0)));
  // Everyone signed in reads the runs (the apps work out the bracket from them).
  assert.equal((await getDocs(collection(b, `tournaments/${current}/runs`))).size, 1);
});

test('a run started in an earlier round cannot be finished after its day', async () => {
  await players();
  if (openRound == null || openRound < 2) return;
  await seed(`tournaments/${current}/runs/1_alice`, { uid: 'alice', round: 1, startedAt: Timestamp.fromMillis(start(current) + 1000) });
  await assertFails(updateDoc(doc(user('alice'), `tournaments/${current}/runs/1_alice`), { finishedAt: serverTimestamp(), skips: 0, errors: 0 }));
});

test('deleting the account removes the sign-ups and runs, even blindly', async () => {
  await players();
  await seed(`tournaments/${current}/players/bob`, { uid: 'bob', name: 'Bob', at: Timestamp.fromMillis(start(current) - DAY) });
  await seed(`tournaments/${current}/runs/1_bob`, { uid: 'bob', round: 1, startedAt: Timestamp.fromMillis(start(current) + 1000) });
  await seed(`tournaments/${upcoming}/players/bob`, { uid: 'bob', name: 'Bob', at: Timestamp.now() });
  // Not while the account exists.
  await assertFails(deleteDoc(doc(user('bob'), `tournaments/${current}/runs/1_bob`)));
  await deleteAccountData(user('bob'), 'bob', fs);
  assert.equal(await read(`tournaments/${current}/players/bob`), undefined);
  assert.equal(await read(`tournaments/${current}/runs/1_bob`), undefined);
  assert.equal(await read(`tournaments/${upcoming}/players/bob`), undefined);
});
