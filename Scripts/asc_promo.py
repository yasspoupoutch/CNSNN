#!/usr/bin/env python3
"""Changes only the promotional text of the App Store listing, on the version on sale (or, if none
is on sale yet, on the one being prepared). Apple lets this text change at any time without review,
so this never creates a version and never submits anything.

Usage: asc_promo.py KEY_ID ISSUER_ID KEY_PATH BUNDLE_ID LISTING_JSON
The text is "promotionalText" in LISTING_JSON, for its "locale".
"""
import base64, json, sys, time, urllib.error, urllib.parse, urllib.request
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

key_id, issuer, key_path, bundle, listing_path = sys.argv[1:6]
listing = json.load(open(listing_path, encoding='utf-8'))
text, locale = listing['promotionalText'], listing['locale']
if len(text) > 170:
    sys.exit(f'::error::Texte promotionnel trop long : {len(text)} caractères (170 au plus).')
API = 'https://api.appstoreconnect.apple.com'
# Versions whose promotional text can be changed, best first.
STATES = ['READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'PENDING_DEVELOPER_RELEASE', 'PREPARE_FOR_SUBMISSION']


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
    url = API + urllib.parse.quote(path, safe='/?=&[],')
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
    return attrs.get('appVersionState') or attrs.get('appStoreState')


apps = call('GET', f'/v1/apps?filter[bundleId]={bundle}')['data']
if not apps:
    sys.exit(f'::error::Aucune app {bundle} dans App Store Connect.')
versions = call('GET', f"/v1/apps/{apps[0]['id']}/appStoreVersions?filter[platform]=IOS&limit=20")['data']
version = next((v for s in STATES for v in versions if state(v) == s), None)
if version is None:
    states = ', '.join(f"{v['attributes']['versionString']} {state(v)}" for v in versions)
    sys.exit(f'::error::Aucune version dont le texte promotionnel peut changer ({states}).')
print(f"Version {version['attributes']['versionString']} ({state(version)})")

locs = call('GET', f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")['data']
loc = next((l for l in locs if l['attributes'].get('locale') == locale), None)
if loc is None:
    sys.exit(f'::error::Pas de fiche {locale} sur cette version.')
print(f"Avant : {loc['attributes'].get('promotionalText')}")
call('PATCH', f"/v1/appStoreVersionLocalizations/{loc['id']}", {'data': {
    'type': 'appStoreVersionLocalizations', 'id': loc['id'], 'attributes': {'promotionalText': text}}})
print(f'Après : {text}')
print('Texte promotionnel changé. Rien n’a été soumis à la revue.')
