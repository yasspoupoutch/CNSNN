import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import * as fs from 'firebase/firestore';
import { legacySprintRecord, sprintRank } from '../tools/sprint.mjs';

const { doc, setDoc, updateDoc, getDoc, getDocs, deleteDoc, collection, query, orderBy, limit, serverTimestamp, Timestamp, deleteField } = fs;
let env;
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-cnsnn-sprint', firestore: { rules: readFileSync('firestore.rules', 'utf8') } }); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const user = (uid, claims = {}) => env.authenticatedContext(uid, claims).firestore();
const seed = (path, data) => env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), path), data); });
const read = async (path) => { let d; await env.withSecurityRulesDisabled(async (c) => { d = (await getDoc(doc(c.firestore(), path))).data(); }); return d; };
const ago = (ms) => Timestamp.fromMillis(Date.now() - ms);

async function players() {
  await seed('users/alice', { uid: 'alice', username: 'Alice' });
  await seed('users/bob', { uid: 'bob', username: 'Bob' });
}
/** A game started `ms` ago, as the server saw it. */
async function startedAgo(uid, ms) {
  const startedAt = ago(ms);
  await seed(`sprintRuns/${uid}`, { startedAt });
  return startedAt;
}
const line = (uid, username, best, startedAt, over = {}) =>
  ({ uid, username, best, rank: sprintRank(best, startedAt.toMillis()), startedAt, at: serverTimestamp(), ...over });

test('a game starts at the server time, on the player\'s own run only', async () => {
  await players();
  await assertSucceeds(setDoc(doc(user('alice'), 'sprintRuns/alice'), { startedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(user('alice'), 'sprintRuns/alice'), { startedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(user('alice'), 'sprintRuns/alice'), { startedAt: ago(60000) }));
  await assertFails(setDoc(doc(user('alice'), 'sprintRuns/alice'), { startedAt: serverTimestamp(), found: 3 }));
  await assertFails(setDoc(doc(user('bob'), 'sprintRuns/alice'), { startedAt: serverTimestamp() }));
  await assertFails(getDoc(doc(user('bob'), 'sprintRuns/alice')));
  await assertSucceeds(getDoc(doc(user('alice'), 'sprintRuns/alice')));
});

test('a record comes from the game just played: a second per word, within 150 s', async () => {
  await players();
  const db = user('alice');
  // Too fast: 30 words in 20 s.
  let start = await startedAgo('alice', 20000);
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 30, start)));
  // Too late: the game started 3 minutes ago.
  start = await startedAgo('alice', 180000);
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 12, start)));
  // Not this game's start, a wrong rank, another name, too many words, someone else's line.
  start = await startedAgo('alice', 92000);
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 12, ago(91000))));
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 12, start, { rank: sprintRank(13, start.toMillis()) })));
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alicia', 12, start)));
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 61, start)));
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 0, start)));
  await assertFails(setDoc(doc(user('bob'), 'sprintRecords/alice'), line('alice', 'Alice', 12, start)));
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 12, start, { legacy: true })));
  await assertSucceeds(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 12, start)));
  // The same game cannot be counted twice, and a lower or equal score never replaces the record.
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 13, start)));
  start = await startedAgo('alice', 95000);
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 12, start)));
  await assertSucceeds(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 15, start)));
  assert.equal((await read('sprintRecords/alice')).best, 15);
});

test('an imported old record is beaten only by a checked game', async () => {
  await players();
  const old = Timestamp.fromMillis(Date.parse('2026-10-20T12:00:00Z'));
  await seed('sprintRecords/alice', { uid: 'alice', username: 'Alice', best: 20, rank: sprintRank(20, old.toMillis()), startedAt: old, at: old });
  const db = user('alice');
  await assertFails(updateDoc(doc(db, 'sprintRecords/alice'), { best: 40 }));
  let start = await startedAgo('alice', 91000);
  await assertFails(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 18, start)));
  await assertSucceeds(setDoc(doc(db, 'sprintRecords/alice'), line('alice', 'Alice', 21, start)));
});

