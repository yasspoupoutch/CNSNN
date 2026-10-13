import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
 doc, setDoc, updateDoc, getDoc, getDocs, deleteDoc, collection, query, where, orderBy, serverTimestamp,
 writeBatch, getCountFromServer, Timestamp,
} from 'firebase/firestore';

let env;
before(async()=>{ env=await initializeTestEnvironment({projectId:'demo-cnsnn',firestore:{rules:readFileSync('firestore.rules','utf8')}}); });
after(async()=>{ await env?.cleanup(); });
beforeEach(async()=>{ await env.clearFirestore(); });

const user=(uid='alice',claims={})=>env.authenticatedContext(uid,claims).firestore();
const profile=(uid='alice',username='Alice')=>({uid,username,createdAt:serverTimestamp(),updatedAt:serverTimestamp(),score:0,gamesPlayed:0,correctAnswers:0,bestTimeMs:null,currentStreak:0});
const card=(status='pending',createdBy='alice')=>({wordFull:'Chocolat',wordNoVowels:'CHCLT',normalizedAnswer:'CHOCOLAT',hint:'Un carré gourmand.',category:'Général',difficulty:'Facile',createdBy,createdAt:serverTimestamp(),status});
const seed=async(path,data)=>env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),path),data);});
const read=async(path)=>{let d;await env.withSecurityRulesDisabled(async c=>{d=(await getDoc(doc(c.firestore(),path))).data();});return d;};

// Same calendar and formula as the app (Core/GameRules.swift, Core/DailyPool.swift).
function parisKey(date=new Date()){
 const p=new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);
 const g=t=>p.find(x=>x.type===t).value;return `${g('year')}-${g('month')}-${g('day')}`;
}
function shiftKey(key,days){const d=new Date(`${key}T12:00:00Z`);d.setUTCDate(d.getUTCDate()+days);return d.toISOString().slice(0,10);}
function base(key){const w=new Date(`${key}T12:00:00Z`).getUTCDay();const iso=w===0?7:w;return iso<=2?50:iso<=5?100:150;}
function points(key,timeMs,usedHint,correct){if(!correct)return 0;const raw=base(key)+Math.max(0,50-Math.floor(timeMs/1000));return usedHint?Math.floor(raw/2):raw;}

async function signUp(uid='alice',username='Alice'){ await assertSucceeds(setDoc(doc(user(uid),`users/${uid}`),profile(uid,username))); }
async function startDaily(uid='alice',day=parisKey()){
 await assertSucceeds(setDoc(doc(user(uid),`dailySessions/${uid}_${day}`),{userId:uid,day,cardId:'daily-e-001',startedAt:serverTimestamp(),hintUsed:false}));
}
async function finishDaily(uid='alice',day=parisKey(),correct=true){
 await assertSucceeds(updateDoc(doc(user(uid),`dailySessions/${uid}_${day}`),{finishedAt:serverTimestamp(),correct,wrongAnswers:1}));
}
// Builds the result exactly as the app does: everything comes from the finished session.
async function resultFor(uid,day,overrides={}){
 const s=(await getDoc(doc(user(uid),`dailySessions/${uid}_${day}`))).data();
 const timeMs=s.finishedAt.toMillis()-s.startedAt.toMillis();
 return {userId:uid,username:(await read(`users/${uid}`)).username,day,cardId:s.cardId,correct:s.correct,usedHint:s.hintUsed,wrongAnswers:s.wrongAnswers,
  timeMs,points:points(day,timeMs,s.hintUsed,s.correct),startedAt:s.startedAt,finishedAt:s.finishedAt,...overrides};
}
function tally(old,r,uid='alice'){
 const laterWin=r.correct&&r.day>old.lastWinDay;
 const streak=laterWin?(old.lastWinDay===shiftKey(r.day,-1)?old.streak+1:1):(!r.correct&&r.day>old.lastWinDay?0:old.streak);
 return {uid,username:r.username,points:old.points+r.points,played:old.played+1,wins:old.wins+(r.correct?1:0),streak,bestStreak:Math.max(old.bestStreak,streak),
  bestTimeMs:r.correct?(old.bestTimeMs==null?r.timeMs:Math.min(old.bestTimeMs,r.timeMs)):old.bestTimeMs,lastWinDay:laterWin?r.day:old.lastWinDay,lastResult:r.day,updatedAt:serverTimestamp()};
}
const zero={points:0,played:0,wins:0,streak:0,bestStreak:0,bestTimeMs:null,lastWinDay:''};
async function publish(uid,r,old=zero,forged={}){
 const db=user(uid),b=writeBatch(db);
 b.set(doc(db,`dailyResults/${uid}_${r.day}`),r);b.set(doc(db,`leaderboard/${uid}`),{...tally(old,r,uid),...forged});
 return b.commit();
}

