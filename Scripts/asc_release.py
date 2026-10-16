#!/usr/bin/env python3
"""Shows, then optionally sets, what the version being prepared still needs before review:
build, age rating and price. Never submits anything to Apple review.

Usage: asc_release.py KEY_ID ISSUER_ID KEY_PATH BUNDLE_ID [--apply]
Without --apply it only reads and prints the current state.
"""
import base64, json, sys, time, urllib.error, urllib.parse, urllib.request
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

key_id, issuer, key_path, bundle = sys.argv[1:5]
APPLY = '--apply' in sys.argv[5:]
API = 'https://api.appstoreconnect.apple.com'
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'}
# Age rating: nothing sensitive in CNSNN. Players do create content (usernames shown in rankings,
# cards proposed then moderated), with reporting and blocking. No chat, no ads, no web browser.
FREQUENCY_NONE = ['alcoholTobaccoOrDrugUseOrReferences', 'contests', 'gamblingSimulated', 'gunsOrOtherWeapons',
                  'horrorOrFearThemes', 'matureOrSuggestiveThemes', 'medicalOrTreatmentInformation',
                  'profanityOrCrudeHumor', 'sexualContentGraphicAndNudity', 'sexualContentOrNudity',
                  'violenceCartoonOrFantasy', 'violenceRealistic', 'violenceRealisticProlongedGraphicOrSadistic']
NO = ['advertising', 'ageAssurance', 'gambling', 'healthOrWellnessTopics', 'lootBox', 'messagingAndChat',
      'parentalControls', 'socialMedia', 'socialMediaAgeRestricted', 'unrestrictedWebAccess']
