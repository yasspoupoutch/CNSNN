#!/usr/bin/env python3
"""Attach a supplied Firebase iOS configuration. No network or Firebase writes."""
from pathlib import Path
import argparse,hashlib,plistlib,shutil
parser=argparse.ArgumentParser();parser.add_argument('plist',type=Path);args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
data=plistlib.loads(args.plist.read_bytes())
for key in ['PROJECT_ID','GOOGLE_APP_ID','API_KEY','BUNDLE_ID']:assert data.get(key),f'Missing {key}'
assert data['BUNDLE_ID']=='com.poupoutch.cnsnn','Bundle ID differs. Inspect the existing iOS registration before changing the app identifier.'
assert data['GOOGLE_APP_ID'].find(':ios:')>=0,'This is not an iOS Firebase configuration.'
dest=root/'App/Resources/GoogleService-Info.plist'
if dest.exists():assert dest.read_bytes()==args.plist.read_bytes(),'Existing Firebase configuration differs. Refusing to overwrite.'
project=root/'CNSNN.xcodeproj/project.pbxproj';text=project.read_text()
if 'App/Resources/GoogleService-Info.plist' not in text:
 def ident(k):return hashlib.sha1(k.encode()).hexdigest()[:24].upper()
 ref,build=ident('firebase-plist-ref'),ident('firebase-plist-build')
 # The project generator uses deterministic identifiers.
 group=ident('main');phase=ident('resources-CNSNN')
 text=text.replace(f'{group} = {{isa = PBXGroup; children = (',f'{group} = {{isa = PBXGroup; children = ({ref},')
 text=text.replace(f'{phase} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (',f'{phase} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({build},')
 objects=f'{ref} = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "App/Resources/GoogleService-Info.plist"; sourceTree = SOURCE_ROOT;}};\n{build} = {{isa = PBXBuildFile; fileRef = {ref};}};\n'
 text=text.replace('objects = {\n','objects = {\n'+objects)
 project.write_text(text)
if args.plist.resolve() != dest.resolve(): shutil.copyfile(args.plist,dest)
print('Firebase iOS configuration attached locally. No rules, services, billing or remote data were modified.')
