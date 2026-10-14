// Release signing key of the Android app. It lives in this public repository only encrypted
// with the same public key as the daily words (Firebase/daily/public.pem): only the GitHub secret
// FIREBASE_SERVICE_ACCOUNT can open it, in CI. A stable key lets each new APK install over the old one.
//
//   node Android/signing/signing.mjs encrypt release.p12 PASSWORD   (local, once)
//   node Android/signing/signing.mjs decrypt                         (CI: exports the key to the build)
import { readFile, writeFile, appendFile } from 'node:fs/promises';
import { createPublicKey } from 'node:crypto';
import { encrypt, decrypt } from '../../Firebase/tools/daily.mjs';

const boxFile = new URL('./release.enc.json', import.meta.url);
const publicKeyFile = new URL('../../Firebase/daily/public.pem', import.meta.url);

const [command, file, password] = process.argv.slice(2);
if (command === 'encrypt') {
  const keystore = (await readFile(file)).toString('base64');
  const box = encrypt([{ keystore, password }], createPublicKey(await readFile(publicKeyFile, 'utf8')));
  await writeFile(boxFile, JSON.stringify(box, null, 1) + '\n');
  console.log('Clé chiffrée dans Android/signing/release.enc.json');
} else if (command === 'decrypt') {
  const path = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!path) throw new Error('GOOGLE_APPLICATION_CREDENTIALS manquant');
  const { private_key: privateKey } = JSON.parse(await readFile(path, 'utf8'));
  const [{ keystore, password: pass }] = decrypt(JSON.parse(await readFile(boxFile, 'utf8')), privateKey);
  // Masked in the logs, then handed to the next steps only.
  console.log(`::add-mask::${pass}`);
  await appendFile(process.env.GITHUB_ENV, `ANDROID_KEYSTORE_PASSWORD=${pass}\nANDROID_KEYSTORE_BASE64<<KEYSTORE_EOF\n${keystore}\nKEYSTORE_EOF\n`);
  console.log('Clé de signature prête.');
} else {
  console.error('Usage : signing.mjs encrypt <fichier.p12> <mot de passe> | decrypt');
  process.exit(1);
}
