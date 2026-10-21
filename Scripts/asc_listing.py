#!/usr/bin/env python3
"""Fills the App Store listing of the version being prepared (created from "version" in LISTING_JSON
when none is): texts, category, copyright and iPhone 6.9" screenshots. Never submits anything to Apple review.

Usage: asc_listing.py KEY_ID ISSUER_ID KEY_PATH BUNDLE_ID LISTING_JSON SCREENSHOT_DIR [PREVIEW_MP4]
The screenshots are SCREENSHOT_DIR/<name>.png, in the order of "screenshots" in LISTING_JSON. The
optional PREVIEW_MP4 becomes the iPhone 6.9" app preview video (886 x 1920, 15 to 30 s).
Running it again replaces the texts and the screenshots: it is safe to repeat.
"""
import base64, hashlib, json, os, sys, time, urllib.error, urllib.parse, urllib.request
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

key_id, issuer, key_path, bundle, listing_path, shots_dir = sys.argv[1:7]
preview_path = sys.argv[7] if len(sys.argv) > 7 and os.path.exists(sys.argv[7]) else None
listing = json.load(open(listing_path, encoding='utf-8'))
API = 'https://api.appstoreconnect.apple.com'
# Apple's API names the 6.9" iPhone slot APP_IPHONE_67; it takes 1320 x 2868 screenshots.
DISPLAY = 'APP_IPHONE_67'
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'}


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
    url = path if path.startswith('http') else API + urllib.parse.quote(path, safe='/?=&[],')
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
        sys.exit(f'::error::{method} {path} -> {err.code} {detail}')


def state(item):
    attrs = item['attributes']
    return attrs.get('appVersionState') or attrs.get('state') or attrs.get('appStoreState')


def first(items, **match):
    return next((i for i in items if all(i['attributes'].get(k) == v for k, v in match.items())), None)


# The app and the version being prepared (created as 1.0 if none exists yet).
apps = call('GET', f'/v1/apps?filter[bundleId]={bundle}')['data']
if not apps:
    sys.exit(f'::error::Aucune app {bundle} dans App Store Connect.')
app = apps[0]
print(f"App : {app['attributes']['name']} ({app['id']}), langue principale {app['attributes'].get('primaryLocale')}")

versions = call('GET', f"/v1/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=20")['data']
version = next((v for v in versions if state(v) in EDITABLE), None)
if version is None:
    # The next version ("version" in LISTING_JSON) is created once the previous one is on sale.
    wanted = listing.get('version', '1.0')
    if any(v['attributes']['versionString'] == wanted for v in versions):
        states = ', '.join(f"{v['attributes']['versionString']} {state(v)}" for v in versions)
        sys.exit(f'::error::Aucune version modifiable et la {wanted} existe déjà ({states}).')
    version = call('POST', '/v1/appStoreVersions', {'data': {
        'type': 'appStoreVersions',
        'attributes': {'platform': 'IOS', 'versionString': wanted},
        'relationships': {'app': {'data': {'type': 'apps', 'id': app['id']}}}}})['data']
    print(f'Version {wanted} créée.')
print(f"Version {version['attributes']['versionString']} ({state(version)})")
call('PATCH', f"/v1/appStoreVersions/{version['id']}", {'data': {
    'type': 'appStoreVersions', 'id': version['id'], 'attributes': {'copyright': listing['copyright']}}})

# App-level texts (name, subtitle, privacy policy) and the category, on the editable app info.
infos = call('GET', f"/v1/apps/{app['id']}/appInfos")['data']
info = next((i for i in infos if state(i) in EDITABLE), infos[0])
call('PATCH', f"/v1/appInfos/{info['id']}", {'data': {'type': 'appInfos', 'id': info['id'], 'relationships': {
    'primaryCategory': {'data': {'type': 'appCategories', 'id': listing['primaryCategory']}},
    'primarySubcategoryOne': {'data': {'type': 'appCategories', 'id': listing['primarySubcategoryOne']}},
    'primarySubcategoryTwo': {'data': {'type': 'appCategories', 'id': listing['primarySubcategoryTwo']}}}}})
print('Catégorie : Jeux > Mots, Puzzle')

locale = listing['locale']
info_attrs = {k: listing[k] for k in ('name', 'subtitle', 'privacyPolicyUrl')}
info_locs = call('GET', f"/v1/appInfos/{info['id']}/appInfoLocalizations")['data']
info_loc = first(info_locs, locale=locale)
if info_loc:
    call('PATCH', f"/v1/appInfoLocalizations/{info_loc['id']}", {'data': {
        'type': 'appInfoLocalizations', 'id': info_loc['id'], 'attributes': info_attrs}})
else:
    call('POST', '/v1/appInfoLocalizations', {'data': {
        'type': 'appInfoLocalizations', 'attributes': {'locale': locale, **info_attrs},
        'relationships': {'appInfo': {'data': {'type': 'appInfos', 'id': info['id']}}}}})
print(f'Nom, sous-titre et confidentialité ({locale}) enregistrés.')

# Version texts.
version_attrs = {k: listing[k] for k in ('description', 'keywords', 'promotionalText', 'supportUrl', 'marketingUrl')}
# "What's new" exists only from the second version on.
if listing.get('whatsNew') and version['attributes']['versionString'] != '1.0':
    version_attrs['whatsNew'] = listing['whatsNew']
