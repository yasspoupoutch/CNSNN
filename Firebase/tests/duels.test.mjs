import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import * as fs from 'firebase/firestore';
import { deleteAccountData } from '../hosting/account.mjs';

const { doc, setDoc, updateDoc, getDoc, getDocs, deleteDoc, collection, query, where, serverTimestamp, Timestamp, writeBatch, deleteField } = fs;
let env;
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-cnsnn-duels', firestore: { rules: readFileSync('firestore.rules', 'utf8') } }); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const user = (uid) => env.authenticatedContext(uid).firestore();
const seed = (path, data) => env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), path), data); });
const patch = (path, data) => env.withSecurityRulesDisabled(async (c) => { await updateDoc(doc(c.firestore(), path), data); });
const read = async (path) => { let d; await env.withSecurityRulesDisabled(async (c) => { d = (await getDoc(doc(c.firestore(), path))).data(); }); return d; };
const cards = ['CLAFOUTIS', 'GIRAFE', 'PARAPLUIE', 'MARSEILLE', 'TITANIC'];
const ago = (ms) => Timestamp.fromMillis(Date.now() - ms);

async function players() {
  await seed('users/alice', { uid: 'alice', username: 'Alice' });
  await seed('users/bob', { uid: 'bob', username: 'Bob' });
  await seed('users/carol', { uid: 'carol', username: 'Carol' });
}
const linkDuel = (over = {}) => ({ from: 'alice', fromName: 'Alice', to: '', toName: '', code: 'ABC234', cardIds: cards, createdAt: serverTimestamp(), ...over });
function createLink(db, id = 'd1', duel = linkDuel(), invite = { duel: id, from: 'alice', createdAt: serverTimestamp() }) {
  const batch = writeBatch(db);
  batch.set(doc(db, `duels/${id}`), duel);
  batch.set(doc(db, `challengeInvites/${duel.code ?? 'ABC234'}`), invite);
  return batch.commit();
}
const join = (over = {}) => ({ to: 'bob', toName: 'Bob', readyAt: serverTimestamp(), ...over });
// A duel already started 30 s ago between Alice and Bob.
async function started() {
  await players();
  await seed('duels/d1', { from: 'alice', fromName: 'Alice', to: 'bob', toName: 'Bob', code: 'ABC234', cardIds: cards, createdAt: ago(40000), readyAt: ago(35000) });
}
const move = (side, done, skips = 0, last = false) => ({ [`${side}Done`]: done, [`${side}Skips`]: skips, ...(last ? { [`${side}FinishedAt`]: serverTimestamp() } : {}) });

test('a duel by link is created with its invite, under the real name, and joined once within 15 min', async () => {
  await players();
  const a = user('alice'), b = user('bob'), c = user('carol');
  await assertFails(setDoc(doc(a, 'duels/d0'), linkDuel()));
  await assertFails(createLink(a, 'd0', linkDuel({ fromName: 'Alicia' })));
  await assertFails(createLink(a, 'd0', linkDuel({ readyAt: serverTimestamp() })));
  await assertFails(createLink(b, 'd0'));
  await assertSucceeds(createLink(a));
  // Anyone signed in may open it and its invite; the first one joins, under their own name.
  assert.equal((await getDoc(doc(c, 'challengeInvites/ABC234'))).data().duel, 'd1');
  await assertSucceeds(getDoc(doc(c, 'duels/d1')));
  await assertFails(updateDoc(doc(a, 'duels/d1'), join({ to: 'alice', toName: 'Alice' })));
  await assertFails(updateDoc(doc(b, 'duels/d1'), join({ toName: 'Bobby' })));
  await assertFails(updateDoc(doc(b, 'duels/d1'), join({ readyAt: Timestamp.now() })));
  await assertFails(updateDoc(doc(b, 'duels/d1'), join({ bobDone: 5 })));
  await assertSucceeds(updateDoc(doc(b, 'duels/d1'), join()));
  await assertFails(updateDoc(doc(c, 'duels/d1'), join({ to: 'carol', toName: 'Carol' })));
  await assertFails(getDoc(doc(c, 'duels/d1')));
  assert.equal((await read('duels/d1')).to, 'bob');
  // Too late.
  await assertSucceeds(createLink(a, 'd2', linkDuel({ code: 'XYZ234' }), { duel: 'd2', from: 'alice', createdAt: serverTimestamp() }));
  await patch('duels/d2', { createdAt: ago(16 * 60000) });
  await assertFails(updateDoc(doc(b, 'duels/d2'), join()));
});

