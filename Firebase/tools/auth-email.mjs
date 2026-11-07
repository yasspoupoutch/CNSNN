// The Firebase Auth emails ("mot de passe oublié"): show their current settings, or apply ours.
// show  : prints sender name, reply-to, subject, language and whether the text was customised. Read-only.
// apply : sets them from auth-email.json (main only, production change).
// Usage: auth-email.mjs show|apply   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { readFile } from 'node:fs/promises';
import { applicationDefault } from 'firebase-admin/app';

const url = 'https://identitytoolkit.googleapis.com/admin/v2/projects/cnsnn-9ctosy/config';
const { access_token: token } = await applicationDefault().getAccessToken();
const call = async (method, target, body) => {
  const res = await fetch(target, { method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', 'x-goog-user-project': 'cnsnn-9ctosy' }, body: body && JSON.stringify(body) });
  const json = await res.json();
  if (!res.ok) { console.error(`Erreur ${res.status} : ${json.error?.message ?? JSON.stringify(json)}`); process.exit(1); }
  return json;
};
const show = (config) => {
  const n = config.notification ?? {};
  const t = n.sendEmail?.resetPasswordTemplate ?? {};
  console.log(`Expéditeur : ${t.senderDisplayName || '(vide)'} <${t.senderLocalPart || 'noreply'}@cnsnn-9ctosy.firebaseapp.com>`);
  console.log(`Répondre à : ${t.replyTo || '(aucun)'}`);
  console.log(`Objet : ${t.subject || '(défaut)'}`);
  console.log(`Langue par défaut : ${n.defaultLocale || '(aucune, anglais)'}`);
  console.log(`Texte personnalisé : ${t.customized ? 'oui' : 'non'} · format ${t.bodyFormat ?? '?'}`);
  console.log(`Lien d'action : ${n.sendEmail?.callbackUri || '(défaut firebaseapp.com)'}`);
  console.log(`Méthode d'envoi : ${n.sendEmail?.method ?? '?'}`);
  console.log('--- texte actuel ---');
  console.log(t.body ?? '(aucun)');
  console.log(`Protection énumération e-mails : ${config.emailPrivacyConfig?.enableImprovedEmailPrivacy ? 'active' : 'inactive'}`);
};

const mode = process.argv[2];
if (mode === 'show') show(await call('GET', url));
else if (mode === 'apply') {
  const wanted = JSON.parse(await readFile(new URL('./auth-email.json', import.meta.url), 'utf8'));
  const masks = ['notification.defaultLocale', ...Object.keys(wanted.resetPasswordTemplate).map((k) => `notification.sendEmail.resetPasswordTemplate.${k}`)];
  const body = { notification: { defaultLocale: wanted.defaultLocale, sendEmail: { resetPasswordTemplate: wanted.resetPasswordTemplate } } };
  show(await call('PATCH', `${url}?updateMask=${masks.join(',')}`, body));
} else { console.error('Usage : auth-email.mjs show|apply'); process.exit(1); }
