// Registers the Android app in the Firebase project (once) and prints its google-services.json,
// which holds only public identifiers. Needs GOOGLE_APPLICATION_CREDENTIALS.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getProjectManagement } from 'firebase-admin/project-management';

const packageName = 'com.poupoutch.cnsnn';
initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const management = getProjectManagement();
const apps = await management.listAndroidApps();
let app;
for (const candidate of apps) {
  if ((await candidate.getMetadata()).packageName === packageName) app = candidate;
}
if (!app) {
  app = await management.createAndroidApp(packageName, 'CNSNN Android');
  console.log(`Application Android créée : ${packageName}`);
} else {
  console.log(`Application Android déjà enregistrée : ${packageName}`);
}
console.log('----- google-services.json -----');
console.log(await app.getConfig());
console.log('----- fin -----');
