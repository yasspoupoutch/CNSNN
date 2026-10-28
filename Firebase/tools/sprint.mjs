// Sprint ranking (iOS 1.3.1): the best Sprints played before it, imported once from the players' synced
// progress. They were never checked by the server; every later record is (see sprintRecords in the rules).

// Same as the rules' sprintRank: the words, then the earliest game first.
export const sprintRank = (best, startedAtMs) => best * 10000000000000 + (9999999999999 - startedAtMs);

/** The ranking line of an old best Sprint, or null when the progress holds none. */
export function legacySprintRecord(uid, username, progressJson, savedAtMs) {
  let best = 0;
  try { best = JSON.parse(progressJson)?.modes?.sprint?.best?.words ?? 0; } catch { return null; }
  if (!Number.isInteger(best) || best < 1 || typeof username !== 'string' || !username) return null;
  // The rules never accept more than 60 words in 90 s: an old value above it is kept at 60.
  best = Math.min(best, 60);
  return { uid, username, best, rank: sprintRank(best, savedAtMs), startedAtMs: savedAtMs };
}

/**
 * Imports the old records once: a marker (meta/sprintImport) stops any later run, since the synced
 * progress is written by the players themselves. Lines already there are left alone.
 */
export async function importSprintRecords(db, Timestamp, FieldValue) {
  const marker = db.doc('meta/sprintImport');
  if ((await marker.get()).exists) return { skipped: true, imported: 0 };
  const names = new Map((await db.collection('users').select('username').get()).docs.map((d) => [d.id, d.get('username')]));
  const banned = new Set((await db.collection('banned').select().get()).docs.map((d) => d.id));
  let imported = 0;
  for (const [uid, username] of names) {
    const progress = await db.doc(`users/${uid}/private/progress`).get();
    const json = progress.get('json');
    if (typeof json !== 'string') continue;
    const savedAtMs = progress.get('updatedAt')?.toMillis?.() ?? Date.now();
    const record = legacySprintRecord(uid, username, json, savedAtMs);
    if (!record) continue;
    const ref = db.doc(`sprintRecords/${uid}`);
    if ((await ref.get()).exists) continue;
    const { startedAtMs, ...line } = record;
    const at = Timestamp.fromMillis(startedAtMs);
    await ref.create({ ...line, startedAt: at, at, ...(banned.has(uid) ? { suspended: true } : {}) });
    imported++;
  }
  await marker.create({ importedAt: FieldValue.serverTimestamp(), imported });
  return { skipped: false, imported };
}
