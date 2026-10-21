import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
 doc, setDoc, updateDoc, getDoc, getDocs, deleteDoc, collection, query, where, orderBy, serverTimestamp,
 writeBatch, getCountFromServer, Timestamp, deleteField,
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
// Same as Core/GameRules.swift DailyScore: time, +1 min with the hint, 10 min for a lost day (and at most).
function score(timeMs,usedHint,correct){return correct?Math.min(timeMs+(usedHint?60000:0),600000):600000;}
const dayIndex=key=>Math.round(Date.parse(`${key}T00:00:00Z`)/86400000);
const dailyRank=(key,s,correct)=>dayIndex(key)*1000000+(correct?s:999999);
const monthIndex=key=>Number(key.slice(0,4))*12+Number(key.slice(5,7))-1;
const weekIndex=key=>Math.floor((dayIndex(key)+3)/7);
const weekRank=(w,found,ms)=>w*100000000+found*10000000+(9999999-ms);

// Creates the profile and reserves its pseudo in the same batch, as the apps do.
function signUpBatch(uid='alice',username='Alice',data=profile(uid,username)){
 const db=user(uid),b=writeBatch(db);
 b.set(doc(db,`usernames/${username.toLowerCase()}`),{uid,createdAt:serverTimestamp()});b.set(doc(db,`users/${uid}`),data);
 return b.commit();
}
async function signUp(uid='alice',username='Alice'){ await assertSucceeds(signUpBatch(uid,username)); }
// Renames the profile, taking the new pseudo and freeing the old one.
function renameBatch(uid,from,to,db=user(uid)){
 const b=writeBatch(db);
 b.set(doc(db,`usernames/${to.toLowerCase()}`),{uid,createdAt:serverTimestamp()});b.delete(doc(db,`usernames/${from.toLowerCase()}`));
 b.update(doc(db,`users/${uid}`),{username:to,updatedAt:serverTimestamp()});
 return b;
}
const patch=async(path,data)=>env.withSecurityRulesDisabled(async c=>{await updateDoc(doc(c.firestore(),path),data);});
// Starts the clock, then moves the start 10 s back: a win needs at least 2 s of play.
async function startDaily(uid='alice',day=parisKey(),{backdate=true}={}){
 await assertSucceeds(setDoc(doc(user(uid),`dailySessions/${uid}_${day}`),{userId:uid,day,cardId:'daily-e-001',startedAt:serverTimestamp(),hintUsed:false}));
 if(backdate) await patch(`dailySessions/${uid}_${day}`,{startedAt:Timestamp.fromMillis(Date.now()-10000)});
}
// Registers a guess on the server as the app does, then moves its time back so the next one is allowed.
function guessData(s,word){return {guesses:(s.guesses??0)+1,guess:word,guessAt:serverTimestamp()};}
async function guess(uid='alice',day=parisKey(),word='CHOCOLAT',{backdate=true}={}){
 const path=`dailySessions/${uid}_${day}`;
 await assertSucceeds(updateDoc(doc(user(uid),path),guessData(await read(path),word)));
 if(backdate) await patch(path,{guessAt:Timestamp.fromMillis(Date.now()-5000)});
}
// Every day has a secret word since 2026-10-14, and a win must name the last registered guess.
async function finishDaily(uid='alice',day=parisKey(),correct=true){
 const path=`dailySessions/${uid}_${day}`;
 if(correct){ await seed(`dailySecrets/${day}`,{answer:'CHOCOLAT'}); await guess(uid,day,'CHOCOLA'); await guess(uid,day,'CHOCOLAT'); }
 const guesses=(await read(path)).guesses??0;
 await assertSucceeds(updateDoc(doc(user(uid),path),{finishedAt:serverTimestamp(),correct,wrongAnswers:correct?guesses-1:guesses,...(correct?{answer:'CHOCOLAT'}:{})}));
}
// Builds the result exactly as the app does: everything comes from the finished session.
async function resultFor(uid,day,overrides={}){
 const s=(await getDoc(doc(user(uid),`dailySessions/${uid}_${day}`))).data();
 const timeMs=s.finishedAt.toMillis()-s.startedAt.toMillis();
 return {userId:uid,username:(await read(`users/${uid}`)).username,day,cardId:s.cardId,correct:s.correct,usedHint:s.hintUsed,wrongAnswers:s.wrongAnswers,
  timeMs,scoreMs:score(timeMs,s.hintUsed,s.correct),rank:dailyRank(day,score(timeMs,s.hintUsed,s.correct),s.correct),startedAt:s.startedAt,finishedAt:s.finishedAt,...overrides};
}
// The week's tally as iOS 1.1 sends it; `weeks:false` is an app from before (iOS 1.0, Android).
function tally(old,r,uid='alice',{weeks=true}={}){
 const laterWin=r.correct&&r.day>old.lastWinDay;
 const streak=laterWin?(old.lastWinDay===shiftKey(r.day,-1)?old.streak+1:1):(!r.correct&&r.day>old.lastWinDay?0:old.streak);
 const m=monthIndex(r.day),om=old.month??0,same=m===om,saved=(same?old.monthSaved:0)+600000-r.scoreMs;
 const month=m<om?{month:om,monthSaved:old.monthSaved,monthPlayed:old.monthPlayed,monthRank:old.monthRank}
  :{month:m,monthSaved:saved,monthPlayed:(same?old.monthPlayed:0)+1,monthRank:m*100000000+saved};
 const w=weekIndex(r.day),ow=old.week??0,sameWeek=w===ow;
 const found=(sameWeek?old.weekFound:0)+(r.correct?1:0),ms=(sameWeek?old.weekTimeMs:0)+(r.correct?r.scoreMs:0);
 const week=!weeks?{}:w<ow?{week:ow,weekFound:old.weekFound,weekTimeMs:old.weekTimeMs,weekPlayed:old.weekPlayed,weekRank:old.weekRank}
  :{week:w,weekFound:found,weekTimeMs:ms,weekPlayed:(sameWeek?old.weekPlayed:0)+1,weekRank:weekRank(w,found,ms)};
 return {uid,username:r.username,...month,...week,played:old.played+1,wins:old.wins+(r.correct?1:0),streak,bestStreak:Math.max(old.bestStreak,streak),
  bestTimeMs:r.correct?(old.bestTimeMs==null?r.timeMs:Math.min(old.bestTimeMs,r.timeMs)):old.bestTimeMs,lastWinDay:laterWin?r.day:old.lastWinDay,lastResult:r.day,updatedAt:serverTimestamp()};
}
const zero={played:0,wins:0,streak:0,bestStreak:0,bestTimeMs:null,lastWinDay:'',month:0,monthSaved:0,monthPlayed:0};
async function publish(uid,r,old=zero,forged={},options={}){
 const db=user(uid),b=writeBatch(db);
 b.set(doc(db,`dailyResults/${uid}_${r.day}`),r);b.set(doc(db,`leaderboard/${uid}`),{...tally(old,r,uid,options),...forged});
 return b.commit();
}