test('a link nobody joined can be withdrawn by its author only', async () => {
  await players();
  await assertSucceeds(createLink(user('alice')));
  await assertFails(deleteDoc(doc(user('bob'), 'duels/d1')));
  await assertSucceeds(deleteDoc(doc(user('alice'), 'duels/d1')));
  await started();
  await assertFails(deleteDoc(doc(user('alice'), 'duels/d1')));
});

test('each player moves one word at a time and finishes at the server time', async () => {
  await started();
  const a = user('alice'), b = user('bob');
  await assertFails(updateDoc(doc(b, 'duels/d1'), move('from', 1)));
  await assertFails(updateDoc(doc(a, 'duels/d1'), move('from', 2)));
  await assertSucceeds(updateDoc(doc(a, 'duels/d1'), move('from', 1)));
  await assertFails(updateDoc(doc(a, 'duels/d1'), move('from', 2, 2)));
  await assertSucceeds(updateDoc(doc(a, 'duels/d1'), move('from', 2, 1)));
  await assertSucceeds(updateDoc(doc(a, 'duels/d1'), move('from', 3, 1)));
  await assertSucceeds(updateDoc(doc(a, 'duels/d1'), move('from', 4, 1)));
  // The 5th word is the finish, stamped by the server.
  await assertFails(updateDoc(doc(a, 'duels/d1'), move('from', 5, 1)));
  await assertFails(updateDoc(doc(a, 'duels/d1'), { ...move('from', 5, 1), fromFinishedAt: Timestamp.now() }));
  await assertFails(updateDoc(doc(a, 'duels/d1'), { ...move('from', 4, 1, true) }));
  await assertSucceeds(updateDoc(doc(a, 'duels/d1'), move('from', 5, 1, true)));
  await assertFails(updateDoc(doc(a, 'duels/d1'), move('from', 6, 1)));
  await assertFails(updateDoc(doc(a, 'duels/d1'), { fromQuit: true }));
  // Bob plays his own side only.
  await assertFails(updateDoc(doc(b, 'duels/d1'), { ...move('to', 1), fromDone: 4 }));
  await assertSucceeds(updateDoc(doc(b, 'duels/d1'), move('to', 1)));
});

test('nothing moves before the start, after 11 minutes, or too fast', async () => {
  await players();
  await seed('duels/d1', { from: 'alice', fromName: 'Alice', to: 'bob', toName: 'Bob', code: 'ABC234', cardIds: cards, createdAt: ago(1000), readyAt: ago(1000) });
  await assertFails(updateDoc(doc(user('alice'), 'duels/d1'), move('from', 1)));
  await patch('duels/d1', { readyAt: ago(12 * 60000) });
  await assertFails(updateDoc(doc(user('alice'), 'duels/d1'), move('from', 1)));
  // 5 words found in 4 s: too fast. 5 passed: no minimum.
  await patch('duels/d1', { readyAt: ago(9000), fromDone: 4, fromSkips: 0, toDone: 4, toSkips: 4 });
  await assertFails(updateDoc(doc(user('alice'), 'duels/d1'), move('from', 5, 0, true)));
  await assertSucceeds(updateDoc(doc(user('bob'), 'duels/d1'), move('to', 5, 5, true)));
});

