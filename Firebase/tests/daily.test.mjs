import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { normalize, consonants, difficultyOf, schedule, encrypt, decrypt, validate, parseList } from '../tools/daily.mjs';

const list = parseList([
 'F\tGénéral\tBonbon\tUne douceur sucrée.', 'F\tAnimaux\tCœur de lion\tUn indice assez long.',
 'M\tObjets\tÉventail\tOn l’agite pour se rafraîchir.', 'D\tCinéma\tLes Évadés\tUne évasion célèbre.',
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
