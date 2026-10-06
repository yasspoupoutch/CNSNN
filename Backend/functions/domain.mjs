export function normalize(value) {
  return String(value).replace(/œ/gi,'oe').replace(/æ/gi,'ae').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z]/g,'');
}
export function consonants(word) { return normalize(word).replace(/[AEIOUY]/g,''); }
export function points(difficulty, timeMs, usedHint, correct) {
  if (!correct) return 0;
  const base = {Facile:50,Moyen:100,Difficile:150}[difficulty];
  if (!base) throw new Error('Invalid difficulty');
  return Math.floor((base + Math.max(0,50-Math.floor(Math.max(0,timeMs)/1000))) / (usedHint ? 2 : 1));
}
export function dayKey(date=new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);
  const get = type=>parts.find(p=>p.type===type).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}
export function previousKey(key) {
  const date = new Date(`${key}T12:00:00Z`);date.setUTCDate(date.getUTCDate()-1);return date.toISOString().slice(0,10);
}
export function resolveAttempt({word,answer,difficulty,startedAtMs,nowMs,usedHint,abandon=false}) {
  const correct = !abandon && normalize(answer).length>0 && normalize(answer)===normalize(word);
  if (!correct && !abandon) return {finished:false,correct:false};
  const timeMs = Math.max(0,nowMs-startedAtMs);
  return {finished:true,correct,timeMs,points:points(difficulty,timeMs,usedHint,correct)};
}