// ---------- Profiles and sync

test('profile ownership, rename, immutable stats',async()=>{
 const db=user(); await signUp();
 await assertSucceeds(renameBatch('alice','Alice','Alicia').commit());
 await assertFails(updateDoc(doc(db,'users/alice'),{score:999}));
 await assertFails(updateDoc(doc(db,'users/alice'),{admin:true}));
 await assertFails(getDoc(doc(user('bob'),'users/alice')));
});
test('forged statistics at creation rejected',async()=>{ await assertFails(signUpBatch('alice','Alice',{...profile(),score:100})); });
test('pseudos are unique, whatever the case',async()=>{
 await signUp('alice','Poupoutch');
 // Taken, in any case, or without a reservation at all.
 await assertFails(signUpBatch('bob','Poupoutch'));
 await assertFails(signUpBatch('bob','POUPOUTCH'));
 await assertFails(setDoc(doc(user('bob'),'users/bob'),profile('bob','Bob')));
 // A reservation must name the pseudo the profile takes, for oneself only.
 const db=user('bob');let b=writeBatch(db);
 b.set(doc(db,'usernames/zorro'),{uid:'bob',createdAt:serverTimestamp()});b.set(doc(db,'users/bob'),profile('bob','Bob'));
 await assertFails(b.commit());
 await assertFails(setDoc(doc(db,'usernames/bob'),{uid:'alice',createdAt:serverTimestamp()}));
 await signUp('bob','Bob');
 // Anyone signed in may check a pseudo; nobody can take or free someone else's.
 assert.equal((await assertSucceeds(getDoc(doc(db,'usernames/poupoutch')))).data().uid,'alice');
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'usernames/poupoutch')));
 await assertFails(deleteDoc(doc(db,'usernames/poupoutch')));
 await assertFails(renameBatch('bob','Bob','poupoutch').commit());
 await assertFails(updateDoc(doc(db,'users/bob'),{username:'Robert',updatedAt:serverTimestamp()}));
 // Renaming frees the old pseudo for others; the case of one's own pseudo can change.
 await assertSucceeds(renameBatch('alice','Poupoutch','Alicia').commit());
 await signUp('carol','poupoutch');
 await assertSucceeds(updateDoc(doc(db,'users/bob'),{username:'BOB',updatedAt:serverTimestamp()}));
});
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
// The word changes at each player's local midnight: a day is open from its midnight in UTC+14 to
// its end in UTC-12, and its answer becomes public only after that. The cases below hold at any
// hour, whatever the time zone of the machine running the tests.
test('daily word at local midnight: open while it is that day somewhere, answer public after',async()=>{
 await signUp();
 const utcKey=(ms)=>new Date(ms).toISOString().slice(0,10),now=Date.now(),hour=3600000;
 const open=[utcKey(now+14*hour),utcKey(now-12*hour)];   // always today somewhere
 const closed=[utcKey(now+38*hour),utcKey(now-60*hour)]; // never today anywhere
 for(const d of [...open,...closed]){
  await seed(`dailyPuzzles/${d}`,{consonants:'CHCLT',category:'Général',difficulty:'Facile'});
  await seed(`dailySecrets/${d}`,{answer:'CHOCOLAT',word:'Chocolat',hint:'Un indice.',category:'Général',difficulty:'Facile'});
 }
 const start=(d)=>setDoc(doc(user(),`dailySessions/alice_${d}`),{userId:'alice',day:d,cardId:'x',startedAt:serverTimestamp(),hintUsed:false});
 for(const d of open){
  await assertSucceeds(getDoc(doc(user(),`dailyPuzzles/${d}`)));
  // Still being played in some time zone: the answer stays secret.
  await assertFails(getDoc(doc(user('bob'),`dailySecrets/${d}`)));
 }
 for(const d of open) if(!(await env.withSecurityRulesDisabled(async c=>(await getDoc(doc(c.firestore(),`dailySessions/alice_${d}`))).exists()))) await assertSucceeds(start(d));
 // Too early everywhere: tomorrow's word cannot be read or started in advance.
 await assertFails(getDoc(doc(user(),`dailyPuzzles/${closed[0]}`)));
 await assertFails(start(closed[0]));
 // Over everywhere: no new game, the answer is public.
 await assertFails(start(closed[1]));
 await assertSucceeds(getDoc(doc(user('bob'),`dailySecrets/${closed[1]}`)));
 // A day already started cannot be started again.
 await assertFails(start(open[0]));
});
// The app looks for today's session before starting it. A direct read of a missing session is
// refused (the rule checks its owner), so the app queries its own sessions instead.
test('a new player can look for a session that does not exist yet',async()=>{
 await signUp(); const day=parisKey();
 await assertFails(getDoc(doc(user(),`dailySessions/alice_${day}`)));
 const mine=await assertSucceeds(getDocs(query(collection(user(),'dailySessions'),where('userId','==','alice'),where('day','==',day))));
 assert.equal(mine.size,0);
 await startDaily('alice',day,{backdate:false});
 assert.equal((await getDocs(query(collection(user(),'dailySessions'),where('userId','==','alice'),where('day','==',day)))).size,1);
 await assertFails(getDocs(query(collection(user('bob'),'dailySessions'),where('userId','==','alice'),where('day','==',day))));
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
 // A registered wrong guess is still refused, and counts as an error.
 await guess('alice',day,'CHOCOLA');
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0,answer:'CHOCOLA'}));
 await guess('alice',day,'CHOCOLAT');
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0,answer:'CHOCOLAT'}));
 await assertSucceeds(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:1,answer:'CHOCOLAT'}));
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
test('official result: server time and recomputed score, once',async()=>{
 await signUp(); await startDaily(); await finishDaily();
 const day=parisKey(),r=await resultFor('alice',day);
 await assertFails(publish('alice',{...r,timeMs:Math.max(0,r.timeMs-1)}));
 await assertFails(publish('alice',{...r,scoreMs:r.scoreMs-1}));
 await assertFails(publish('alice',{...r,rank:r.rank-1}));
 await assertFails(publish('alice',{...r,points:100}));
 // The hint must be the session's: hiding it to dodge the minute fails.
 await assertFails(publish('alice',{...r,usedHint:true,scoreMs:score(r.timeMs,true,true),rank:dailyRank(day,score(r.timeMs,true,true),true)}));
 await assertFails(publish('alice',{...r,username:'Someone'}));
 // A result without the matching leaderboard tally is refused, and the reverse too.
 await assertFails(setDoc(doc(user(),`dailyResults/alice_${day}`),r));
 await assertFails(setDoc(doc(user(),'leaderboard/alice'),tally(zero,r)));
 await assertSucceeds(publish('alice',r));
 const board=await read('leaderboard/alice');
 assert.equal(board.monthSaved,600000-r.scoreMs); assert.equal(board.monthPlayed,1); assert.equal(board.month,monthIndex(day));
 assert.equal(board.monthRank,monthIndex(day)*100000000+600000-r.scoreMs); assert.equal(board.wins,1); assert.equal(board.streak,1); assert.equal(board.bestTimeMs,r.timeMs);
 // Replays and edits are impossible.
 await assertFails(publish('alice',r,{...zero,...board}));
 await assertFails(updateDoc(doc(user(),`dailyResults/alice_${day}`),{timeMs:1}));
 await assertFails(deleteDoc(doc(user(),`dailyResults/alice_${day}`)));
 await assertFails(updateDoc(doc(user(),'leaderboard/alice'),{monthSaved:99999999,updatedAt:serverTimestamp()}));
});
test('a lost daily counts 10 minutes and resets the streak',async()=>{
 await signUp();
 const day=parisKey(),yesterday=shiftKey(day,-1);
 // An old line, from before the time-only scoring, still has its points: the next result drops them.
 await seed('leaderboard/alice',{uid:'alice',username:'Alice',points:120,played:3,wins:3,streak:3,bestStreak:3,bestTimeMs:4000,lastWinDay:yesterday,lastResult:yesterday,updatedAt:Timestamp.now()});
 await startDaily(); await finishDaily('alice',day,false);
 const r=await resultFor('alice',day);
 assert.equal(r.scoreMs,600000);
 const old=await read('leaderboard/alice');
 await assertFails(publish('alice',r,old,{streak:4,bestStreak:4}));
 await assertFails(publish('alice',r,old,{points:old.points}));
 await assertFails(publish('alice',r,old,{monthSaved:1000}));
 await assertSucceeds(publish('alice',r,old));
 const board=await read('leaderboard/alice');
 assert.equal(board.streak,0); assert.equal(board.bestStreak,3); assert.equal(board.played,4); assert.equal(board.points,undefined);
 assert.equal(board.monthSaved,0); assert.equal(board.monthPlayed,1);
});
test('a win after yesterday extends the streak',async()=>{
 await signUp();
 const day=parisKey(),yesterday=shiftKey(day,-1);
 const m=monthIndex(day);
 await seed('leaderboard/alice',{uid:'alice',username:'Alice',played:1,wins:1,streak:1,bestStreak:1,bestTimeMs:9000,lastWinDay:yesterday,lastResult:yesterday,
  month:m,monthSaved:591000,monthPlayed:1,monthRank:m*100000000+591000,updatedAt:Timestamp.now()});
 await startDaily(); await finishDaily();
 const r=await resultFor('alice',day),old=await read('leaderboard/alice');
 await assertSucceeds(publish('alice',r,old));
 const board=await read('leaderboard/alice');
 assert.equal(board.streak,2); assert.equal(board.monthPlayed,2); assert.equal(board.monthSaved,591000+600000-r.scoreMs);
});
test('the month total starts again each month and ignores a late day from an older month',async()=>{
 await signUp();
 const day=parisKey(),yesterday=shiftKey(day,-1),m=monthIndex(day);
 const line=month=>({uid:'alice',username:'Alice',played:5,wins:5,streak:0,bestStreak:2,bestTimeMs:9000,lastWinDay:'',lastResult:yesterday,
  month,monthSaved:2000000,monthPlayed:5,monthRank:month*100000000+2000000,updatedAt:Timestamp.now()});
 await seed('leaderboard/alice',line(m-1));
 await startDaily(); await finishDaily();
 const r=await resultFor('alice',day),old=await read('leaderboard/alice');
 // Carrying last month's total over is refused.
 await assertFails(publish('alice',r,old,{month:m,monthSaved:2000000+600000-r.scoreMs,monthPlayed:6,monthRank:m*100000000+2000000+600000-r.scoreMs}));
 await assertSucceeds(publish('alice',r,old));
 let board=await read('leaderboard/alice');
 assert.equal(board.month,m); assert.equal(board.monthSaved,600000-r.scoreMs); assert.equal(board.monthPlayed,1);
 await env.clearFirestore();
 await signUp();
 await seed('leaderboard/alice',line(m+1));
 await startDaily(); await finishDaily();
 const late=await resultFor('alice',day),newer=await read('leaderboard/alice');
 await assertFails(publish('alice',late,newer,{month:m,monthSaved:600000-late.scoreMs,monthPlayed:1,monthRank:m*100000000+600000-late.scoreMs}));
 await assertSucceeds(publish('alice',late,newer));
 board=await read('leaderboard/alice');
 assert.equal(board.month,m+1); assert.equal(board.monthSaved,2000000); assert.equal(board.monthPlayed,5);
});
test('the week ranks words found then time, and starts again each Monday',async()=>{
 await signUp();
 const day=parisKey(),yesterday=shiftKey(day,-1),w=weekIndex(day);
 const line=(week,found,ms)=>({uid:'alice',username:'Alice',played:2,wins:2,streak:0,bestStreak:2,bestTimeMs:9000,lastWinDay:'',lastResult:yesterday,
  month:monthIndex(day),monthSaved:0,monthPlayed:0,monthRank:monthIndex(day)*100000000,week,weekFound:found,weekTimeMs:ms,weekPlayed:found,weekRank:weekRank(week,found,ms),updatedAt:Timestamp.now()});
 await seed('leaderboard/alice',line(w,2,70000));
 await startDaily(); await finishDaily();
 let r=await resultFor('alice',day),old=await read('leaderboard/alice');
 // Forged words found, time or rank are refused; so is half a week tally.
 await assertFails(publish('alice',r,old,{weekFound:4,weekRank:weekRank(w,4,70000+r.scoreMs)}));
 await assertFails(publish('alice',r,old,{weekTimeMs:1000,weekRank:weekRank(w,3,1000)}));
 await assertFails(publish('alice',r,old,{weekRank:weekRank(w,3,0)}));
 { const half=tally(old,r); delete half.weekRank; const db=user(),b=writeBatch(db);
   b.set(doc(db,`dailyResults/alice_${day}`),r); b.set(doc(db,'leaderboard/alice'),half); await assertFails(b.commit()); }
 await assertSucceeds(publish('alice',r,old));
 let board=await read('leaderboard/alice');
 assert.equal(board.week,w); assert.equal(board.weekFound,3); assert.equal(board.weekTimeMs,70000+r.scoreMs); assert.equal(board.weekPlayed,3);
 assert.equal(board.weekRank,weekRank(w,3,70000+r.scoreMs));
 // A lost day counts as played, adds no time and no word.
 await env.clearFirestore(); await signUp();
 await seed('leaderboard/alice',line(w,2,70000));
 await startDaily(); await finishDaily('alice',day,false);
 r=await resultFor('alice',day); old=await read('leaderboard/alice');
 await assertFails(publish('alice',r,old,{weekTimeMs:70000+600000,weekRank:weekRank(w,2,670000)}));
 await assertSucceeds(publish('alice',r,old));
 board=await read('leaderboard/alice');
 assert.equal(board.weekFound,2); assert.equal(board.weekTimeMs,70000); assert.equal(board.weekPlayed,3);
 // Last week's tally is not carried over; a late day from an older week leaves the newer week alone.
 await env.clearFirestore(); await signUp();
 await seed('leaderboard/alice',line(w-1,6,200000));
 await startDaily(); await finishDaily();
 r=await resultFor('alice',day); old=await read('leaderboard/alice');
 await assertFails(publish('alice',r,old,{week:w,weekFound:7,weekTimeMs:200000+r.scoreMs,weekPlayed:7,weekRank:weekRank(w,7,200000+r.scoreMs)}));
 await assertSucceeds(publish('alice',r,old));
 board=await read('leaderboard/alice');
 assert.equal(board.week,w); assert.equal(board.weekFound,1); assert.equal(board.weekTimeMs,r.scoreMs);
 await env.clearFirestore(); await signUp();
 await seed('leaderboard/alice',line(w+1,1,30000));
 await startDaily(); await finishDaily();
 r=await resultFor('alice',day); old=await read('leaderboard/alice');
 await assertFails(publish('alice',r,old,{week:w,weekFound:1,weekTimeMs:r.scoreMs,weekPlayed:1,weekRank:weekRank(w,1,r.scoreMs)}));
 await assertSucceeds(publish('alice',r,old));
 board=await read('leaderboard/alice');
 assert.equal(board.week,w+1); assert.equal(board.weekFound,1); assert.equal(board.weekTimeMs,30000);
});
test('an app from before the weekly ranking still saves its results',async()=>{
 await signUp();
 const day=parisKey(),w=weekIndex(day);
 await startDaily(); await finishDaily();
 const r=await resultFor('alice',day);
 // iOS 1.0 sends no week fields: accepted, and the line leaves the week's ranking.
 await assertSucceeds(publish('alice',r,zero,{},{weeks:false}));
 const board=await read('leaderboard/alice');
 assert.equal(board.week,undefined); assert.equal(board.month,monthIndex(day));
 // Week fields sent at all must be complete and right.
 await env.clearFirestore(); await signUp(); await startDaily(); await finishDaily();
 const again=await resultFor('alice',day);
 await assertFails(publish('alice',again,zero,{week:w},{weeks:false}));
 await assertSucceeds(publish('alice',again));
 assert.equal((await read('leaderboard/alice')).weekRank,weekRank(w,1,again.scoreMs));
});
test('leaderboard rename follows the profile only',async()=>{
 await signUp();
 await seed('leaderboard/alice',{uid:'alice',username:'Alice',played:0,wins:0,streak:0,bestStreak:0,bestTimeMs:null,lastWinDay:'',lastResult:'',updatedAt:Timestamp.now()});
 const db=user(),b=renameBatch('alice','Alice','Alicia',db);
 b.update(doc(db,'leaderboard/alice'),{username:'Alicia',updatedAt:serverTimestamp()});
 await assertSucceeds(b.commit());
 await assertFails(updateDoc(doc(db,'leaderboard/alice'),{username:'Zorro',updatedAt:serverTimestamp()}));
});
test('ranking and percentile queries are public to players, on single fields',async()=>{
 const day=parisKey(),base=dailyRank(day,0,true);
 // b took the hint: 9 s + 1 min puts them behind c. d lost, yesterday's player is another day.
 for(const [uid,timeMs,hint,correct] of [['a',4000,false,true],['b',9000,true,true],['c',15000,false,true],['d',30000,false,false]]){
  const s=score(timeMs,hint,correct);
  await seed(`dailyResults/${uid}_${day}`,{userId:uid,username:uid,day,correct,usedHint:hint,timeMs,scoreMs:s,rank:dailyRank(day,s,correct)});
 }
 await seed(`dailyResults/e_${shiftKey(day,-1)}`,{userId:'e',username:'e',day:shiftKey(day,-1),correct:true,timeMs:1000,scoreMs:1000,rank:dailyRank(shiftKey(day,-1),1000,true)});
 const db=user('bob'),results=collection(db,'dailyResults');
 const top=await assertSucceeds(getDocs(query(results,where('rank','>=',base),where('rank','<=',base+600000),orderBy('rank'))));
 assert.deepEqual(top.docs.map(d=>d.data().userId),['a','c','b']);
 const behind=await assertSucceeds(getCountFromServer(query(results,where('rank','>',base+4000),where('rank','<=',base+999999))));
 assert.equal(behind.data().count,3);
 const m=monthIndex(day);
 await seed('leaderboard/a',{uid:'a',username:'a',month:m,monthSaved:1000,monthRank:m*100000000+1000});
 await seed('leaderboard/b',{uid:'b',username:'b',month:m-1,monthSaved:9000,monthRank:(m-1)*100000000+9000});
 const month=await assertSucceeds(getDocs(query(collection(db,'leaderboard'),where('monthRank','>=',m*100000000),where('monthRank','<',(m+1)*100000000),orderBy('monthRank','desc'))));
 assert.deepEqual(month.docs.map(d=>d.id),['a']);
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

test('friends: typing a code adds both players, only with that code',async()=>{
 await signUp(); await signUp('bob','Bob'); await signUp('carol','Carol');
 await seed('friendCodes/ABC2Z9',{uid:'alice',username:'Alice',createdAt:new Date()});
 await seed('friendCodes/CAR234',{uid:'carol',username:'Carol',createdAt:new Date()});
 const bob=user('bob'),back={username:'Bob',addedAt:serverTimestamp(),code:'ABC2Z9'};
 // Bob must have added Alice first.
 await assertFails(setDoc(doc(bob,'users/alice/friends/bob'),back));
 await assertSucceeds(setDoc(doc(bob,'users/bob/friends/alice'),{username:'Alice',addedAt:serverTimestamp()}));
 // Another player's code, a missing code, someone else's place or extra fields: refused.
 await assertFails(setDoc(doc(bob,'users/alice/friends/bob'),{...back,code:'CAR234'}));
 await assertFails(setDoc(doc(bob,'users/alice/friends/bob'),{...back,code:'ZZZZZZ'}));
 await assertFails(setDoc(doc(bob,'users/alice/friends/bob'),{username:'Bob',addedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(bob,'users/alice/friends/carol'),back));
 await assertFails(setDoc(doc(bob,'users/alice/friends/bob'),{...back,extra:1}));
 await assertSucceeds(setDoc(doc(bob,'users/alice/friends/bob'),back));
 // Bob still cannot read Alice's list; Alice sees him and may remove him.
 await assertFails(getDoc(doc(bob,'users/alice/friends/bob')));
 const list=await assertSucceeds(getDocs(collection(user('alice'),'users/alice/friends')));
 assert.deepEqual(list.docs.map(d=>d.id),['bob']);
 await assertSucceeds(deleteDoc(doc(user('alice'),'users/alice/friends/bob')));
 // A suspended player cannot.
 await seed('banned/bob',{username:'Bob',reason:'x',bannedAt:new Date(),bannedBy:'admin'});
 await assertFails(setDoc(doc(bob,'users/alice/friends/bob'),back));
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
test('account deletion leaves a tombstone and anonymizes live cards',async()=>{
 await signUp(); await seed('cards/CHOCOLAT',{...card('approved'),authorName:'Alice'});
 const db=user(),b=writeBatch(db);
 b.update(doc(db,'cards/CHOCOLAT'),{createdBy:'deleted',authorName:deleteField()});
 b.set(doc(db,'deletedUsers/alice'),{deletedAt:serverTimestamp()});
 b.delete(doc(db,'users/alice'));
 await assertSucceeds(b.commit());
 const c=await read('cards/CHOCOLAT'); assert.equal(c.createdBy,'deleted'); assert.equal(c.authorName,undefined);
 await assertSucceeds(getDoc(doc(user('bob'),'deletedUsers/alice')));
 // Nobody can mark someone else deleted, or rewrite another author's card.
 await assertFails(setDoc(doc(user('bob'),'deletedUsers/carol'),{deletedAt:serverTimestamp()}));
 await seed('cards/CROISSANT',{...card('approved','carol'),normalizedAnswer:'CROISSANT'});
 await assertFails(updateDoc(doc(user('bob'),'cards/CROISSANT'),{createdBy:'deleted'}));
});

// ---------- Pseudos, suspensions and player reports

test('offensive pseudos are refused, ordinary ones pass',async()=>{
 for(const name of ['Connard','gros c0nnard','Bâtard 93','pute','P.U.T.A.I.N']) await assertFails(signUpBatch('alice',name));
 for(const [uid,name] of [['m','Monique'],['c','Computer'],['n','Nazim']]) await signUp(uid,name);
 await signUp();
 await assertFails(renameBatch('alice','Alice','Salope').commit());
});
test('a suspended player keeps reading but can no longer play ranked, propose, report or rename',async()=>{
 await signUp(); await seed('cards/CHOCOLAT',card('approved','bob'));
 await assertFails(setDoc(doc(user('bob'),'banned/alice'),{username:'Alice',reason:'Pseudo',bannedAt:serverTimestamp(),bannedBy:'bob'}));
 await assertSucceeds(setDoc(doc(user('mod',{admin:true}),'banned/alice'),{username:'Alice',reason:'Pseudo',bannedAt:serverTimestamp(),bannedBy:'mod'}));
 await assertSucceeds(getDoc(doc(user(),'banned/alice')));
 await assertFails(getDoc(doc(user('bob'),'banned/alice')));
 await assertFails(setDoc(doc(user(),`dailySessions/alice_${parisKey()}`),{userId:'alice',day:parisKey(),cardId:'x',startedAt:serverTimestamp(),hintUsed:false}));
 await assertFails(propose());
 await assertFails(setDoc(doc(user(),'reports/alice_CHOCOLAT'),{userId:'alice',cardId:'CHOCOLAT',reason:'Indice incorrect.',createdAt:serverTimestamp(),status:'pending'}));
 await assertFails(renameBatch('alice','Alice','Alicia').commit());
 await assertSucceeds(getDoc(doc(user(),'cards/CHOCOLAT')));
 // Lifting the suspension gives everything back.
 await assertSucceeds(deleteDoc(doc(user('mod',{admin:true}),'banned/alice')));
 await startDaily();
});
test('player reports: one per reporter and player, name checked, admin resolves',async()=>{
 await seed('leaderboard/bob',{uid:'bob',username:'Bob',played:1});
 const r={userId:'alice',playerId:'bob',username:'Bob',reason:'Pseudo inapproprié',createdAt:serverTimestamp(),status:'pending'};
 await assertFails(setDoc(doc(user(),'playerReports/alice_bob'),{...r,username:'Autre'}));
 await assertFails(setDoc(doc(user(),'playerReports/whatever'),r));
 await assertFails(setDoc(doc(user('bob'),'playerReports/bob_bob'),{...r,userId:'bob'}));
 await assertSucceeds(setDoc(doc(user(),'playerReports/alice_bob'),r));
 await assertFails(getDocs(query(collection(user('bob'),'playerReports'),where('status','==','pending'))));
 await assertSucceeds(getDocs(query(collection(user('mod',{admin:true}),'playerReports'),where('status','==','pending'))));
 await assertSucceeds(updateDoc(doc(user('mod',{admin:true}),'playerReports/alice_bob'),{status:'resolved',reviewedBy:'mod',reviewedAt:serverTimestamp()}));
});
test('a day without a secret word never gives a free win',async()=>{
 await signUp(); await startDaily(); await guess('alice',parisKey(),'NIMPORTE');
 await assertFails(updateDoc(doc(user(),`dailySessions/alice_${parisKey()}`),{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0,answer:'NIMPORTE'}));
 await assertSucceeds(updateDoc(doc(user(),`dailySessions/alice_${parisKey()}`),{finishedAt:serverTimestamp(),correct:false,wrongAnswers:1}));
});

// ---------- Guesses: counted on the server, so a script cannot try every answer

test('guesses: counted one by one, one per second, at most twenty',async()=>{
 await signUp(); await startDaily();
 const day=parisKey(),path=`dailySessions/alice_${day}`,ref=doc(user(),path);
 await seed(`dailySecrets/${day}`,{answer:'CHOCOLAT'});
 // The count cannot jump, go back or be skipped.
 await assertFails(updateDoc(ref,{guesses:2,guess:'A',guessAt:serverTimestamp()}));
 await assertFails(updateDoc(ref,{guesses:1,guess:'A',guessAt:Timestamp.fromMillis(Date.now()-5000)}));
 await assertFails(updateDoc(ref,{guess:'A',guessAt:serverTimestamp()}));
 await assertFails(updateDoc(ref,{guesses:1,guess:'',guessAt:serverTimestamp()}));
 await guess('alice',day,'A',{backdate:false});
 // A second guess within a second is refused.
 await assertFails(updateDoc(ref,guessData(await read(path),'B')));
 await patch(path,{guessAt:Timestamp.fromMillis(Date.now()-5000)});
 await assertFails(updateDoc(ref,{guesses:1,guess:'B',guessAt:serverTimestamp()}));
 for(let i=2;i<=20;i++) await guess('alice',day,'X'+i);
 // The twenty-first guess is refused, even the right one.
 await assertFails(updateDoc(ref,guessData(await read(path),'CHOCOLAT')));
 // Only a loss with the twenty errors can end the game.
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:false,wrongAnswers:3}));
 await assertSucceeds(updateDoc(ref,{finishedAt:serverTimestamp(),correct:false,wrongAnswers:20}));
});
test('a win names the last registered guess, after two seconds at least',async()=>{
 await signUp(); const day=parisKey(),path=`dailySessions/alice_${day}`;
 await seed(`dailySecrets/${day}`,{answer:'CHOCOLAT'});
 await startDaily('alice',day,{backdate:false});
 const ref=doc(user(),path);
 await guess('alice',day,'CHOCOLAT');
 // Too fast to be a person reading the consonants.
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0,answer:'CHOCOLAT'}));
 await patch(path,{startedAt:Timestamp.fromMillis(Date.now()-10000)});
 await guess('alice',day,'CHOCOLA');
 // The right word, but not the last guess sent.
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:1,answer:'CHOCOLAT'}));
 await guess('alice',day,'CHOCOLAT');
 await assertFails(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:0,answer:'CHOCOLAT'}));
 await assertSucceeds(updateDoc(ref,{finishedAt:serverTimestamp(),correct:true,wrongAnswers:2,answer:'CHOCOLAT'}));
 // Finished: no more guesses.
 await assertFails(updateDoc(ref,guessData(await read(path),'X')));
});

