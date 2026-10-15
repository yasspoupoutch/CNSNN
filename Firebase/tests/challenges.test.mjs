import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import * as fs from 'firebase/firestore';
import { deleteAccountData } from '../hosting/account.mjs';

const { doc, setDoc, updateDoc, getDoc, getDocs, deleteDoc, collection, query, where, serverTimestamp, Timestamp, writeBatch } = fs;
let env;
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-cnsnn-challenges', firestore: { rules: readFileSync('firestore.rules', 'utf8') } }); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const user = (uid) => env.authenticatedContext(uid).firestore();
const seed = (path, data) => env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), path), data); });
const patch = (path, data) => env.withSecurityRulesDisabled(async (c) => { await updateDoc(doc(c.firestore(), path), data); });
const read = async (path) => { let d; await env.withSecurityRulesDisabled(async (c) => { d = (await getDoc(doc(c.firestore(), path))).data(); }); return d; };
const cards = ['CLAFOUTIS', 'GIRAFE', 'PARAPLUIE', 'MARSEILLE', 'TITANIC'];
const ago = (ms) => Timestamp.fromMillis(Date.now() - ms);

async function players() {
  const now = Timestamp.now();
  await seed('users/alice', { uid: 'alice', username: 'Alice' });
  await seed('users/bob', { uid: 'bob', username: 'Bob' });
  await seed('users/carol', { uid: 'carol', username: 'Carol' });
  await seed('users/alice/friends/bob', { username: 'Bob', addedAt: now });
}
const challenge = (over = {}) => ({ from: 'alice', fromName: 'Alice', to: 'bob', toName: 'Bob', cardIds: cards, createdAt: serverTimestamp(), fromStartedAt: serverTimestamp(), ...over });
const finish = (side, skips = 0, errors = 1) => ({ [`${side}FinishedAt`]: serverTimestamp(), [`${side}Skips`]: skips, [`${side}Errors`]: errors });

test('a challenge goes to a friend, under the real names, with 5 distinct words', async () => {
  await players();
  const db = user('alice');
  await assertSucceeds(setDoc(doc(db, 'challenges/c1'), challenge()));
  await assertFails(setDoc(doc(db, 'challenges/c2'), challenge({ to: 'carol', toName: 'Carol' })));
  await assertFails(setDoc(doc(db, 'challenges/c3'), challenge({ fromName: 'Alicia' })));
  await assertFails(setDoc(doc(db, 'challenges/c4'), challenge({ toName: 'Bobby' })));
  await assertFails(setDoc(doc(db, 'challenges/c5'), challenge({ cardIds: cards.slice(0, 4) })));
  await assertFails(setDoc(doc(db, 'challenges/c6'), challenge({ cardIds: [...cards.slice(0, 4), 'CLAFOUTIS'] })));
  await assertFails(setDoc(doc(db, 'challenges/c7'), challenge({ fromStartedAt: Timestamp.fromMillis(Date.now() - 60000) })));
  await assertFails(setDoc(doc(db, 'challenges/c8'), challenge({ fromFinishedAt: serverTimestamp() })));
  await assertFails(setDoc(doc(user('bob'), 'challenges/c9'), challenge()));
  await seed('banned/alice', { username: 'Alice', reason: 'Test' });
  await assertFails(setDoc(doc(db, 'challenges/c10'), challenge()));
});

test('only the two players read a challenge, and each lists their own', async () => {
  await players();
  await assertSucceeds(setDoc(doc(user('alice'), 'challenges/c1'), challenge()));
  await assertSucceeds(getDoc(doc(user('bob'), 'challenges/c1')));
  await assertFails(getDoc(doc(user('carol'), 'challenges/c1')));
  assert.equal((await getDocs(query(collection(user('alice'), 'challenges'), where('from', '==', 'alice')))).size, 1);
  assert.equal((await getDocs(query(collection(user('bob'), 'challenges'), where('to', '==', 'bob')))).size, 1);
  await assertFails(getDocs(query(collection(user('carol'), 'challenges'), where('to', '==', 'bob'))));
  await assertFails(getDocs(collection(user('carol'), 'challenges')));
});

