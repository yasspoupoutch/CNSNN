// Optional trusted ranked daily backend. NOT registered in Firebase/firebase.json.
// Production deployment requires prior approval for Firebase Blaze billing.
import { onCall,HttpsError } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore,Timestamp,FieldValue } from 'firebase-admin/firestore';
import { dayKey,previousKey,resolveAttempt } from './domain.mjs';
initializeApp();const db=getFirestore();
const options={region:'europe-west1',enforceAppCheck:true,maxInstances:2,timeoutSeconds:15,memory:'256MiB'};
function user(request) { if(!request.auth)throw new HttpsError('unauthenticated','Connexion requise.');return request.auth.uid; }
function refs(uid,key) {
 return {session:db.doc(`gameSessions/${uid}_${key}`),result:db.doc(`dailyResults/${uid}_${key}`),profile:db.doc(`users/${uid}`),challenge:db.doc(`dailyChallenges/${key}`),solution:db.doc(`dailySolutions/${key}`)};
}
export const beginDaily=onCall(options,async request=>{
 const uid=user(request),key=dayKey(),r=refs(uid,key);
 return db.runTransaction(async tx=>{
  const [challenge,session,result,profile]=await Promise.all([tx.get(r.challenge),tx.get(r.session),tx.get(r.result),tx.get(r.profile)]);
  if(!challenge.exists || !profile.exists)throw new HttpsError('failed-precondition','Défi ou profil indisponible.');
  const data=challenge.data();
  if(!session.exists && !result.exists)tx.create(r.session,{userId:uid,dailyKey:key,startedAt:Timestamp.now(),usedHint:false,status:'active',wrongAnswers:0});
  // Never return the full word or normalized answer before completion.
  return {dailyKey:key,cardId:data.cardId,wordNoVowels:data.wordNoVowels,category:data.category,difficulty:data.difficulty,result:result.exists?result.data():null};
 });
});
export const revealDailyHint=onCall(options,async request=>{
 const uid=user(request),key=request.data?.dailyKey;
 if(typeof key!=='string'||key!==dayKey())throw new HttpsError('invalid-argument','Défi expiré.');
 const r=refs(uid,key);
 return db.runTransaction(async tx=>{
  const [s,c]=await Promise.all([tx.get(r.session),tx.get(r.solution)]);
  if(!s.exists || s.data().status!=='active' || !c.exists)throw new HttpsError('failed-precondition','Partie indisponible.');
  tx.update(r.session,{usedHint:true});return {hint:c.data().hint};
 });
});
export const answerDaily=onCall(options,async request=>{
 const uid=user(request),key=request.data?.dailyKey,answer=request.data?.answer,abandon=request.data?.abandon===true;
 if(typeof key!=='string'||!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(key)||typeof answer!=='string'||answer.length>120)throw new HttpsError('invalid-argument','Réponse invalide.');
 const r=refs(uid,key);
 return db.runTransaction(async tx=>{
  const [s,existing,c,solution,p]=await Promise.all([tx.get(r.session),tx.get(r.result),tx.get(r.challenge),tx.get(r.solution),tx.get(r.profile)]);
  if(existing.exists)return {...existing.data(),finished:true}; // Idempotent, no second award.
  if(key!==dayKey())throw new HttpsError('failed-precondition','Défi expiré.');
  if(!s.exists||!c.exists||!solution.exists||!p.exists)throw new HttpsError('failed-precondition','Partie indisponible.');
  const session=s.data(),now=Timestamp.now();
  if(session.status!=='active')throw new HttpsError('failed-precondition','Partie terminée.');
  if(session.lastAnswerAt && now.toMillis()-session.lastAnswerAt.toMillis()<700)throw new HttpsError('resource-exhausted','Attends un instant.');
  const outcome=resolveAttempt({word:solution.data().wordFull,answer,difficulty:c.data().difficulty,startedAtMs:session.startedAt.toMillis(),nowMs:now.toMillis(),usedHint:session.usedHint,abandon});
  if(!outcome.finished){tx.update(r.session,{wrongAnswers:FieldValue.increment(1),lastAnswerAt:now});return outcome;}
  const result={...outcome,userId:uid,cardId:c.data().cardId,dailyKey:key,mode:'daily',createdAt:now,wordFull:solution.data().wordFull};
  tx.create(r.result,result);tx.create(db.doc(`attempts/${uid}_${key}`),result);tx.update(r.session,{status:'completed',lastAnswerAt:now});
  const profile=p.data(),streak=outcome.correct?(profile.lastDailyWin===previousKey(key)?(profile.currentStreak??0)+1:1):0;
  const update={score:FieldValue.increment(outcome.points),gamesPlayed:FieldValue.increment(1),correctAnswers:FieldValue.increment(outcome.correct?1:0),updatedAt:now};
  if(!outcome.correct)update.currentStreak=0;
  if(outcome.correct){update.currentStreak=streak;update.lastDailyWin=key;update.bestTimeMs=profile.bestTimeMs==null?outcome.timeMs:Math.min(profile.bestTimeMs,outcome.timeMs);}
  tx.update(r.profile,update);return result;
 });
});
