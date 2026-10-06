import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, getDocs, collection, query, where, serverTimestamp } from 'firebase/firestore';
let env;
before(async()=>{ env=await initializeTestEnvironment({projectId:'demo-cnsnn',firestore:{rules:readFileSync('firestore.rules','utf8')}}); });
after(async()=>{ await env?.cleanup(); });
beforeEach(async()=>{ await env.clearFirestore(); });
const user=(uid='alice',claims={})=>env.authenticatedContext(uid,claims).firestore();
const profile=()=>({uid:'alice',username:'Alice',createdAt:serverTimestamp(),updatedAt:serverTimestamp(),score:0,gamesPlayed:0,correctAnswers:0,bestTimeMs:null,currentStreak:0});
const card=(status='pending')=>({wordFull:'Chocolat',wordNoVowels:'CHCLT',normalizedAnswer:'CHOCOLAT',hint:'Un carré gourmand.',category:'Général',difficulty:'Facile',createdBy:'alice',createdAt:serverTimestamp(),status});
test('profile ownership, rename, immutable stats and admin',async()=>{
 const db=user(); await assertSucceeds(setDoc(doc(db,'users/alice'),profile()));
 await assertSucceeds(updateDoc(doc(db,'users/alice'),{username:'Alicia',updatedAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(db,'users/alice'),{score:999}));
 await assertFails(updateDoc(doc(db,'users/alice'),{admin:true}));
 await assertFails(getDoc(doc(user('bob'),'users/alice')));
});
test('forged statistics at creation rejected',async()=>{ await assertFails(setDoc(doc(user(),'users/alice'),{...profile(),score:100})); });
test('pending private, owner cannot approve, admin claim can',async()=>{
 const db=user(); await assertSucceeds(setDoc(doc(db,'cards/card'),card()));
 await assertFails(getDoc(doc(user('bob'),'cards/card')));
 await assertFails(updateDoc(doc(db,'cards/card'),{status:'approved',reviewedBy:'alice',reviewedAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(doc(user('mod',{admin:true}),'cards/card'),{status:'approved',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
 await assertSucceeds(getDoc(doc(user('bob'),'cards/card')));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'cards/card')));
});
test('approved at creation and extra fields rejected',async()=>{
 await assertFails(setDoc(doc(user(),'cards/card'),card('approved')));
 await assertFails(setDoc(doc(user(),'cards/card'),{...card(),admin:true}));
});
test('approved query permitted, global enumeration denied',async()=>{
 await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'cards/card'),card('approved'));});
 await assertSucceeds(getDocs(query(collection(user('bob'),'cards'),where('status','==','approved'))));
 await assertFails(getDocs(collection(user('bob'),'cards')));
});
test('client cannot forge attempts, daily result or schedule',async()=>{
 for(const path of ['attempts/fake','dailyResults/fake','dailyChallenges/2026-10-06']) await assertFails(setDoc(doc(user(),path),{userId:'alice',score:100}));
});
test('report deduplication and admin resolution',async()=>{
 await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'cards/card'),card('approved'));});
 const report={userId:'alice',cardId:'card',reason:'Indice incorrect.',createdAt:serverTimestamp(),status:'pending'};
 await assertSucceeds(setDoc(doc(user(),'reports/alice_card'),report));
 await assertFails(setDoc(doc(user(),'reports/duplicate'),report));
 await assertFails(updateDoc(doc(user(),'reports/alice_card'),{status:'resolved'}));
 await assertSucceeds(updateDoc(doc(user('mod',{admin:true}),'reports/alice_card'),{status:'resolved',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
});

test('only admin can withdraw an approved card',async()=>{
 await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'cards/card'),card('approved'));});
 await assertFails(updateDoc(doc(user(),'cards/card'),{status:'rejected',reviewedBy:'alice',reviewedAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(doc(user('mod',{admin:true}),'cards/card'),{status:'rejected',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
 await assertFails(getDoc(doc(user('bob'),'cards/card')));
});
