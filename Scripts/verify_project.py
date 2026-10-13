#!/usr/bin/env python3
"""Structural checks only. This does not compile Swift or evaluate Firebase rules."""
from pathlib import Path
import json,plistlib,re,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
count=0
for path in list(root.rglob('*.json')):
 if any(part in ('node_modules','.git','work') for part in path.parts):continue
 json.loads(path.read_text());count+=1
for path in [root/'App/Resources/Info.plist',root/'App/Resources/PrivacyInfo.xcprivacy']:
 plistlib.loads(path.read_bytes());count+=1
ET.parse(root/'CNSNN.xcodeproj/xcshareddata/xcschemes/CNSNN.xcscheme');count+=1
# Parse the OpenStep syntax, including empty arrays and string escaping.
text=(root/'CNSNN.xcodeproj/project.pbxproj').read_text()
text=re.sub(r'^//[^\n]*','',text,flags=re.MULTILINE)
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',text)
pos=0
def take():
 global pos
 t=tokens[pos];pos+=1;return t
def expect(t):
 assert take()==t,f'Expected {t} near token {pos}'
def value():
 t=take()
 if t=='{':
  d={}
  while tokens[pos]!='}':
   key=take();expect('=');d[key.strip('"')]=value();expect(';')
  expect('}');return d
 if t=='(':
  a=[]
  while tokens[pos]!=')':
   a.append(value())
   if tokens[pos]!=')':expect(',')
  expect(')');return a
 return json.loads(t) if t.startswith('"') else t
project=value();assert pos==len(tokens)
objects=project['objects'];assert project['rootObject'] in objects
for key,data in objects.items():
 for f in ['fileRef','productRef','target','targetProxy','containerPortal','mainGroup','productRefGroup','buildConfigurationList','productReference','package']:
  if f in data:assert data[f] in objects,(key,f,data[f])
 for f in ['children','files','buildConfigurations','buildPhases','dependencies','targets','packageReferences','packageProductDependencies']:
  for ref in data.get(f,[]):assert ref in objects,(key,f,ref)
 if data.get('isa')=='PBXFileReference' and data.get('sourceTree')=='SOURCE_ROOT':assert (root/data['path']).exists(),data['path']
# Lightweight lexical guard for accidental raw newlines and unbalanced delimiters.
for path in list((root/'App').rglob('*.swift'))+list((root/'Core').rglob('*.swift'))+list((root/'Tests').rglob('*.swift')):
 s=path.read_text();stack=[];i=0
 while i<len(s):
  if s.startswith('//',i):
   end=s.find('\n',i);i=len(s) if end<0 else end;continue
  if s[i]=='"':
   i+=1
   while i<len(s) and s[i]!='"':
    assert s[i]!='\n',f'Raw newline in string: {path}'
    if s[i]=='\\':i+=1
    i+=1
   assert i<len(s),f'Unterminated string: {path}'
  elif s[i] in '({[':stack.append(s[i])
  elif s[i] in ')}]':assert stack and stack.pop()=={')':'(',']':'[','}':'{'}[s[i]],f'Unbalanced source: {path}'
  i+=1
 assert not stack,f'Unbalanced source: {path}'
 count+=1
rules=(root/'Firebase/firestore.rules').read_text()
assert 'allow read, write: if true' not in rules
assert "request.auth.token.get('admin', false) == true" in rules
print(f'PASS: {count} source/config files checked; {len(objects)} Xcode objects resolve. Compilation still requires Xcode.')