// ---------- Profiles and sync

test('profile ownership, rename, immutable stats',async()=>{
 const db=user(); await signUp();
 await assertSucceeds(updateDoc(doc(db,'users/alice'),{username:'Alicia',updatedAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(db,'users/alice'),{score:999}));
 await assertFails(updateDoc(doc(db,'users/alice'),{admin:true}));
 await assertFails(getDoc(doc(user('bob'),'users/alice')));
});
test('forged statistics at creation rejected',async()=>{ await assertFails(setDoc(doc(user(),'users/alice'),{...profile(),score:100})); });
test('synced progress is private to its owner and bounded',async()=>{
 await signUp();
 const ref=p=>doc(p,'users/alice/private/progress');
 await assertSucceeds(setDoc(ref(user()),{json:'{}',schema:2,updatedAt:serverTimestamp()}));
 await assertSucceeds(getDoc(ref(user())));
 await assertFails(getDoc(ref(user('bob'))));
 await assertFails(setDoc(ref(user('bob')),{json:'{}',schema:2,updatedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(user(),'users/alice/private/other'),{json:'{}',schema:2,updatedAt:serverTimestamp()}));
 await assertFails(setDoc(ref(user()),{json:'x'.repeat(900001),schema:2,updatedAt:serverTimestamp()}));
});
test('admin document grants moderation, but cannot be self-created',async()=>{
 await assertFails(setDoc(doc(user('mallory'),'admins/mallory'),{}));
 await seed('admins/mod',{});
 await assertSucceeds(getDoc(doc(user('mod'),'admins/mod')));
 await assertFails(getDoc(doc(user('bob'),'admins/mod')));
 await seed('cards/CHOCOLAT',card());
 await assertSucceeds(updateDoc(doc(user('mod'),'cards/CHOCOLAT'),{status:'approved',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
});

// ---------- Daily word

test('daily session: today only, server start time, single start',async()=>{
 await signUp();
 const db=user(),day=parisKey();
 await assertFails(setDoc(doc(db,`dailySessions/alice_${shiftKey(day,-3)}`),{userId:'alice',day:shiftKey(day,-3),cardId:'x',startedAt:serverTimestamp(),hintUsed:false}));
 await assertFails(setDoc(doc(db,`dailySessions/alice_${day}`),{userId:'alice',day,cardId:'x',startedAt:Timestamp.fromMillis(Date.now()-60000),hintUsed:false}));
 await assertFails(setDoc(doc(db,`dailySessions/bob_${day}`),{userId:'bob',day,cardId:'x',startedAt:serverTimestamp(),hintUsed:false}));
 await startDaily();
 // Restarting would reset the clock: refused.
 await assertFails(setDoc(doc(db,`dailySessions/alice_${day}`),{userId:'alice',day,cardId:'x',startedAt:serverTimestamp(),hintUsed:false}));
 await assertFails(getDoc(doc(user('bob'),`dailySessions/alice_${day}`)));
});
test('daily session needs a profile',async()=>{ await assertFails(setDoc(doc(user(),`dailySessions/alice_${parisKey()}`),{userId:'alice',day:parisKey(),cardId:'x',startedAt:serverTimestamp(),hintUsed:false})); });
test('hint cannot be hidden and finish happens once',async()=>{
 await signUp(); await startDaily();
 const ref=doc(user(),`dailySessions/alice_${parisKey()}`);
 await assertSucceeds(updateDoc(ref,{hintUsed:true}));
 await assertFails(updateDoc(ref,{hintUsed:false}));
 await assertFails(updateDoc(ref,{finishedAt:Timestamp.fromMillis(Date.now()-50000),correct:true,wrongAnswers:0}));
 await finishDaily();
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0}));
 await assertFails(updateDoc(ref,{startedAt:serverTimestamp()}));
});
test('secret daily word: consonants today, hint and answer only when earned',async()=>{
 await signUp(); await signUp('bob','Bob');
 const day=parisKey(),old=shiftKey(day,-3),next=shiftKey(day,2);
 for(const d of [day,old,next]){
  await seed(`dailyPuzzles/${d}`,{consonants:'CHCLT',category:'Général',difficulty:'Facile'});
  await seed(`dailyHints/${d}`,{hint:'Un carré gourmand.'});
  await seed(`dailySecrets/${d}`,{answer:'CHOCOLAT',word:'Chocolat',hint:'Un carré gourmand.',category:'Général',difficulty:'Facile'});
 }
 const db=user();
 await assertSucceeds(getDoc(doc(db,`dailyPuzzles/${day}`)));
 await assertSucceeds(getDoc(doc(db,`dailyPuzzles/${old}`)));
 await assertFails(getDoc(doc(db,`dailyPuzzles/${next}`)));
 await assertFails(getDocs(collection(db,'dailyPuzzles')));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),`dailyPuzzles/${day}`)));
 await assertFails(setDoc(doc(db,`dailyPuzzles/${day}`),{consonants:'X'}));
 // Before starting: neither hint nor answer.
 await assertFails(getDoc(doc(db,`dailyHints/${day}`)));
 await assertFails(getDoc(doc(db,`dailySecrets/${day}`)));
 await assertFails(getDocs(collection(db,'dailySecrets')));
 await assertFails(getDoc(doc(db,`dailySecrets/${next}`)));
 // Past days are open, so the history can show yesterday's word.
 await assertSucceeds(getDoc(doc(db,`dailySecrets/${old}`)));
 await startDaily();
 await assertFails(getDoc(doc(db,`dailyHints/${day}`)));
 await assertFails(getDoc(doc(db,`dailySecrets/${day}`)));
 const ref=doc(db,`dailySessions/alice_${day}`);
 await assertSucceeds(updateDoc(ref,{hintUsed:true}));
 await assertSucceeds(getDoc(doc(db,`dailyHints/${day}`)));
 await assertFails(getDoc(doc(db,`dailySecrets/${day}`)));
 // Another player's revealed hint does not open it for Bob.
 await assertFails(getDoc(doc(user('bob'),`dailyHints/${day}`)));
 // A win without the right answer is refused, so a wrong guess cannot finish the game.
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0}));
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0,answer:'CHOCOLA'}));
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0,answer:'chocolat'}));
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:false,wrongAnswers:0,answer:'X'.repeat(81)}));
 await assertSucceeds(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:2,answer:'CHOCOLAT'}));
 await assertSucceeds(getDoc(doc(db,`dailySecrets/${day}`)));
 await assertFails(getDoc(doc(user('bob'),`dailySecrets/${day}`)));
 // The official result still publishes from the finished session.
 await assertSucceeds(publish('alice',await resultFor('alice',day)));
});
test('giving up on a secret daily word needs no answer',async()=>{
 await signUp(); const day=parisKey();
 await seed(`dailySecrets/${day}`,{answer:'CHOCOLAT',word:'Chocolat',hint:'Un carré gourmand.',category:'Général',difficulty:'Facile'});
 await startDaily(); await finishDaily('alice',day,false);
 await assertSucceeds(getDoc(doc(user(),`dailySecrets/${day}`)));
 await assertSucceeds(getDoc(doc(user(),`dailyHints/${day}`)));
});
test('official result: server time and recomputed points, once',async()=>{
 await signUp(); await startDaily(); await finishDaily();
 const day=parisKey(),r=await resultFor('alice',day);
 await assertFails(publish('alice',{...r,timeMs:Math.max(0,r.timeMs-1)}));
 await assertFails(publish('alice',{...r,points:r.points+1}));
 await assertFails(publish('alice',{...r,usedHint:true,points:points(day,r.timeMs,true,true)}));
 await assertFails(publish('alice',{...r,username:'Someone'}));
 // A result without the matching leaderboard tally is refused, and the reverse too.
 await assertFails(setDoc(doc(user(),`dailyResults/alice_${day}`),r));
 await assertFails(setDoc(doc(user(),'leaderboard/alice'),tally(zero,r)));
 await assertSucceeds(publish('alice',r));
 const board=await read('leaderboard/alice');
 assert.equal(board.points,r.points); assert.equal(board.wins,1); assert.equal(board.streak,1); assert.equal(board.bestTimeMs,r.timeMs);
 // Replays and edits are impossible.
 await assertFails(publish('alice',r,{...zero,...board}));
 await assertFails(updateDoc(doc(user(),`dailyResults/alice_${day}`),{timeMs:1}));
 await assertFails(deleteDoc(doc(user(),`dailyResults/alice_${day}`)));
 await assertFails(updateDoc(doc(user(),'leaderboard/alice'),{points:99999,updatedAt:serverTimestamp()}));
});
test('a lost daily scores zero and resets the streak',async()=>{
 await signUp();
 const day=parisKey(),yesterday=shiftKey(day,-1);
 await seed('leaderboard/alice',{uid:'alice',username:'Alice',points:120,played:3,wins:3,streak:3,bestStreak:3,bestTimeMs:4000,lastWinDay:yesterday,lastResult:yesterday,updatedAt:Timestamp.now()});
 await startDaily(); await finishDaily('alice',day,false);
 const r=await resultFor('alice',day);
 assert.equal(r.points,0);
 const old=await read('leaderboard/alice');
 await assertFails(publish('alice',r,old,{streak:4,bestStreak:4}));
 await assertFails(publish('alice',r,old,{points:old.points+50}));
 await assertSucceeds(publish('alice',r,old));
 const board=await read('leaderboard/alice');
 assert.equal(board.streak,0); assert.equal(board.bestStreak,3); assert.equal(board.played,4); assert.equal(board.points,120);
});
test('a win after yesterday extends the streak',async()=>{
 await signUp();
 const day=parisKey(),yesterday=shiftKey(day,-1);
 await seed('leaderboard/alice',{uid:'alice',username:'Alice',points:100,played:1,wins:1,streak:1,bestStreak:1,bestTimeMs:9000,lastWinDay:yesterday,lastResult:yesterday,updatedAt:Timestamp.now()});
 await startDaily(); await finishDaily();
 const r=await resultFor('alice',day),old=await read('leaderboard/alice');
 await assertSucceeds(publish('alice',r,old));
 assert.equal((await read('leaderboard/alice')).streak,2);
});
test('leaderboard rename follows the profile only',async()=>{
 await signUp();
 await seed('leaderboard/alice',{uid:'alice',username:'Alice',points:0,played:0,wins:0,streak:0,bestStreak:0,bestTimeMs:null,lastWinDay:'',lastResult:'',updatedAt:Timestamp.now()});
 const db=user(),b=writeBatch(db);
 b.update(doc(db,'users/alice'),{username:'Alicia',updatedAt:serverTimestamp()});
 b.update(doc(db,'leaderboard/alice'),{username:'Alicia',updatedAt:serverTimestamp()});
 await assertSucceeds(b.commit());
 await assertFails(updateDoc(doc(db,'leaderboard/alice'),{username:'Zorro',updatedAt:serverTimestamp()}));
});
test('ranking and percentile queries are public to players',async()=>{
 const day=parisKey();
 for(const [uid,timeMs] of [['a',4000],['b',9000],['c',15000]]) await seed(`dailyResults/${uid}_${day}`,{userId:uid,username:uid,day,correct:true,timeMs,points:100});
 const db=user('bob');
 const top=await assertSucceeds(getDocs(query(collection(db,'dailyResults'),where('day','==',day),where('correct','==',true),orderBy('timeMs'))));
 assert.deepEqual(top.docs.map(d=>d.data().timeMs),[4000,9000,15000]);
 const slower=await assertSucceeds(getCountFromServer(query(collection(db,'dailyResults'),where('day','==',day),where('correct','==',true),where('timeMs','>',4000))));
 assert.equal(slower.data().count,2);
 await assertSucceeds(getDocs(query(collection(db,'leaderboard'),orderBy('points','desc'))));
 await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),'leaderboard')));
});