version_locs = call('GET', f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")['data']
version_loc = first(version_locs, locale=locale)
if version_loc:
    call('PATCH', f"/v1/appStoreVersionLocalizations/{version_loc['id']}", {'data': {
        'type': 'appStoreVersionLocalizations', 'id': version_loc['id'], 'attributes': version_attrs}})
else:
    version_loc = call('POST', '/v1/appStoreVersionLocalizations', {'data': {
        'type': 'appStoreVersionLocalizations', 'attributes': {'locale': locale, **version_attrs},
        'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}}}}})['data']
print(f'Description, mots-clés et texte promotionnel ({locale}) enregistrés.')

# Screenshots: empty the 6.9" set, then upload in order.
sets = call('GET', f"/v1/appStoreVersionLocalizations/{version_loc['id']}/appScreenshotSets")['data']
shot_set = first(sets, screenshotDisplayType=DISPLAY)
if shot_set is None:
    shot_set = call('POST', '/v1/appScreenshotSets', {'data': {
        'type': 'appScreenshotSets', 'attributes': {'screenshotDisplayType': DISPLAY},
        'relationships': {'appStoreVersionLocalization': {'data': {
            'type': 'appStoreVersionLocalizations', 'id': version_loc['id']}}}}})['data']
for old in call('GET', f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots")['data']:
    call('DELETE', f"/v1/appScreenshots/{old['id']}")

for name in listing['screenshots']:
    path = os.path.join(shots_dir, f'{name}.png')
    data = open(path, 'rb').read()
    shot = call('POST', '/v1/appScreenshots', {'data': {
        'type': 'appScreenshots', 'attributes': {'fileName': f'{name}.png', 'fileSize': len(data)},
        'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': shot_set['id']}}}}})['data']
    for op in shot['attributes']['uploadOperations']:
        part = data[op['offset']:op['offset'] + op['length']]
        headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
        urllib.request.urlopen(urllib.request.Request(op['url'], data=part, method=op['method'], headers=headers),
                               timeout=120).read()
    call('PATCH', f"/v1/appScreenshots/{shot['id']}", {'data': {
        'type': 'appScreenshots', 'id': shot['id'],
        'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()}}})
    print(f'Capture envoyée : {name}.png')

# Apple processes the files for a few seconds; report the final state of each.
for _ in range(12):
    shots = call('GET', f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots")['data']
    states = [(s['attributes'].get('assetDeliveryState') or {}).get('state') for s in shots]
    if all(state in ('COMPLETE', 'FAILED') for state in states):
        break
    time.sleep(5)
print('État des captures : ' + ', '.join(f"{s['attributes']['fileName']} {st}" for s, st in zip(shots, states)))
if 'FAILED' in states or len(shots) != len(listing['screenshots']):
    sys.exit('::error::Une capture a été refusée par Apple.')

# App preview video: the same upload dance as the screenshots, in the 6.9" preview set. Apple
# processes the video for several minutes; its state is only reported here.
if preview_path:
    sets = call('GET', f"/v1/appStoreVersionLocalizations/{version_loc['id']}/appPreviewSets")['data']
    preview_set = first(sets, previewType='IPHONE_67')
    if preview_set is None:
        preview_set = call('POST', '/v1/appPreviewSets', {'data': {
            'type': 'appPreviewSets', 'attributes': {'previewType': 'IPHONE_67'},
            'relationships': {'appStoreVersionLocalization': {'data': {
                'type': 'appStoreVersionLocalizations', 'id': version_loc['id']}}}}})['data']
    for old in call('GET', f"/v1/appPreviewSets/{preview_set['id']}/appPreviews")['data']:
        call('DELETE', f"/v1/appPreviews/{old['id']}")
    data = open(preview_path, 'rb').read()
    preview = call('POST', '/v1/appPreviews', {'data': {
        'type': 'appPreviews', 'attributes': {'fileName': 'preview.mp4', 'fileSize': len(data), 'mimeType': 'video/mp4'},
        'relationships': {'appPreviewSet': {'data': {'type': 'appPreviewSets', 'id': preview_set['id']}}}}})['data']
    for op in preview['attributes']['uploadOperations']:
        part = data[op['offset']:op['offset'] + op['length']]
        headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
        urllib.request.urlopen(urllib.request.Request(op['url'], data=part, method=op['method'], headers=headers),
                               timeout=300).read()
    call('PATCH', f"/v1/appPreviews/{preview['id']}", {'data': {
        'type': 'appPreviews', 'id': preview['id'],
        'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()}}})
    for _ in range(24):
        state_now = (call('GET', f"/v1/appPreviews/{preview['id']}")['data']['attributes'].get('assetDeliveryState') or {}).get('state')
        if state_now in ('COMPLETE', 'FAILED'):
            break
        time.sleep(10)
    print(f'Aperçu vidéo envoyé : {state_now}')
    if state_now == 'FAILED':
        sys.exit('::error::Apple a refusé l’aperçu vidéo.')

print('Fiche prête. Rien n’a été soumis à la revue.')
