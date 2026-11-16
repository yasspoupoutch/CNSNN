// Push alert for new pseudos (tools/new-pseudos.mjs), run against the emulator with a fake ntfy server.
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, Timestamp } from 'firebase/firestore';

const PROJECT = 'demo-cnsnn-pseudos';
let env, server, sent = [], run, message;

before(async () => {
  env = await initializeTestEnvironment({ projectId: PROJECT, firestore: { rules: readFileSync('firestore.rules', 'utf8') } });
  server = createServer((req, res) => {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => { sent.push(JSON.parse(body)); res.end('{}'); });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  process.env.NTFY_URL = `http://127.0.0.1:${server.address().port}/`;
  ({ run, message } = await import('../tools/new-pseudos.mjs'));
});
after(async () => { await env?.cleanup(); server?.close(); });
beforeEach(async () => { await env.clearFirestore(); sent = []; });

const now = Date.parse('2026-11-16T14:00:00Z');
const at = (min) => Timestamp.fromMillis(now + min * 60_000);
const player = (uid, username, min) => env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), `users/${uid}`), { uid, username, createdAt: at(min) }));
const lastCheck = (min) => env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'ops/newPseudos'), { lastCheck: at(min) }));
const opts = (o = {}) => ({ project: PROJECT, topic: 'sujet-test', now, ...o });

test('announces only the pseudos created since the last check, then moves the check time', async () => {
  await player('a', 'Ancien', -200);
  await player('b', 'Bilou', -100);
  await player('c', 'Sara', -30);
  await lastCheck(-120);
  const r = await run(opts());
  assert.deepEqual(r.pseudos.map((p) => p.pseudo), ['Bilou', 'Sara']);
  assert.equal(r.total, 3);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].topic, 'sujet-test');
  assert.equal(sent[0].title, 'CNSNN : 2 nouveaux pseudos');
  assert.match(sent[0].message, /Bilou \(lun\. 13:20\)/);
  assert.match(sent[0].message, /Total : 3 joueurs/);

  // Next run: nothing new, nothing sent.
  const again = await run(opts({ now: now + 120 * 60_000 }));
  assert.equal(again.pseudos.length, 0);
  assert.equal(sent.length, 1);
});

test('a pseudo created in the last minute waits for the next run', async () => {
  await lastCheck(-120);
  await player('d', 'Tardif', -0.5);
  assert.equal((await run(opts())).pseudos.length, 0);
  assert.equal((await run(opts({ now: now + 120 * 60_000 }))).pseudos[0].pseudo, 'Tardif');
});

test('first run looks back 24 h; test mode sends even with nothing new; dry run saves nothing', async () => {
  await player('e', 'Hier', -25 * 60);
  const dry = await run(opts({ dryRun: true }));
  assert.equal(dry.pseudos.length, 0);
  assert.equal(sent.length, 0);
  let saved;
  await env.withSecurityRulesDisabled(async (c) => { saved = (await getDoc(doc(c.firestore(), 'ops/newPseudos'))).exists(); });
  assert.equal(saved, false);

  await run(opts({ test: true }));
  assert.equal(sent.length, 1);
  assert.equal(sent[0].title, 'CNSNN : alerte pseudos activée ✅');
  assert.match(sent[0].message, /Total : 1 joueur avec/);
});

test('without a topic nothing is sent', async () => {
  await player('f', 'Solo', -10);
  const r = await run(opts({ topic: undefined }));
  assert.equal(r.pseudos.length, 1);
  assert.equal(sent.length, 0);
});

test('players cannot read or write the check time', async () => {
  const db = env.authenticatedContext('alice').firestore();
  await assertFails(getDoc(doc(db, 'ops/newPseudos')));
  await assertFails(setDoc(doc(db, 'ops/newPseudos'), { lastCheck: at(0) }));
});

test('message lists at most 30 pseudos', () => {
  const many = Array.from({ length: 32 }, (_, i) => ({ pseudo: `p${i}`, createdAt: '2026-11-16T12:00:00Z' }));
  const m = message(many, 100);
  assert.equal(m.title, 'CNSNN : 32 nouveaux pseudos');
  assert.match(m.body, /… et 2 autres/);
  assert.equal(message([{ pseudo: 'x', createdAt: '2026-11-16T12:00:00Z' }], null).title, 'CNSNN : 1 nouveau pseudo');
});