// ---------- Friends

test('friend codes: create own, look up any, list only own',async()=>{
 await signUp(); await signUp('bob','Bob');
 const alice=user('alice'),bob=user('bob');
 await assertFails(setDoc(doc(alice,'friendCodes/ABC2Z9'),{uid:'bob',username:'Bob',createdAt:serverTimestamp()}));
 await assertFails(setDoc(doc(alice,'friendCodes/abc0O1'),{uid:'alice',username:'Alice',createdAt:serverTimestamp()}));
 await assertSucceeds(setDoc(doc(alice,'friendCodes/ABC2Z9'),{uid:'alice',username:'Alice',createdAt:serverTimestamp()}));
 // Taken: a second write is an update, refused.
 await assertFails(setDoc(doc(bob,'friendCodes/ABC2Z9'),{uid:'bob',username:'Bob',createdAt:serverTimestamp()}));
 const found=await assertSucceeds(getDoc(doc(bob,'friendCodes/ABC2Z9')));
 assert.equal(found.data().uid,'alice');
 await assertSucceeds(getDoc(doc(bob,'friendCodes/ZZZZZZ')));
 await assertSucceeds(getDocs(query(collection(alice,'friendCodes'),where('uid','==','alice'))));
 await assertFails(getDocs(collection(bob,'friendCodes')));
 await assertFails(deleteDoc(doc(bob,'friendCodes/ABC2Z9')));
 await assertSucceeds(deleteDoc(doc(alice,'friendCodes/ABC2Z9')));
});
test('friends list is private to its owner',async()=>{
 await signUp(); await signUp('bob','Bob');
 await assertSucceeds(setDoc(doc(user('alice'),'users/alice/friends/bob'),{username:'Bob',addedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(user('alice'),'users/alice/friends/alice'),{username:'Alice',addedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(user('bob'),'users/alice/friends/bob'),{username:'Bob',addedAt:serverTimestamp()}));
 await assertFails(getDocs(collection(user('bob'),'users/alice/friends')));
 await assertSucceeds(getDocs(collection(user('alice'),'users/alice/friends')));
 await assertSucceeds(deleteDoc(doc(user('alice'),'users/alice/friends/bob')));
});

// ---------- Cards and moderation

async function propose(uid='alice',id='CHOCOLAT',data=card('pending',uid),quota){
 const db=user(uid),b=writeBatch(db);
 b.set(doc(db,`cards/${id}`),data);
 b.update(doc(db,`users/${uid}`),quota??{updatedAt:serverTimestamp(),lastProposalAt:serverTimestamp(),proposalWindowAt:serverTimestamp(),proposalCount:1});
 return b.commit();
}
test('proposal: id is the normalized word, so duplicates fail',async()=>{
 await signUp(); await signUp('bob','Bob');
 await assertFails(propose('alice','random-id'));
 await assertSucceeds(propose());
 await assertFails(propose('bob','CHOCOLAT',card('pending','bob')));
});
test('proposal author pseudo must be the proposer own',async()=>{
 await signUp();
 await assertFails(propose('alice','CHOCOLAT',{...card('pending','alice'),authorName:'Admin'}));
 await assertSucceeds(propose('alice','CHOCOLAT',{...card('pending','alice'),authorName:'Alice'}));
});
test('proposal needs the quota update and respects the cooldown',async()=>{
 await signUp();
 await assertFails(setDoc(doc(user(),'cards/CHOCOLAT'),card()));
 await assertSucceeds(propose());
 const second={...card(),wordFull:'Croissant',wordNoVowels:'CRSSNT',normalizedAnswer:'CROISSANT'};
 // Within 30 s of the previous proposal.
 const p=await read('users/alice');
 await assertFails(propose('alice','CROISSANT',second,{updatedAt:serverTimestamp(),lastProposalAt:serverTimestamp(),proposalWindowAt:p.proposalWindowAt,proposalCount:2}));
 // Quota counters cannot be reset by hand.
 await assertFails(updateDoc(doc(user(),'users/alice'),{updatedAt:serverTimestamp(),proposalCount:0}));
});
test('proposal daily cap of ten',async()=>{
 await signUp();
 await env.withSecurityRulesDisabled(async c=>{await updateDoc(doc(c.firestore(),'users/alice'),{lastProposalAt:Timestamp.fromMillis(Date.now()-60000),proposalWindowAt:Timestamp.fromMillis(Date.now()-3600000),proposalCount:10});});
 const p=await read('users/alice');
 await assertFails(propose('alice','CHOCOLAT',card(),{updatedAt:serverTimestamp(),lastProposalAt:serverTimestamp(),proposalWindowAt:p.proposalWindowAt,proposalCount:11}));
 await env.withSecurityRulesDisabled(async c=>{await updateDoc(doc(c.firestore(),'users/alice'),{proposalCount:4});});
 await assertSucceeds(propose('alice','CHOCOLAT',card(),{updatedAt:serverTimestamp(),lastProposalAt:serverTimestamp(),proposalWindowAt:p.proposalWindowAt,proposalCount:5}));
});
test('pending private, owner cannot approve, admin claim can and may fix the hint',async()=>{
 await signUp(); await assertSucceeds(propose());
 const db=user();
 await assertFails(getDoc(doc(user('bob'),'cards/CHOCOLAT')));
 await assertFails(updateDoc(doc(db,'cards/CHOCOLAT'),{status:'approved',reviewedBy:'alice',reviewedAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(user('mod',{admin:true}),'cards/CHOCOLAT'),{status:'approved',wordFull:'Autre mot',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(doc(user('mod',{admin:true}),'cards/CHOCOLAT'),{status:'approved',hint:'Un carré qui fond.',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
 await assertSucceeds(getDoc(doc(user('bob'),'cards/CHOCOLAT')));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'cards/CHOCOLAT')));
 // Live cards can no longer be withdrawn by their author.
 await assertFails(deleteDoc(doc(db,'cards/CHOCOLAT')));
});
test('approved at creation and extra fields rejected',async()=>{
 await signUp();
 await assertFails(propose('alice','CHOCOLAT',card('approved')));
 await assertFails(propose('alice','CHOCOLAT',{...card(),admin:true}));
});
test('approved query permitted, global enumeration denied',async()=>{
 await seed('cards/CHOCOLAT',card('approved'));
 await assertSucceeds(getDocs(query(collection(user('bob'),'cards'),where('status','==','approved'))));
 await assertFails(getDocs(collection(user('bob'),'cards')));
});
test('client cannot forge legacy attempts or schedule',async()=>{
 for(const path of ['attempts/fake','dailyChallenges/2026-10-06']) await assertFails(setDoc(doc(user(),path),{userId:'alice',score:100}));
});
test('moderators publish daily words with the weekday difficulty',async()=>{
 const challenge=(difficulty)=>({cardId:'custom-1',wordFull:'Montgolfière',hint:'Un ballon à air chaud.',category:'Objets',difficulty,publishedBy:'mod',publishedAt:serverTimestamp()});
 const mod=user('mod',{admin:true});
 // 2026-10-17 is a Saturday: hard.
 await assertFails(setDoc(doc(mod,'dailyChallenges/2026-10-17'),challenge('Facile')));
 await assertSucceeds(setDoc(doc(mod,'dailyChallenges/2026-10-17'),challenge('Difficile')));
 await assertSucceeds(setDoc(doc(mod,'dailyChallenges/2026-10-13'),challenge('Facile')));
 await assertSucceeds(setDoc(doc(mod,'dailyChallenges/2026-10-14'),challenge('Moyen')));
 await assertFails(setDoc(doc(user(),'dailyChallenges/2026-10-18'),{...challenge('Difficile'),publishedBy:'alice'}));
 await assertSucceeds(getDoc(doc(user(),'dailyChallenges/2026-10-17')));
});
test('a missing card id can be checked before proposing',async()=>{
 await assertSucceeds(getDoc(doc(user(),'cards/INCONNU')));
});
test('report deduplication and admin resolution',async()=>{
 await seed('cards/CHOCOLAT',card('approved'));
 const report={userId:'alice',cardId:'CHOCOLAT',reason:'Indice incorrect.',createdAt:serverTimestamp(),status:'pending'};
 await assertSucceeds(setDoc(doc(user(),'reports/alice_CHOCOLAT'),report));
 await assertFails(setDoc(doc(user(),'reports/duplicate'),report));
 await assertFails(updateDoc(doc(user(),'reports/alice_CHOCOLAT'),{status:'resolved'}));
 await assertSucceeds(updateDoc(doc(user('mod',{admin:true}),'reports/alice_CHOCOLAT'),{status:'resolved',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
});
test('only admin can withdraw an approved card',async()=>{
 await seed('cards/CHOCOLAT',card('approved'));
 await assertFails(updateDoc(doc(user(),'cards/CHOCOLAT'),{status:'rejected',reviewedBy:'alice',reviewedAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(doc(user('mod',{admin:true}),'cards/CHOCOLAT'),{status:'rejected',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
 await assertFails(getDoc(doc(user('bob'),'cards/CHOCOLAT')));
});

// ---------- Account deletion

test('account deletion removes every player document, and only then the daily history',async()=>{
 await signUp(); await startDaily(); await finishDaily();
 const day=parisKey(); await assertSucceeds(publish('alice',await resultFor('alice',day)));
 await assertSucceeds(setDoc(doc(user(),'users/alice/private/progress'),{json:'{}',schema:2,updatedAt:serverTimestamp()}));
 const db=user();
 // The daily history stays while the profile exists (no delete-and-replay).
 await assertFails(deleteDoc(doc(db,`dailySessions/alice_${day}`)));
 const b=writeBatch(db);
 for(const path of ['users/alice','users/alice/private/progress','leaderboard/alice',`dailyResults/alice_${day}`,`dailySessions/alice_${day}`]) b.delete(doc(db,path));
 await assertSucceeds(b.commit());
 assert.equal(await read('leaderboard/alice'),undefined);
 // Nobody else can delete a profile.
 await signUp('bob','Bob');
 await assertFails(deleteDoc(doc(user('alice'),'users/bob')));
});
