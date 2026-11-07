// Read-only check for one account, to help a player who cannot sign in or receive the reset email.
// Prints whether the email has an account, how it signs in, dates and pseudo, and whether Firebase's
// email enumeration protection is on (then "mot de passe oublié" never says when an email is unknown).
// Never prints the email itself (the logs may become public). Costs one read.
// Usage: account-check.mjs   with ACCOUNT_EMAIL set. Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const auth = getAuth();
const email = (process.env.ACCOUNT_EMAIL ?? '').trim().toLowerCase();
if (!email.includes('@')) { console.error('Adresse e-mail manquante ou invalide.'); process.exit(1); }

try {
  const config = await auth.projectConfigManager().getProjectConfig();
  const on = config.emailPrivacyConfig?.enableImprovedEmailPrivacy;
  console.log(`Protection contre l'énumération des e-mails : ${on ? 'ACTIVE (un e-mail inconnu ne donne aucune erreur ni aucun mail)' : on === false ? 'inactive' : 'inconnue'}`);
} catch (e) { console.log(`Protection contre l'énumération des e-mails : illisible (${e.code ?? e.message})`); }

let user;
try { user = await auth.getUserByEmail(email); } catch (e) {
  if (e.code === 'auth/user-not-found') {
    console.log('Compte : AUCUN compte avec cette adresse (aucun mail de réinitialisation ne peut partir).');
    const sameLocal = [];
    let pageToken;
    const local = email.split('@')[0];
    do {
      const page = await auth.listUsers(1000, pageToken);
      for (const u of page.users) if (u.email && u.email.split('@')[0] === local) sameLocal.push(u.email.split('@')[1]);
      pageToken = page.pageToken;
    } while (pageToken);
    console.log(sameLocal.length ? `Même identifiant avec un autre domaine : @${sameLocal.join(', @')}` : 'Aucun compte avec le même identifiant sur un autre domaine.');
    process.exit(0);
  }
  throw e;
}
const providers = user.providerData.map((p) => p.providerId).join(', ') || 'aucun';
console.log('Compte : TROUVÉ');
console.log(`Connexion : ${providers}`);
console.log(`E-mail vérifié : ${user.emailVerified ? 'oui' : 'non'} · Désactivé : ${user.disabled ? 'OUI' : 'non'}`);
console.log(`Créé : ${user.metadata.creationTime} · Dernière connexion : ${user.metadata.lastSignInTime ?? 'jamais'}`);
const profile = await getFirestore().doc(`users/${user.uid}`).get();
console.log(`Pseudo : ${profile.exists ? profile.get('username') ?? '(sans pseudo)' : '(pas de profil)'}`);
