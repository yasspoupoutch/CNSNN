// Push alert for new pseudos (tools/new-pseudos.mjs), run against the emulator with a fake ntfy server.
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, Timestamp } from 'firebase/firestore';

const PROJECT = 'demo-cnsnn-pseudos';
let env, server, sent = [], run, message, parisTime, parisDay;

before(async () => {
  env = await initializeTestEnvironment({ projectId: PROJECT, firestore: { rules: readFileSync('firestore.rules', 'utf8') } });
  server = createServer((req, res) => {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => { sent.push(JSON.parse(body)); res.end('{}'); });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  process.env.NTFY_URL = `http://127.0.0.1:${server.address().port}/`;
  ({ run, message, parisTime, parisDay } = await import('../tools/new-pseudos.mjs'));
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
  assert.match(sent[0].message, /Bilou \(lundi 13 h 20\)/);
  assert.match(sent[0].message, /Total : 3 joueurs/);
  assert.match(sent[0].message, /Vérifié lundi 15 h 00 \(heure française\)/);
  assert.match(sent[0].message, /Derniers inscrits : Sara \(lundi 16\/11 14 h 30\), Bilou \(lundi 16\/11 13 h 20\), Ancien/);

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
  // Kept for when the topic is set.
  assert.equal((await run(opts())).pseudos[0].pseudo, 'Solo');
  assert.equal(sent.length, 1);
});

test('daily summary: sent once per French day, even with nothing new; later tries stop', async () => {
  await player('g', 'Ancien', -300);
  await lastCheck(-120);
  const first = await run(opts({ daily: true }));
  assert.equal(first.sent, true);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].title, 'CNSNN : aucun nouveau pseudo');
  assert.match(sent[0].message, /Total : 1 joueur avec/);

  // A later try the same evening: a new pseudo appeared, but it waits for tomorrow's summary.
  await player('h', 'Lisou', 10);
  const later = await run(opts({ daily: true, now: now + 30 * 60_000 }));
  assert.equal(later.skipped, true);
  assert.equal(sent.length, 1);

  const tomorrow = await run(opts({ daily: true, now: now + 24 * 3600_000 }));
  assert.deepEqual(tomorrow.pseudos.map((p) => p.pseudo), ['Lisou']);
  assert.equal(sent.length, 2);
  assert.equal(sent[1].title, 'CNSNN : 1 nouveau pseudo');
});

test('French day changes at midnight Paris time', () => {
  assert.equal(parisDay(Date.parse('2026-11-16T22:59:00Z')), '2026-11-16');
  assert.equal(parisDay(Date.parse('2026-11-16T23:01:00Z')), '2026-11-17');
});

test('players cannot read or write the check time', async () => {
  const db = env.authenticatedContext('alice').firestore();
  await assertFails(getDoc(doc(db, 'ops/newPseudos')));
  await assertFails(setDoc(doc(db, 'ops/newPseudos'), { lastCheck: at(0) }));
});

test('times are in French time, summer and winter', () => {
  assert.equal(parisTime('2026-11-16T23:05:00Z'), 'mardi 00 h 05');
  assert.equal(parisTime('2026-07-01T10:30:00Z'), 'mercredi 12 h 30');
});

test('message lists at most 30 pseudos', () => {
  const many = Array.from({ length: 32 }, (_, i) => ({ pseudo: `p${i}`, createdAt: '2026-11-16T12:00:00Z' }));
  const m = message(many, 100);
  assert.equal(m.title, 'CNSNN : 32 nouveaux pseudos');
  assert.match(m.body, /… et 2 autres/);
  assert.equal(message([{ pseudo: 'x', createdAt: '2026-11-16T12:00:00Z' }], null).title, 'CNSNN : 1 nouveau pseudo');
});

test('automatic pseudos (Joueur4821) are counted apart, not listed', () => {
  const at = '2026-11-16T12:00:00Z';
  const m = message([{ pseudo: 'Joueur4821', createdAt: at }, { pseudo: 'Sara', createdAt: at }, { pseudo: 'Joueur10234', createdAt: at }], 10, null,
    [{ pseudo: 'Joueur4821', createdAt: at }, { pseudo: 'Sara', createdAt: at }]);
  assert.equal(m.title, 'CNSNN : 3 nouveaux joueurs');
  assert.match(m.body, /• Sara/);
  assert.doesNotMatch(m.body, /• Joueur/);
  assert.match(m.body, /2 joueurs gardent le pseudo automatique/);
  assert.match(m.body, /Derniers inscrits : Sara \(/);
  assert.equal(message([{ pseudo: 'Joueur4821', createdAt: at }], 1).title, 'CNSNN : 1 nouveau joueur');
});
