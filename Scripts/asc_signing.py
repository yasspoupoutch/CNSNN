#!/usr/bin/env python3
"""Prepares what the App Store build needs to be signed, through the App Store Connect API.

Xcode's automatic (cloud) signing refuses the API key on CI, so the TestFlight workflow signs
manually, with the Apple Distribution certificate of KEY_PEM (the CI's own private key, kept
encrypted in Scripts/ios-signing). Nothing is ever revoked or deleted:
  - App Groups is enabled on the app and widget identifiers if needed, and Associated Domains
    (challenge links as universal links) on the app identifier, the first BUNDLE_ID;
  - the certificate matching KEY_PEM is reused, or created once from a CSR;
  - an App Store profile per identifier is reused while active with the App Group, or created.
Writes into OUT_DIR: dist-cert.der and <bundle id>.mobileprovision, and prints one line per
profile: PROFILE <bundle id> <uuid> groups=<App Groups it allows> domains=<yes|no> name=<name>.

Usage: asc_signing.py KEY_ID ISSUER_ID API_KEY_PATH KEY_PEM OUT_DIR BUNDLE_ID [BUNDLE_ID...]
"""
import base64, json, plistlib, re, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.x509.oid import NameOID

key_id, issuer, key_path, dist_key_path, out_dir, *bundles = sys.argv[1:]
out = Path(out_dir)
out.mkdir(parents=True, exist_ok=True)
CERT_NAME = 'CNSNN CI'
PROFILE_PREFIX = 'CNSNN CI App Store '


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def token():
    key = serialization.load_pem_private_key(open(key_path, 'rb').read(), password=None)
    head = b64(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode())
    now = int(time.time())
    body = b64(json.dumps({'iss': issuer, 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'}).encode())
    r, s = decode_dss_signature(key.sign(f'{head}.{body}'.encode(), ec.ECDSA(hashes.SHA256())))
    return f'{head}.{body}.' + b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


AUTH = token()


def api(method, path, body=None, ok=(200, 201, 204)):
    url = 'https://api.appstoreconnect.apple.com' + urllib.parse.quote(path, safe='/?=&[],')
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={'Authorization': f'Bearer {AUTH}', 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read()
            return res.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as err:
        payload = json.loads(err.read() or b'{}')
        if err.code in ok:
            return err.code, payload
        detail = '; '.join(f"{e.get('code')} {e.get('title')} {e.get('detail', '')}" for e in payload.get('errors', []))
        raise SystemExit(f'::error::{method} {path.split("?")[0]} -> {err.code} {detail}')


# Identifiers and App Groups capability.
ids = {}
for bundle in bundles:
    _, res = api('GET', f'/v1/bundleIds?filter[identifier]={bundle}&limit=5')
    match = [d for d in res['data'] if d['attributes']['identifier'] == bundle]
    if match:
        ids[bundle] = match[0]['id']
    else:
        _, res = api('POST', '/v1/bundleIds', {'data': {'type': 'bundleIds', 'attributes': {
            'identifier': bundle, 'name': 'CNSNN ' + bundle.split('.')[-1], 'platform': 'IOS'}}})
        ids[bundle] = res['data']['id']
        print(f'Identifiant créé : {bundle}')
    _, caps = api('GET', f'/v1/bundleIds/{ids[bundle]}/bundleIdCapabilities')
    if not any(c['attributes'].get('capabilityType') == 'APP_GROUPS' for c in caps['data']):
        api('POST', '/v1/bundleIdCapabilities', {'data': {'type': 'bundleIdCapabilities',
            'attributes': {'capabilityType': 'APP_GROUPS'},
            'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': ids[bundle]}}}}}, ok=(409,))
        print(f'App Groups activé sur {bundle}')
    if bundle == bundles[0] and not any(c['attributes'].get('capabilityType') == 'ASSOCIATED_DOMAINS' for c in caps['data']):
        api('POST', '/v1/bundleIdCapabilities', {'data': {'type': 'bundleIdCapabilities',
            'attributes': {'capabilityType': 'ASSOCIATED_DOMAINS'},
            'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': ids[bundle]}}}}}, ok=(409,))
        print(f'Associated Domains activé sur {bundle}')

# Distribution certificate: the one whose public key is ours, else a new one.
dist_key = serialization.load_pem_private_key(open(dist_key_path, 'rb').read(), password=None)
ours = dist_key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
_, res = api('GET', '/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=50')
cert_id = cert_der = None
for cert in res['data']:
    der = base64.b64decode(cert['attributes']['certificateContent'])
    public = x509.load_der_x509_certificate(der).public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    if public == ours:
        cert_id, cert_der = cert['id'], der
if cert_id:
    print('Certificat Apple Distribution existant réutilisé')
else:
    csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, CERT_NAME),
        x509.NameAttribute(NameOID.EMAIL_ADDRESS, 'jeucnsnn@gmail.com'),
    ])).sign(dist_key, hashes.SHA256())
    _, res = api('POST', '/v1/certificates', {'data': {'type': 'certificates', 'attributes': {
        'certificateType': 'DISTRIBUTION', 'csrContent': csr.public_bytes(serialization.Encoding.PEM).decode()}}})
    cert_id, cert_der = res['data']['id'], base64.b64decode(res['data']['attributes']['certificateContent'])
    print('Certificat Apple Distribution créé')
(out / 'dist-cert.der').write_bytes(cert_der)

# App Store profiles tied to that certificate (its id is in the name). A profile is reused only
# while active and allowing REQUIRED_GROUP (and, for the app, Associated Domains); otherwise a new
# one is made (Apple keeps the old one).
REQUIRED_GROUP = 'group.com.poupoutch.cnsnn'


def parse(content):
    plist = plistlib.loads(re.search(rb'<\?xml.*</plist>', content, re.S).group(0))
    entitlements = plist.get('Entitlements', {})
    return plist, entitlements.get('com.apple.security.application-groups', []), 'com.apple.developer.associated-domains' in entitlements


_, res = api('GET', '/v1/profiles?filter[profileType]=IOS_APP_STORE&limit=200')
active = [p for p in res['data'] if p['attributes'].get('profileState') == 'ACTIVE']
for bundle in bundles:
    name = f'{PROFILE_PREFIX}{bundle} {cert_id}'
    content = None
    for profile in active:
        if profile['attributes']['name'].startswith(name):
            candidate = base64.b64decode(profile['attributes']['profileContent'])
            _, groups, domains = parse(candidate)
            if REQUIRED_GROUP in groups and (domains or bundle != bundles[0]):
                content = candidate
    if content is None:
        _, res = api('POST', '/v1/profiles', {'data': {'type': 'profiles',
            'attributes': {'name': f'{name} {time.strftime("%Y%m%d%H%M%S")}', 'profileType': 'IOS_APP_STORE'},
            'relationships': {
                'bundleId': {'data': {'type': 'bundleIds', 'id': ids[bundle]}},
                'certificates': {'data': [{'type': 'certificates', 'id': cert_id}]}}}})
        content = base64.b64decode(res['data']['attributes']['profileContent'])
    (out / f'{bundle}.mobileprovision').write_bytes(content)
    plist, groups, domains = parse(content)
    print(f'PROFILE {bundle} {plist["UUID"]} groups={",".join(groups) or "-"} domains={"yes" if domains else "no"} name={name}')
