// Private key of the iPhone app's Apple Distribution certificate, made for GitHub Actions.
// Like the Android key, it lives in this public repository only encrypted with the daily words'
// public key (Firebase/daily/public.pem): only the GitHub secret FIREBASE_SERVICE_ACCOUNT can open
// it, in CI. Keeping the same key lets every TestFlight run reuse one certificate.
//
//   node Scripts/ios-signing/signing.mjs encrypt key.pem   (local, once)
//   node Scripts/ios-signing/signing.mjs decrypt OUT.pem   (CI)
import { readFile, writeFile } from 'node:fs/promises';
import { createPublicKey } from 'node:crypto';
import { encrypt, decrypt } from '../../Firebase/tools/daily.mjs';

const boxFile = new URL('./distribution.enc.json', import.meta.url);
const publicKeyFile = new URL('../../Firebase/daily/public.pem', import.meta.url);

const [command, file] = process.argv.slice(2);
if (command === 'encrypt') {
  const key = await readFile(file, 'utf8');
  const box = encrypt([{ key }], createPublicKey(await readFile(publicKeyFile, 'utf8')));
  await writeFile(boxFile, JSON.stringify(box, null, 1) + '\n');
  console.log('Clé chiffrée dans Scripts/ios-signing/distribution.enc.json');
} else if (command === 'decrypt' && file) {
  const path = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!path) throw new Error('GOOGLE_APPLICATION_CREDENTIALS manquant');
  const { private_key: privateKey } = JSON.parse(await readFile(path, 'utf8'));
  const [{ key }] = decrypt(JSON.parse(await readFile(boxFile, 'utf8')), privateKey);
  await writeFile(file, key, { mode: 0o600 });
  console.log('Clé de distribution prête.');
} else {
  console.error('Usage : signing.mjs encrypt <key.pem> | decrypt <out.pem>');
  process.exit(1);
}
