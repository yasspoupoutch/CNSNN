// Grants the moderator role to one Firebase Auth user: the signed `admin` claim and an
// admins/{uid} document (read by the app and the rules). Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const uid = process.argv[2];
if (!uid || !/^[A-Za-z0-9]{10,128}$/.test(uid)) { console.error('UID invalide.'); process.exit(1); }
initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const user = await getAuth().getUser(uid);
await getAuth().setCustomUserClaims(uid, { ...(user.customClaims ?? {}), admin: true });
await getFirestore().doc(`admins/${uid}`).set({ grantedAt: FieldValue.serverTimestamp() });
// No email in the log: run logs become public whenever the repository is.
console.log(`Administrateur ajouté : ${uid} (${user.email ? 'compte avec email' : 'compte invité'})`);