test('each player finishes once, at the server time, no faster than 2 s per word found', async () => {
  await players();
  const a = user('alice'), b = user('bob');
  await assertSucceeds(setDoc(doc(a, 'challenges/c1'), challenge()));
  // Too fast for 5 words; but 5 skips need no minimum.
  await assertFails(updateDoc(doc(a, 'challenges/c1'), finish('from')));
  await patch('challenges/c1', { fromStartedAt: ago(30000) });
  await assertFails(updateDoc(doc(a, 'challenges/c1'), { ...finish('from'), fromFinishedAt: Timestamp.now() }));
  await assertFails(updateDoc(doc(a, 'challenges/c1'), finish('from', 6)));
  await assertFails(updateDoc(doc(a, 'challenges/c1'), { ...finish('from'), fromStartedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(b, 'challenges/c1'), finish('from')));
  await assertSucceeds(updateDoc(doc(a, 'challenges/c1'), finish('from', 1, 3)));
  await assertFails(updateDoc(doc(a, 'challenges/c1'), finish('from', 0, 0)));
  // Bob cannot finish before starting, starts once, then finishes.
  await assertFails(updateDoc(doc(b, 'challenges/c1'), finish('to')));
  await assertFails(updateDoc(doc(a, 'challenges/c1'), { toStartedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(b, 'challenges/c1'), { toStartedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(b, 'challenges/c1'), { toStartedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(b, 'challenges/c1'), finish('to', 0)));
  await assertSucceeds(updateDoc(doc(b, 'challenges/c1'), finish('to', 5, 0)));
  const c = await read('challenges/c1');
  assert.equal(c.fromSkips, 1); assert.equal(c.fromErrors, 3); assert.equal(c.toSkips, 5);
  assert.ok(c.toFinishedAt.toMillis() >= c.toStartedAt.toMillis());
});

test('the friend has 48 h to start and everyone 50 h to finish', async () => {
  await players();
  await seed('challenges/old', { ...challenge(), createdAt: ago(49 * 3600e3), fromStartedAt: ago(49 * 3600e3) });
  await assertFails(updateDoc(doc(user('bob'), 'challenges/old'), { toStartedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(user('alice'), 'challenges/old'), finish('from', 0, 0)));
  await seed('challenges/older', { ...challenge(), createdAt: ago(51 * 3600e3), fromStartedAt: ago(51 * 3600e3) });
  await assertFails(updateDoc(doc(user('alice'), 'challenges/older'), finish('from', 0, 0)));
});

test('challenges are deleted only with the account, by either player', async () => {
  await players();
  await assertSucceeds(setDoc(doc(user('alice'), 'challenges/c1'), challenge()));
  await assertFails(deleteDoc(doc(user('alice'), 'challenges/c1')));
  await assertFails(deleteDoc(doc(user('bob'), 'challenges/c1')));
  const db = user('bob'), batch = writeBatch(db);
  batch.delete(doc(db, 'users/bob')); batch.delete(doc(db, 'challenges/c1'));
  await assertSucceeds(batch.commit());
});

test('web deletion removes the challenges sent and received', async () => {
  await players();
  await seed('users/carol/friends/alice', { username: 'Alice', addedAt: Timestamp.now() });
  await assertSucceeds(setDoc(doc(user('alice'), 'challenges/sent'), challenge()));
  await assertSucceeds(setDoc(doc(user('carol'), 'challenges/received'), challenge({ from: 'carol', fromName: 'Carol', to: 'alice', toName: 'Alice' })));
  await assertSucceeds(setDoc(doc(user('carol'), 'challenges/other'), { ...challenge({ from: 'carol', fromName: 'Carol', to: 'alice', toName: 'Alice' }) }).then(() => patch('challenges/other', { to: 'bob', toName: 'Bob' })));
  await deleteAccountData(user('alice'), 'alice', fs);
  let left;
  await env.withSecurityRulesDisabled(async (c) => { left = (await getDocs(collection(c.firestore(), 'challenges'))).docs.map((d) => d.id); });
  assert.deepEqual(left, ['other']);
});