// ---------- Suspensions keep the progress

test('a suspension hides results and totals without deleting them, and is reversible',async()=>{
 await signUp(); await startDaily(); await finishDaily();
 const day=parisKey(); await assertSucceeds(publish('alice',await resultFor('alice',day)));
 const mod=user('mod',{admin:true}),b=writeBatch(mod);
 b.set(doc(mod,'banned/alice'),{username:'Alice',reason:'Triche',bannedAt:serverTimestamp(),bannedBy:'mod'});
 b.update(doc(mod,'leaderboard/alice'),{suspended:true});
 b.update(doc(mod,`dailyResults/alice_${day}`),{suspended:true});
 await assertSucceeds(b.commit());
 // Only the flag can change, and only by a moderator.
 await assertFails(updateDoc(doc(mod,'leaderboard/alice'),{monthSaved:0}));
 await assertFails(updateDoc(doc(mod,`dailyResults/alice_${day}`),{timeMs:1}));
 await assertFails(updateDoc(doc(user(),'leaderboard/alice'),{suspended:deleteField()}));
 await assertFails(updateDoc(doc(user(),`dailyResults/alice_${day}`),{suspended:deleteField()}));
 await assertFails(updateDoc(doc(user('bob'),'leaderboard/alice'),{suspended:true}));
 assert.equal((await read('leaderboard/alice')).wins,1);
 const r=writeBatch(mod);
 r.delete(doc(mod,'banned/alice'));
 r.update(doc(mod,'leaderboard/alice'),{suspended:deleteField()});
 r.update(doc(mod,`dailyResults/alice_${day}`),{suspended:deleteField()});
 await assertSucceeds(r.commit());
 const board=await read('leaderboard/alice');
 assert.equal(board.suspended,undefined); assert.equal(board.wins,1);
});

