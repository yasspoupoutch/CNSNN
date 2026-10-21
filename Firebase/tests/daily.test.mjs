import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { normalize, consonants, difficultyOf, schedule, encrypt, decrypt, validate, parseList, combine, singleWord, limitFootball } from '../tools/daily.mjs';

const list = parseList([
 'F\tGénéral\tBonbon\tUne douceur sucrée.', 'F\tAnimaux\tŒuf\tUn indice assez long.',
 'M\tObjets\tÉventail\tOn l’agite pour se rafraîchir.', 'D\tCinéma\tÉvasion\tUne évasion célèbre.',
].join('\n'));

test('normalization matches the app', () => {
 assert.equal(normalize('Bienvenue chez les Ch’tis'), 'BIENVENUECHEZLESCHTIS');
 assert.equal(normalize('Cœur de lion'), 'COEURDELION');
 assert.equal(consonants('Pyjama'), 'PJM');
});
test('difficulty follows the weekday', () => {
 assert.equal(difficultyOf('2026-10-12'), 'Facile');   // Monday
 assert.equal(difficultyOf('2026-10-14'), 'Moyen');    // Wednesday
 assert.equal(difficultyOf('2026-10-18'), 'Difficile'); // Sunday
});
test('schedule gives each day a word of its difficulty', () => {
 const days = schedule(list, '2026-10-14', 28);
 assert.equal(days.length, 28);
 for (const d of days) assert.equal(d.difficulty, difficultyOf(d.day));
 assert.deepEqual(schedule(list, '2026-10-14', 28), days);
});
test('the list round-trips through encryption and rejects duplicates', () => {
 const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
 const box = encrypt(list, publicKey.export({ type: 'spki', format: 'pem' }));
 assert.ok(!JSON.stringify(box).includes('Bonbon'));
 assert.deepEqual(decrypt(box, privateKey.export({ type: 'pkcs8', format: 'pem' })), list);
 assert.throws(() => validate([...list, { ...list[0], word: 'BONBON' }]));
});
test('played words come back last, the longest ago first', () => {
 const easy = parseList(['Bonbon','Carotte','Domino','Fenêtre','Girafe','Hibou','Jardin'].map((w) => `F\tGénéral\t${w}\tUn indice simple.`).concat(['M\tObjets\tÉventail\tOn l’agite.', 'D\tCinéma\tÉvasion\tUne évasion.']).join('\n'));
 // 2026-10-19 and 2026-10-20 are Monday and Tuesday: easy days.
 const first = schedule(easy, '2026-10-19', 2);
 const played = new Map([[normalize(first[0].word), '2026-10-12'], [normalize(first[1].word), '2026-10-05']]);
 const next = schedule(easy, '2026-10-19', 30, played).filter((d) => d.difficulty === 'Facile');
 const words = next.map((d) => normalize(d.word));
 assert.ok(!words.slice(0, 5).some((w) => played.has(w)));
 assert.equal(words[5], normalize(first[1].word));
 assert.equal(words[6], normalize(first[0].word));
});
test('lists combine without duplicates', () => {
 const { words, skipped } = combine([list, [{ ...list[0], word: 'BONBON' }, { word: 'Nouveau', hint: 'Un mot de plus.', category: 'Général', difficulty: 'Facile' }]]);
 assert.equal(words.length, list.length + 1);
 assert.equal(skipped, 1);
});

test('the Mot du jour is a single word', () => {
  assert.equal(singleWord({ word: 'Papillon' }), true);
  assert.equal(singleWord({ word: 'Arc-en-ciel' }), true);
  assert.equal(singleWord({ word: 'Coup de pied' }), false);
  assert.throws(() => parseList('F\tGénéral\tCoup de pied\tUn geste au football.'), /un seul mot/);
});

test('football keeps at most one word in ten', () => {
  const make = (category, n) => Array.from({ length: n }, (_, i) => ({ word: `${category}${i}`, hint: 'Un indice.', category, difficulty: 'Difficile' }));
  const kept = limitFootball([...make('Football', 30), ...make('Général', 45)]);
  assert.equal(kept.filter((w) => w.category === 'Football').length, 5);
  assert.equal(kept.filter((w) => w.category === 'Général').length, 45);
});
