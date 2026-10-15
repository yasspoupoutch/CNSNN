// Deletes everything a player stored, exactly like the apps (App/Firebase/FirebaseRepository.swift
// deleteAccount, Android CloudRepository.deleteAccount). Used by suppression.html and its tests.
// `fs` holds the Firestore functions (from the browser SDK or from npm), so both share this code.

/** Commits writes in order, 400 per batch (Firestore allows 500). */
async function commit(db, fs, writes) {
  for (let i = 0; i < writes.length; i += 400) {
    const batch = fs.writeBatch(db);
    for (const write of writes.slice(i, i + 400)) write(batch);
    await batch.commit();
  }
}

export async function deleteAccountData(db, uid, fs) {
  const { doc, collection, query, where, getDocs } = fs;
  const owned = async (name, field = 'userId') => (await getDocs(query(collection(db, name), where(field, '==', uid)))).docs;
  const refs = [doc(db, 'users', uid), doc(db, 'users', uid, 'private', 'progress'), doc(db, 'leaderboard', uid)];
  refs.push(...(await getDocs(collection(db, 'users', uid, 'friends'))).docs.map((d) => d.ref));
  refs.push(...(await owned('friendCodes', 'uid')).map((d) => d.ref));
  for (const name of ['dailyResults', 'dailySessions', 'reports', 'playerReports']) refs.push(...(await owned(name)).map((d) => d.ref));
  // Friend challenges, sent or received: they carry the player's name.
  for (const field of ['from', 'to']) refs.push(...(await owned('challenges', field)).map((d) => d.ref));
  // Approved cards stay in the game without the author's name or id; the other proposals go.
  const authored = await owned('cards', 'createdBy');
  refs.push(...authored.filter((d) => d.data().status !== 'approved').map((d) => d.ref));
  const live = authored.filter((d) => d.data().status === 'approved').map((d) => d.ref);
  // The profile goes first, with the tombstone that lets friends drop this account and the
  // suspension record: the rules only let the daily history and the rest go once it is gone.
  // The tombstone can only be created once, so a deletion cut off halfway resumes without it.
  const tombstone = doc(db, 'deletedUsers', uid);
  const resumed = (await fs.getDoc(tombstone)).exists();
  await commit(db, fs, [
    ...(resumed ? [] : [(b) => b.set(tombstone, { deletedAt: fs.serverTimestamp() })]),
    (b) => b.delete(doc(db, 'banned', uid)),
    ...refs.map((ref) => (b) => b.delete(ref)),
    ...live.map((ref) => (b) => b.update(ref, { createdBy: 'deleted', authorName: fs.deleteField() })),
  ]);
  // Reports naming this player can only be read once the profile is gone.
  const about = await owned('playerReports', 'playerId');
  await commit(db, fs, about.map((d) => (b) => b.delete(d.ref)));
  return { documents: refs.length + about.length + 2, anonymizedCards: live.length, resumed };
}