test('everyone signed in reads the top 10 on one field; a rename follows the profile only', async () => {
  await players();
  let start = await startedAgo('alice', 91000);
  await assertSucceeds(setDoc(doc(user('alice'), 'sprintRecords/alice'), line('alice', 'Alice', 14, start)));
  start = await startedAgo('bob', 91000);
  await assertSucceeds(setDoc(doc(user('bob'), 'sprintRecords/bob'), line('bob', 'Bob', 22, start)));
  const top = await getDocs(query(collection(user('alice'), 'sprintRecords'), orderBy('rank', 'desc'), limit(15)));
  assert.deepEqual(top.docs.map((d) => d.id), ['bob', 'alice']);
  await assertFails(getDocs(query(collection(env.unauthenticatedContext().firestore(), 'sprintRecords'), orderBy('rank', 'desc'), limit(15))));
  await assertFails(updateDoc(doc(user('alice'), 'sprintRecords/alice'), { username: 'Zorro' }));
  await seed('users/alice', { uid: 'alice', username: 'Alicia' });
  await assertSucceeds(updateDoc(doc(user('alice'), 'sprintRecords/alice'), { username: 'Alicia' }));
  await assertFails(updateDoc(doc(user('alice'), 'sprintRecords/alice'), { username: 'Alicia', best: 50 }));
});

test('a suspended player cannot play ranked; a moderator hides and shows the line; the owner deletes it', async () => {
  await players();
  const start = await startedAgo('alice', 91000);
  await assertSucceeds(setDoc(doc(user('alice'), 'sprintRecords/alice'), line('alice', 'Alice', 14, start)));
  await seed('banned/alice', { username: 'Alice', reason: 'Triche' });
  await assertFails(setDoc(doc(user('alice'), 'sprintRuns/alice'), { startedAt: serverTimestamp() }));
  const mod = user('mod', { admin: true });
  await assertFails(updateDoc(doc(user('bob'), 'sprintRecords/alice'), { suspended: true }));
  await assertFails(updateDoc(doc(mod, 'sprintRecords/alice'), { best: 1 }));
  await assertSucceeds(updateDoc(doc(mod, 'sprintRecords/alice'), { suspended: true }));
  await assertSucceeds(updateDoc(doc(mod, 'sprintRecords/alice'), { suspended: deleteField() }));
  await assertFails(deleteDoc(doc(user('bob'), 'sprintRecords/alice')));
  await assertSucceeds(deleteDoc(doc(user('alice'), 'sprintRecords/alice')));
  await assertSucceeds(deleteDoc(doc(user('alice'), 'sprintRuns/alice')));
});

test('old records are read from the synced progress, at most 60 words', () => {
  const json = (words) => JSON.stringify({ username: 'Alice', modes: { sprint: { best: { words, combo: 4 }, counts: {} } } });
  assert.deepEqual(legacySprintRecord('alice', 'Alice', json(17), 1000), { uid: 'alice', username: 'Alice', best: 17, rank: sprintRank(17, 1000), startedAtMs: 1000 });
  assert.equal(legacySprintRecord('alice', 'Alice', json(250), 1000).best, 60);
  assert.equal(legacySprintRecord('alice', 'Alice', json(0), 1000), null);
  assert.equal(legacySprintRecord('alice', 'Alice', JSON.stringify({ modes: {} }), 1000), null);
  assert.equal(legacySprintRecord('alice', 'Alice', 'not json', 1000), null);
  assert.equal(legacySprintRecord('alice', undefined, json(5), 1000), null);
  assert.equal(sprintRank(17, 1000), 179999999998999);
  // More words first, then the earlier game.
  assert.ok(sprintRank(18, 5000) > sprintRank(17, 1000));
  assert.ok(sprintRank(17, 1000) > sprintRank(17, 5000));
});
