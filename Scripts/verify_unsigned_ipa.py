"""Verify a device IPA on macOS before publishing it for external signing."""
import hashlib
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def output(*args):
    return subprocess.check_output(args, text=True)


def verify(ipa, original):
    with tempfile.TemporaryDirectory(prefix='cnsnn-ipa-check-') as directory:
        with zipfile.ZipFile(ipa) as archive:
            require(archive.testzip() is None, 'Archive IPA corrompue.')
            names = archive.namelist()
            require(all(n.startswith('Payload/') and '..' not in Path(n).parts
                        for n in names), 'Structure IPA inattendue.')
        # ditto restores executable modes and bundle metadata from its ZIP.
        subprocess.run(['ditto', '-x', '-k', str(ipa), directory], check=True)
        app = Path(directory) / 'Payload/CNSNN.app'
        require(app.is_dir(), 'Payload/CNSNN.app absent.')
        for source in original.rglob('*'):
            if source.is_file():
                target = app / source.relative_to(original)
                require(target.is_file(), f'Ressource absente : {target.name}')
                require(hashlib.sha256(source.read_bytes()).digest() ==
                        hashlib.sha256(target.read_bytes()).digest(),
                        f'Ressource modifiée : {target.name}')
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'],
                'Le bundle doit cibler iPhoneOS, pas le simulateur.')
        executable = app / info['CFBundleExecutable']
        require(executable.is_file() and executable.stat().st_mode & 0o111,
                'Exécutable absent ou permissions incorrectes.')
        require('arm64' in output('xcrun', 'lipo', '-archs', str(executable)),
                'Architecture ARM64 absente.')
        for name in ['Assets.car', 'GoogleService-Info.plist', 'PrivacyInfo.xcprivacy']:
            require((app / name).is_file(), f'Ressource requise absente : {name}')
        firebase = plistlib.loads((app / 'GoogleService-Info.plist').read_bytes())
        require(firebase.get('BUNDLE_ID') == info['CFBundleIdentifier'],
                'Bundle ID Firebase incompatible.')
        require(not (app / 'embedded.mobileprovision').exists(),
                'Un profil de signature inattendu est présent.')
        binaries = [executable]
        frameworks = app / 'Frameworks'
        if frameworks.exists():
            binaries += [p for p in frameworks.rglob('*') if p.is_file() and
                         ('Mach-O' in output('file', '-b', str(p)))]
        for binary in binaries:
            platform = output('xcrun', 'vtool', '-show-build', str(binary))
            require(re.search(r'platform\s+IOS\b', platform) is not None,
                    f'Binaire non iOS physique : {binary.name}')
            for line in output('xcrun', 'otool', '-L', str(binary)).splitlines()[1:]:
                dependency = line.strip().split(' (', 1)[0]
                if dependency.startswith(('/System/Library/', '/usr/lib/')):
                    continue  # Supplied by iOS; do not copy system frameworks.
                if dependency.startswith('@rpath/'):
                    relative = dependency[len('@rpath/'):]
                    target = frameworks / relative
                    if dependency == '@rpath/' + binary.parent.name + '/' + binary.name:
                        continue  # A dynamic framework's own install name.
                    require(target.is_file(), f'Dépendance non embarquée : {dependency}')
                elif dependency.startswith('@loader_path/'):
                    require((binary.parent / dependency[len('@loader_path/'):]).is_file(),
                            f'Dépendance absente : {dependency}')
                elif dependency.startswith('@executable_path/'):
                    require((app / dependency[len('@executable_path/'):]).is_file(),
                            f'Dépendance absente : {dependency}')
                else:
                    raise SystemExit(f'Dépendance externe inattendue : {dependency}')
        print('PASS : IPA iPhone ARM64, bundle complet identique, ressources Firebase et dépendances vérifiées.')
        print('Firebase et CNSNNCore peuvent être liés statiquement dans le binaire ; aucun framework séparé n’est alors nécessaire.')
        print('Cet IPA doit encore être signé par Sideloadly. Le lancement réel sur iPhone reste à vérifier.')


if __name__ == '__main__':
    require(len(sys.argv) == 3, 'Usage: verify_unsigned_ipa.py IPA APP_ORIGINAL')
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
