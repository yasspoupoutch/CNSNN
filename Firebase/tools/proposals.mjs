// Every community word proposal (pending, approved or refused) with its author, dates and status,
// and each author's anti-spam counters (last proposal, proposals in the current 24 h window).
// Read-only. Printed only encrypted for the given public key (the logs may become public).
// Costs about one read per proposal plus one per author.
// Usage: proposals.mjs key.pem   Needs GOOGLE_APPLICATION_CREDENTIALS.
import { readFile } from 'node:fs/promises';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { encrypt } from './daily.mjs';

const publicKey = await readFile(process.argv[2], 'utf8');
initializeApp({ credential: applicationDefault(), projectId: 'cnsnn-9ctosy' });
const db = getFirestore();
const iso = (t) => (t?.toDate ? t.toDate().toISOString() : null);

const cards = (await db.collection('cards').where('createdBy', '>', '').get()).docs;
const authors = [...new Set(cards.map((c) => c.get('createdBy')).filter((u) => u && u !== 'deleted'))];
const profiles = authors.length ? await db.getAll(...authors.map((u) => db.doc(`users/${u}`)),
  { fieldMask: ['username', 'lastProposalAt', 'proposalWindowAt', 'proposalCount'] }) : [];
const byUid = new Map(profiles.map((p) => [p.id, p]));

const rows = cards.map((c) => ({
  id: c.id, word: c.get('wordFull'), status: c.get('status'), author: c.get('authorName') ?? byUid.get(c.get('createdBy'))?.get('username') ?? null,
  uid: c.get('createdBy'), createdAt: iso(c.get('createdAt')), reviewedAt: iso(c.get('reviewedAt')),
  category: c.get('category'), difficulty: c.get('difficulty'), hint: c.get('hint'),
})).sort((a, b) => (a.createdAt ?? '').localeCompare(b.createdAt ?? ''));
const quotas = profiles.filter((p) => p.exists).map((p) => ({
  uid: p.id, username: p.get('username'), lastProposalAt: iso(p.get('lastProposalAt')),
  proposalWindowAt: iso(p.get('proposalWindowAt')), proposalCount: p.get('proposalCount') ?? null,
}));

const counts = rows.reduce((m, r) => ({ ...m, [r.status]: (m[r.status] ?? 0) + 1 }), {});
console.log(`Propositions : ${rows.length} (${Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(', ')}), auteurs : ${authors.length}`);
console.log('PROPOSALS_ENCRYPTED ' + JSON.stringify(encrypt({ rows, quotas }, publicKey)));