// ---------- Community rules, card catalogue version

test('community rules are accepted at sign-up or later, with the server time',async()=>{
 await assertFails(signUpBatch('alice','Alice',{...profile(),rulesVersion:1,rulesAcceptedAt:Timestamp.fromMillis(0)}));
 await assertSucceeds(signUpBatch('alice','Alice',{...profile(),rulesVersion:1,rulesAcceptedAt:serverTimestamp()}));
 await signUp('bob','Bob');
 await assertSucceeds(updateDoc(doc(user('bob'),'users/bob'),{rulesVersion:1,rulesAcceptedAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(user('bob'),'users/bob'),{rulesVersion:'1',rulesAcceptedAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(user('alice'),'users/bob'),{rulesVersion:2,rulesAcceptedAt:serverTimestamp()}));
 // Still possible while suspended.
 await seed('banned/bob',{username:'Bob',reason:'x',bannedAt:Timestamp.now(),bannedBy:'mod'});
 await assertSucceeds(updateDoc(doc(user('bob'),'users/bob'),{rulesVersion:2,rulesAcceptedAt:serverTimestamp()}));
});
test('card catalogue version: read by players, moved by moderators',async()=>{
 await assertFails(setDoc(doc(user(),'meta/cards'),{updatedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(user('mod',{admin:true}),'meta/cards'),{updatedAt:Timestamp.fromMillis(0)}));
 await assertSucceeds(setDoc(doc(user('mod',{admin:true}),'meta/cards'),{updatedAt:serverTimestamp()}));
 await assertSucceeds(getDoc(doc(user(),'meta/cards')));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'meta/cards')));
});

// ---------- Deletion of everything that names the player

test('a deleted account takes its suspension record and the reports naming it',async()=>{
 await signUp();
 await seed('banned/alice',{username:'Alice',reason:'x',bannedAt:Timestamp.now(),bannedBy:'mod'});
 await seed('playerReports/bob_alice',{userId:'bob',playerId:'alice',username:'Alice',reason:'Pseudo inapproprié',createdAt:Timestamp.now(),status:'pending'});
 const db=user();
 // While the profile exists, a suspended player can neither lift it nor see who reported them.
 await assertFails(deleteDoc(doc(db,'banned/alice')));
 await assertFails(getDocs(query(collection(db,'playerReports'),where('playerId','==','alice'))));
 const b=writeBatch(db);
 b.delete(doc(db,'users/alice')); b.delete(doc(db,'banned/alice'));
 await assertSucceeds(b.commit());
 const about=await assertSucceeds(getDocs(query(collection(db,'playerReports'),where('playerId','==','alice'))));
 assert.equal(about.size,1);
 await assertSucceeds(deleteDoc(doc(db,'playerReports/bob_alice')));
});
