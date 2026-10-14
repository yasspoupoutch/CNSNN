// Web account deletion (required by Google Play): signs in with email and password, deletes every
// document exactly like the apps (account.mjs), then the Firebase account. Nothing stays in the browser.
import { initializeApp } from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js';
import { initializeAuth, inMemoryPersistence, signInWithEmailAndPassword, deleteUser, signOut } from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js';
import * as fs from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-firestore.js';
import { deleteAccountData } from './account.mjs';

const form = document.getElementById('delete');
const status = document.getElementById('status');
const submit = document.getElementById('submit');
const say = (text, kind = '') => { status.textContent = text; status.className = 'status ' + kind; };

// Firebase Hosting serves this project's public web configuration at this reserved address.
const config = fetch('/__/firebase/init.json').then((r) => { if (!r.ok) throw new Error('config'); return r.json(); });

const messages = {
  'auth/invalid-credential': 'Adresse ou mot de passe incorrect.',
  'auth/wrong-password': 'Adresse ou mot de passe incorrect.',
  'auth/user-not-found': 'Adresse ou mot de passe incorrect.',
  'auth/invalid-email': 'Cette adresse email n’est pas valide.',
  'auth/too-many-requests': 'Trop de tentatives. Réessayez dans quelques minutes.',
  'auth/network-request-failed': 'Pas de connexion. Vérifiez le réseau puis réessayez.',
};

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!document.getElementById('confirm').checked) return;
  submit.disabled = true;
  say('Suppression en cours…');
  let auth;
  try {
    const app = initializeApp(await config);
    auth = initializeAuth(app, { persistence: inMemoryPersistence });
    const { user } = await signInWithEmailAndPassword(auth, document.getElementById('email').value.trim(), document.getElementById('password').value);
    await deleteAccountData(fs.getFirestore(app), user.uid, fs);
    await deleteUser(user);
    form.reset();
    say('Votre compte et toutes vos données ont été supprimés. Vous pouvez désinstaller l’application.', 'ok');
  } catch (error) {
    console.error(error);
    say(messages[error?.code] ?? 'La suppression n’a pas abouti. Réessayez, ou écrivez à jeucnsnn@gmail.com.', 'error');
    if (auth?.currentUser) await signOut(auth).catch(() => {});
  } finally {
    submit.disabled = false;
  }
});
