import {test} from 'node:test';
import assert from 'node:assert/strict';
import {normalize,consonants,points,dayKey,previousKey,resolveAttempt} from '../domain.mjs';
test('French normalization and editorial vowel policy',()=>{
 for(const [word,expected] of [['Chocolat','CHCLT'],['Éléphant','LPHNT'],['L’été','LT'],['œuf','F'],['Penalty','PNLT'],['  Ballon d’or  ','BLLNDR']])assert.equal(consonants(word),expected);
 assert.equal(normalize('L’ŒUVRE d’Été'),'LOEUVREDETE');
});
test('score is difficulty/time/hint based and never negative',()=>{
 assert.equal(points('Facile',10000,false,true),90);assert.equal(points('Facile',10000,true,true),45);
 assert.equal(points('Difficile',999999,false,true),150);assert.equal(points('Facile',-1000,false,true),100);
 assert.equal(points('Difficile',0,false,false),0);assert.throws(()=>points('unknown',0,false,true));
});
test('Paris midnight and daylight saving dates',()=>{
 assert.equal(dayKey(new Date('2026-10-05T22:30:00Z')),'2026-10-06');
 assert.equal(dayKey(new Date('2026-03-29T22:30:00Z')),'2026-03-30');
 assert.equal(previousKey('2026-03-30'),'2026-03-29');assert.equal(previousKey('2026-01-01'),'2025-12-31');
});
test('incorrect guesses award nothing and keep the session active',()=>{
 assert.deepEqual(resolveAttempt({word:'Chocolat',answer:'chocolats',difficulty:'Facile',startedAtMs:0,nowMs:1000,usedHint:false}),{finished:false,correct:false});
 assert.deepEqual(resolveAttempt({word:'',answer:'',difficulty:'Facile',startedAtMs:0,nowMs:1000,usedHint:false}),{finished:false,correct:false});
});
test('server timestamps determine a correct result',()=>{
 assert.deepEqual(resolveAttempt({word:'Éléphant',answer:'elephant',difficulty:'Facile',startedAtMs:2000,nowMs:12000,usedHint:false}),{finished:true,correct:true,timeMs:10000,points:90});
});
test('abandonment closes the daily challenge with zero points',()=>{
 assert.deepEqual(resolveAttempt({word:'Chocolat',answer:'chocolat',difficulty:'Facile',startedAtMs:0,nowMs:20000,usedHint:false,abandon:true}),{finished:true,correct:false,timeMs:20000,points:0});
});
