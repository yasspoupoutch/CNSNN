// Firestore use against the free Spark quota (50,000 reads, 20,000 writes, 20,000 deletes a day), day by
// day over the last week, from Cloud Monitoring. Prints counts only, never data: run logs become public
// whenever the repository is. Exits with an error past WARN of a daily quota, so the run fails and
// GitHub sends its failure email. Needs GOOGLE_APPLICATION_CREDENTIALS with monitoring read access.
import { applicationDefault } from 'firebase-admin/app';

const PROJECT = 'cnsnn-9ctosy';
const WARN = 0.6;
const QUOTAS = { read: 50_000, write: 20_000, delete: 20_000 };
const DAY = 86_400_000;

const { access_token: token } = await applicationDefault().getAccessToken();
// The quota resets at midnight Pacific time: count whole Pacific days.
const pacificOffset = (date) => {
    const local = new Date(date.toLocaleString('en-US', { timeZone: 'America/Los_Angeles' }));
    return date.getTime() - local.getTime();
};
const now = new Date();
const todayPacific = new Date(now.toLocaleString('en-US', { timeZone: 'America/Los_Angeles' }));
todayPacific.setHours(0, 0, 0, 0);
const end = new Date(todayPacific.getTime() + pacificOffset(now) + DAY);
const start = new Date(end.getTime() - 7 * DAY);

async function perDay(kind) {
    const params = new URLSearchParams({
        filter: `metric.type="firestore.googleapis.com/document/${kind}_count"`,
        'interval.startTime': start.toISOString(),
        'interval.endTime': end.toISOString(),
        'aggregation.alignmentPeriod': '86400s',
        'aggregation.perSeriesAligner': 'ALIGN_SUM',
        'aggregation.crossSeriesReducer': 'REDUCE_SUM',
    });
    const response = await fetch(`https://monitoring.googleapis.com/v3/projects/${PROJECT}/timeSeries?${params}`, {
        headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
        console.error(`Cloud Monitoring a refusé la lecture (${response.status}).`);
        if (response.status === 403) console.error("Le compte de service doit avoir le rôle « Lecteur Monitoring » (roles/monitoring.viewer).");
        process.exit(1);
    }
    const body = await response.json();
    const days = new Map();
    for (const series of body.timeSeries ?? []) {
        for (const point of series.points ?? []) {
            const day = point.interval.endTime.slice(0, 10);
            days.set(day, (days.get(day) ?? 0) + Number(point.value.int64Value ?? 0));
        }
    }
    return days;
}

const counts = Object.fromEntries(await Promise.all(Object.keys(QUOTAS).map(async (kind) => [kind, await perDay(kind)])));
const days = [...new Set(Object.values(counts).flatMap((map) => [...map.keys()]))].sort();
let worst = 0;
console.log('Jour (fin, UTC) | lectures | écritures | suppressions');
for (const day of days) {
    const cells = Object.entries(QUOTAS).map(([kind, quota]) => {
        const value = counts[kind].get(day) ?? 0;
        worst = Math.max(worst, value / quota);
        return `${value} (${Math.round((100 * value) / quota)} %)`;
    });
    console.log(`${day} | ${cells.join(' | ')}`);
}
if (days.length === 0) console.log('Aucune activité Firestore mesurée sur 7 jours.');
console.log(`Pic sur 7 jours : ${Math.round(worst * 100)} % d'un quota journalier gratuit.`);
if (worst >= WARN) {
    console.log(`::error::Firestore a dépassé ${WARN * 100} % d'un quota journalier gratuit : prévoir de réduire les lectures ou de passer au plan Blaze.`);
    process.exit(2);
}
