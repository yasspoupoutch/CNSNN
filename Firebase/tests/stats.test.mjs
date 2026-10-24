import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, collection, increment, deleteDoc, query, where, documentId } from 'firebase/firestore';

let env;
before(async()=>{ env=await initializeTestEnvironment({projectId:'demo-cnsnn-stats',firestore:{rules:readFileSync('firestore.rules','utf8')}}); });
after(async()=>{ await env?.cleanup(); });
beforeEach(async()=>{ await env.clearFirestore(); });

const user=(uid='alice')=>env.authenticatedContext(uid).firestore();
const guest=()=>env.unauthenticatedContext().firestore();
const seed=async(path,data)=>env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),path),data);});
const key=(shift=0)=>new Date(Date.now()+shift*86400000).toISOString().slice(0,10);
// What the apps send: increments merged into the day's document.
const add=(db,day,counts)=>setDoc(doc(db,`stats/${day}`),Object.fromEntries(Object.entries(counts).map(([k,v])=>[k,increment(v)])),{merge:true});

test('a phone without a pseudo only counts itself as opened',async()=>{
 await assertSucceeds(add(guest(),key(),{opensIos:1,newIos:1}));
 await assertSucceeds(add(guest(),key(),{opensAndroid:1}));
 await assertFails(add(guest(),key(),{players:1}));
 await assertFails(add(guest(),key(),{classic:2}));
});
test('a player adds games and counts once per write',async()=>{
 await assertSucceeds(add(user(),key(),{opensIos:1,players:1,newPlayers:1,daily:1,classic:12,sprint:2,survival:1,duo:1,challenge:1}));
 await assertSucceeds(add(user('bob'),key(),{opensAndroid:1,players:1,classic:3}));
 await assertFails(add(user(),key(),{players:2}));
 await assertFails(add(user(),key(),{opensIos:5}));
 await assertFails(add(user(),key(),{classic:1000}));
 await assertFails(add(user(),key(),{classic:-1}));
 await assertFails(add(user(),key(),{uid:'alice'}));
 await assertFails(add(user(),key(),{}));
});
test('counters cannot be rewritten, lowered or deleted',async()=>{
 await seed(`stats/${key()}`,{players:40,classic:300});
 await assertFails(setDoc(doc(user(),`stats/${key()}`),{players:41}));
 await assertFails(setDoc(doc(user(),`stats/${key()}`),{players:0},{merge:true}));
 await assertFails(setDoc(doc(user(),`stats/${key()}`),{players:'beaucoup'},{merge:true}));
 await assertFails(deleteDoc(doc(user(),`stats/${key()}`)));
 await assertSucceeds(add(user(),key(),{players:1,classic:4}));
});
test('only recent days, under a day key',async()=>{
 await assertSucceeds(add(user(),key(-3),{players:1}));
 await assertFails(add(user(),key(-6),{players:1}));
 await assertFails(add(user(),key(3),{players:1}));
 await assertFails(add(user(),'demain',{players:1}));
});
test('only the admins read the counts',async()=>{
 await seed(`stats/${key()}`,{players:3});
 await seed('admins/boss',{});
 await assertFails(getDoc(doc(user(),`stats/${key()}`)));
 await assertFails(getDocs(collection(guest(),'stats')));
 await assertSucceeds(getDoc(doc(user('boss'),`stats/${key()}`)));
 await assertSucceeds(getDocs(query(collection(user('boss'),'stats'),where(documentId(),'>=',key(-13)))));
});