YES = ['userGeneratedContent']


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def token():
    key = serialization.load_pem_private_key(open(key_path, 'rb').read(), password=None)
    head = b64(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode())
    now = int(time.time())
    body = b64(json.dumps({'iss': issuer, 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'}).encode())
    r, s = decode_dss_signature(key.sign(f'{head}.{body}'.encode(), ec.ECDSA(hashes.SHA256())))
    return f'{head}.{body}.' + b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


AUTH = token()


def call(method, path, body=None):
    """Returns the decoded JSON, or None after printing Apple's error."""
    url = API + urllib.parse.quote(path, safe='/?=&[],-')
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={'Authorization': f'Bearer {AUTH}', 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        errors = json.loads(err.read() or b'{}').get('errors', [])
        detail = '; '.join(f"{e.get('code')} {e.get('title')} {e.get('detail', '')}" for e in errors)
        print(f'::warning::{method} {path} -> {err.code} {detail}')
        return None


def state(item):
    attrs = item['attributes']
    return attrs.get('appVersionState') or attrs.get('state') or attrs.get('appStoreState')


app = call('GET', f'/v1/apps?filter[bundleId]={bundle}')['data'][0]
versions = call('GET', f"/v1/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=20")['data']
version = next(v for v in versions if state(v) in EDITABLE)
infos = call('GET', f"/v1/apps/{app['id']}/appInfos")['data']
info = next((i for i in infos if state(i) in EDITABLE), infos[0])
print(f"Mode : {'application des réglages' if APPLY else 'lecture seule'}")
print(f"Version {version['attributes']['versionString']} ({state(version)})")

# Build.
current = (call('GET', f"/v1/appStoreVersions/{version['id']}/build") or {}).get('data')
builds = call('GET', f"/v1/builds?filter[app]={app['id']}&sort=-uploadedDate&limit=5") or {'data': []}
print('Builds envoyées : ' + ', '.join(
    f"{b['attributes']['version']} ({b['attributes'].get('processingState')})" for b in builds['data']))
print('Build choisie : ' + (current['attributes']['version'] if current else 'aucune'))
valid = next((b for b in builds['data'] if b['attributes'].get('processingState') == 'VALID'
              and not b['attributes'].get('expired')), None)
if APPLY and valid and (current is None or current['id'] != valid['id']):
    if call('PATCH', f"/v1/appStoreVersions/{version['id']}", {'data': {
            'type': 'appStoreVersions', 'id': version['id'],
            'relationships': {'build': {'data': {'type': 'builds', 'id': valid['id']}}}}}) is not None:
        print(f"Build {valid['attributes']['version']} attachée à la version.")

# Age rating.
rating = (call('GET', f"/v1/appInfos/{info['id']}/ageRatingDeclaration") or {}).get('data')
if rating:
    attrs = rating['attributes']
    print('Classification actuelle : ' + json.dumps(attrs, ensure_ascii=False, sort_keys=True))
    answers = {key: 'NONE' for key in FREQUENCY_NONE if key in attrs}
    answers.update({key: False for key in NO if key in attrs})
    answers.update({key: True for key in YES if key in attrs})
    if APPLY and call('PATCH', f"/v1/ageRatingDeclarations/{rating['id']}", {'data': {
            'type': 'ageRatingDeclarations', 'id': rating['id'], 'attributes': answers}}) is not None:
        print('Classification enregistrée : ' + json.dumps(answers, ensure_ascii=False, sort_keys=True))
    after = (call('GET', f"/v1/appInfos/{info['id']}") or {}).get('data', {}).get('attributes', {})
    print('Âge calculé par Apple : ' + str({k: v for k, v in after.items() if 'age' in k.lower() or 'rating' in k.lower()}))

# Price.
schedule = call('GET', f"/v1/apps/{app['id']}/appPriceSchedule?include=manualPrices,baseTerritory")
prices = (schedule or {}).get('included', [])
print('Prix actuel : ' + (json.dumps([p.get('attributes') for p in prices], ensure_ascii=False) if prices else 'non défini'))
if APPLY and not any(p['type'] == 'appPrices' for p in prices):
    points = call('GET', f"/v1/apps/{app['id']}/appPricePoints?filter[territory]=FRA&limit=200") or {'data': []}
    free = next((pt for pt in points['data'] if float(pt['attributes'].get('customerPrice') or 1) == 0), None)
    if free is None:
        print('::warning::Prix gratuit introuvable.')
    elif call('POST', '/v1/appPriceSchedules', {
            'data': {'type': 'appPriceSchedules', 'relationships': {
                'app': {'data': {'type': 'apps', 'id': app['id']}},
                'baseTerritory': {'data': {'type': 'territories', 'id': 'FRA'}},
                'manualPrices': {'data': [{'type': 'appPrices', 'id': '${free}'}]}}},
            'included': [{'type': 'appPrices', 'id': '${free}', 'attributes': {'startDate': None},
                          'relationships': {'appPricePoint': {'data': {'type': 'appPricePoints', 'id': free['id']}}}}]}) is not None:
        print('Prix : gratuit.')

# Availability: every country, and new ones as Apple adds them, if nothing is set yet.
availability = call('GET', f"/v1/apps/{app['id']}/appAvailabilityV2")
print('Disponibilité : ' + ('déjà définie' if availability and availability.get('data') else 'non définie'))
if APPLY and not (availability and availability.get('data')):
    territories = call('GET', '/v1/territories?limit=200') or {'data': []}
    items = [{'type': 'territoryAvailabilities', 'id': f"${{{t['id']}}}", 'attributes': {'available': True},
              'relationships': {'territory': {'data': {'type': 'territories', 'id': t['id']}}}}
             for t in territories['data']]
    if items and call('POST', '/v2/appAvailabilities', {
            'data': {'type': 'appAvailabilities', 'attributes': {'availableInNewTerritories': True},
                     'relationships': {'app': {'data': {'type': 'apps', 'id': app['id']}},
                                       'territoryAvailabilities': {'data': [
                                           {'type': i['type'], 'id': i['id']} for i in items]}}},
            'included': items}) is not None:
        print(f'Disponibilité : {len(items)} pays.')

print('Rien n’a été soumis à la revue.')
