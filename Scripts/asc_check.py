#!/usr/bin/env python3
"""Checks what the App Store Connect API key may do, without changing anything.

Prints one line per endpoint: HTTP status and, on error, Apple's error code and title.
Usage: asc_check.py KEY_ID ISSUER_ID KEY_PATH BUNDLE_ID
"""
import base64, json, sys, time, urllib.error, urllib.parse, urllib.request
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

key_id, issuer, key_path, bundle = sys.argv[1:5]


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def token():
    key = serialization.load_pem_private_key(open(key_path, 'rb').read(), password=None)
    head = b64(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode())
    now = int(time.time())
    body = b64(json.dumps({'iss': issuer, 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}).encode())
    r, s = decode_dss_signature(key.sign(f'{head}.{body}'.encode(), ec.ECDSA(hashes.SHA256())))
    return f'{head}.{body}.' + b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


auth = token()
checks = [
    ('apps', f'/v1/apps?filter[bundleId]={bundle}'),
    ('bundleIds', f'/v1/bundleIds?filter[identifier]={bundle}'),
    ('certificates', '/v1/certificates?limit=20'),
    ('profiles', '/v1/profiles?limit=20'),
    ('devices', '/v1/devices?limit=5'),
]
for name, path in checks:
    req = urllib.request.Request('https://api.appstoreconnect.apple.com' + urllib.parse.quote(path, safe='/?=&[]'),
                                 headers={'Authorization': f'Bearer {auth}'})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            data = json.load(res).get('data', [])
            items = [d.get('attributes', {}) for d in data]
            detail = {
                'bundleIds': lambda: [i.get('identifier') for i in items],
                'certificates': lambda: [i.get('certificateType') for i in items],
                'profiles': lambda: [(i.get('name'), i.get('profileType'), i.get('profileState')) for i in items],
            }.get(name, lambda: len(items))()
            print(f'{name}: {res.status} {detail}')
    except urllib.error.HTTPError as err:
        errors = json.loads(err.read() or b'{}').get('errors', [])
        print(f'{name}: {err.code} ' + '; '.join(f"{e.get('code')} {e.get('title')} {e.get('detail', '')}" for e in errors))
    except urllib.error.URLError as err:
        print(f'{name}: network error {err.reason}')