test('leaving is final and only before finishing', async () => {
  await started();
  await assertFails(updateDoc(doc(user('alice'), 'duels/d1'), { toQuit: true }));
  await assertFails(updateDoc(doc(user('alice'), 'duels/d1'), { fromQuit: false }));
  await assertSucceeds(updateDoc(doc(user('alice'), 'duels/d1'), { fromQuit: true }));
  await assertFails(updateDoc(doc(user('alice'), 'duels/d1'), move('from', 1)));
  await assertFails(updateDoc(doc(user('alice'), 'duels/d1'), { fromQuit: deleteField() }));
});

test('a random opponent is taken from the waiting line, once, in one batch', async () => {
  await players();
  const a = user('alice'), b = user('bob'), c = user('carol');
  // A place: own, real name, server time, no duel.
  await assertFails(setDoc(doc(a, 'duelQueue/bob'), { name: 'Bob', at: serverTimestamp(), duel: '' }));
  await assertFails(setDoc(doc(b, 'duelQueue/bob'), { name: 'Bobby', at: serverTimestamp(), duel: '' }));
  await assertFails(setDoc(doc(b, 'duelQueue/bob'), { name: 'Bob', at: ago(1000), duel: '' }));
  await assertSucceeds(setDoc(doc(b, 'duelQueue/bob'), { name: 'Bob', at: serverTimestamp(), duel: '' }));
  assert.equal((await getDocs(query(collection(c, 'duelQueue'), where('at', '>', ago(60000))))).size, 1);
  const random = (over = {}) => ({ from: 'alice', fromName: 'Alice', to: 'bob', toName: 'Bob', random: true, cardIds: cards, createdAt: serverTimestamp(), readyAt: serverTimestamp(), ...over });
  const take = (db, id, duel, place = 'bob', also) => {
    const batch = writeBatch(db);
    batch.set(doc(db, `duels/${id}`), duel);
    batch.update(doc(db, `duelQueue/${place}`), { duel: id });
    if (also) also(batch);
    return batch.commit();
  };
  // The duel and the place go together, under the waiting player's name.
  await assertFails(setDoc(doc(a, 'duels/r1'), random()));
  await assertFails(updateDoc(doc(a, 'duelQueue/bob'), { duel: 'r1' }));
  await assertFails(take(a, 'r1', random({ toName: 'Bobby' })));
  await assertFails(take(a, 'r1', random({ readyAt: Timestamp.now() })));
  await assertFails(take(c, 'r1', random()));
  // Someone also waiting in the line cannot take: they would take each other.
  await assertSucceeds(setDoc(doc(a, 'duelQueue/alice'), { name: 'Alice', at: serverTimestamp(), duel: '' }));
  await assertFails(take(a, 'r1', random()));
  await assertSucceeds(take(a, 'r1', random(), 'bob', (batch) => batch.delete(doc(a, 'duelQueue/alice'))));
  assert.equal((await read('duelQueue/bob')).duel, 'r1');
  // Taken: nobody else can take it.
  await assertFails(take(c, 'r2', random({ from: 'carol', fromName: 'Carol' })));
  // An old place (closed app) cannot be taken.
  await assertSucceeds(setDoc(doc(c, 'duelQueue/carol'), { name: 'Carol', at: serverTimestamp(), duel: '' }));
  await patch('duelQueue/carol', { at: ago(120000) });
  await assertFails(take(a, 'r3', random({ to: 'carol', toName: 'Carol' }), 'carol'));
  // The players play it as any duel.
  await assertSucceeds(getDoc(doc(b, 'duels/r1')));
  await assertFails(getDoc(doc(c, 'duels/r1')));
  await assertSucceeds(deleteDoc(doc(b, 'duelQueue/bob')));
  await assertFails(deleteDoc(doc(c, 'duelQueue/bob')));
});

test('web deletion removes the duels and the waiting place', async () => {
  await started();
  await seed('duelQueue/bob', { name: 'Bob', at: Timestamp.now(), duel: '' });
  const db = user('bob');
  await deleteAccountData(db, 'bob', fs);
  assert.equal(await read('duels/d1'), undefined);
  assert.equal(await read('duelQueue/bob'), undefined);
});
