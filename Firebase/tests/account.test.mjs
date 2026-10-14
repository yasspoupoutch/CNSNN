import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import * as fs from 'firebase/firestore';
import { deleteAccountData } from '../hosting/account.mjs';

const { doc, setDoc, getDoc, getDocs, collection, Timestamp } = fs;
let env;
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-cnsnn-account', firestore: { rules: readFileSync('firestore.rules', 'utf8') } }); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const seed = (path, data) => env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), path), data); });
const all = async (name) => { let docs; await env.withSecurityRulesDisabled(async (c) => { docs = (await getDocs(collection(c.firestore(), name))).docs.map((d) => ({ id: d.id, ...d.data() })); }); return docs; };
const card = (id, status) => ({ wordFull: 'Mot', wordNoVowels: 'MT', normalizedAnswer: id, hint: 'Un indice.', category: 'Général', difficulty: 'Facile', createdBy: 'alice', authorName: 'Alice', status, createdAt: Timestamp.now() });

// The web page (suppression.html) runs the same code under the real rules, signed in as the player.
test('web deletion: every document, 120 live cards anonymized, reports and suspension gone', async () => {
  const now = Timestamp.now(), day = '2026-10-15';
  await seed('users/alice', { uid: 'alice', username: 'Alice' });
  await seed('users/alice/private/progress', { json: '{}', schema: 1, updatedAt: now });
  await seed('users/alice/friends/bob', { username: 'Bob', addedAt: now });
  await seed('friendCodes/ABC234', { uid: 'alice', username: 'Alice', createdAt: now });
  await seed('leaderboard/alice', { uid: 'alice', username: 'Alice', points: 10 });
  await seed(`dailySessions/alice_${day}`, { userId: 'alice', day, cardId: 'x', startedAt: now, hintUsed: false });
  await seed(`dailyResults/alice_${day}`, { userId: 'alice', username: 'Alice', day, correct: true, timeMs: 9000, points: 100 });
  await seed('reports/alice_CHOCOLAT', { userId: 'alice', cardId: 'CHOCOLAT', reason: 'Indice faux.', status: 'pending' });
  await seed('playerReports/alice_bob', { userId: 'alice', playerId: 'bob', username: 'Bob', status: 'pending' });
  await seed('playerReports/bob_alice', { userId: 'bob', playerId: 'alice', username: 'Alice', status: 'pending' });
  await seed('banned/alice', { username: 'Alice', reason: 'Test' });
  await seed('cards/PENDING', card('PENDING', 'pending'));
  for (let i = 0; i < 120; i++) await seed(`cards/LIVE${i}`, card(`LIVE${i}`, 'approved'));
  await seed('users/bob', { uid: 'bob', username: 'Bob' });

  const result = await deleteAccountData(env.authenticatedContext('alice').firestore(), 'alice', fs);
  assert.equal(result.anonymizedCards, 120);
  for (const name of ['users', 'leaderboard', 'friendCodes', 'dailySessions', 'dailyResults', 'reports', 'playerReports', 'banned']) {
    assert.deepEqual((await all(name)).filter((d) => JSON.stringify(d).includes('alice') || JSON.stringify(d).includes('Alice')), [], name);
  }
  const cards = await all('cards');
  assert.equal(cards.length, 120);
  assert.ok(cards.every((c) => c.createdBy === 'deleted' && c.authorName === undefined));
  assert.equal((await all('deletedUsers'))[0].id, 'alice');
  let friends;
  await env.withSecurityRulesDisabled(async (c) => { friends = (await getDocs(collection(c.firestore(), 'users/alice/friends'))).size; });
  assert.equal(friends, 0);
  // Other players' data stays.
  assert.equal((await all('users')).length, 1);
});
test('web deletion refuses to act for someone else', async () => {
  await seed('users/alice', { uid: 'alice', username: 'Alice' });
  await assert.rejects(deleteAccountData(env.authenticatedContext('mallory').firestore(), 'alice', fs));
  let profile; await env.withSecurityRulesDisabled(async (c) => { profile = (await getDoc(doc(c.firestore(), 'users/alice'))).exists(); });
  assert.ok(profile);
});
