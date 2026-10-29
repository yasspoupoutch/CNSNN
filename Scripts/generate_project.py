from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
def ident(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def q(s): return json.dumps(str(s))
objects={}
def obj(key,body):
 i=ident(key);objects[i]=body;return i
def array(values): return '('+','.join(values)+',)' if values else '()'
def config(key,settings): return obj(key,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(f'{k} = {v};' for k,v in settings.items())+'}; name = '+q(key.rsplit('-',1)[-1])+';')
def configs(key,settings):
 ids=[config(key+'-'+name,{**settings,**({'SWIFT_OPTIMIZATION_LEVEL':q('-Onone'),'DEBUG_INFORMATION_FORMAT':'dwarf','SWIFT_ACTIVE_COMPILATION_CONDITIONS':q('DEBUG $(inherited)'), 'ENABLE_TESTABILITY':'YES'} if name=='Debug' else {'SWIFT_OPTIMIZATION_LEVEL':q('-O'),'DEBUG_INFORMATION_FORMAT':q('dwarf-with-dsym')})}) for name in ['Debug','Release']]
 return obj(key+'-configs','isa = XCConfigurationList; buildConfigurations = '+array(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
main=ident('main');products=[];groups=[];targets=[]
common={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','SWIFT_STRICT_CONCURRENCY':'targeted','TARGETED_DEVICE_FAMILY':q('1'),'CODE_SIGN_STYLE':'Automatic'}
projectcfg=configs('Project',common)
# Firebase SDK, linked only to app. Resolves in Xcode on Mac.
remote=obj('firebase','isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/firebase/firebase-ios-sdk.git"; requirement = {kind = upToNextMajorVersion; minimumVersion = 12.0.0;};')
packages=[]
for name in ['FirebaseCore','FirebaseAuth','FirebaseFirestore']:
 packages.append(obj(name,'isa = XCSwiftPackageProductDependency; package = '+remote+'; productName = '+name+';'))
def target(name,paths,ptype,extension,deps=None,settings=None,packageproducts=None,resources=None):
 tid=ident('target-'+name);sources=[];refs=[]
 for path in paths:
  rid=obj('ref-'+str(path),'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(path)+'; sourceTree = SOURCE_ROOT;')
  refs.append(rid);sources.append(obj('build-'+name+'-'+str(path),'isa = PBXBuildFile; fileRef = '+rid+';'))
 group=obj('group-'+name,'isa = PBXGroup; name = '+q(name)+'; children = '+array(refs)+'; sourceTree = "<group>";');groups.append(group)
 sp=obj('sources-'+name,'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+array(sources)+'; runOnlyForDeploymentPostprocessing = 0;')
 fb=[]
 for prod in packageproducts or []: fb.append(obj('link-'+name+'-'+prod,'isa = PBXBuildFile; productRef = '+prod+';'))
 for dep in [d for d in (deps or []) if d != 'CNSNN']: fb.append(obj('link-'+name+'-'+dep,'isa = PBXBuildFile; fileRef = '+ident('product-'+dep)+';'))
 fp=obj('frameworks-'+name,'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = '+array(fb)+'; runOnlyForDeploymentPostprocessing = 0;')
 rbuild=[]
 for path,ftype in resources or []:
  rid=obj('ref-'+path,'isa = PBXFileReference; lastKnownFileType = '+ftype+'; path = '+q(path)+'; sourceTree = SOURCE_ROOT;')
  groups.append(rid);rbuild.append(obj('resource-'+path,'isa = PBXBuildFile; fileRef = '+rid+';'))
 rp=obj('resources-'+name,'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+array(rbuild)+'; runOnlyForDeploymentPostprocessing = 0;')
 product=obj('product-'+name,'isa = PBXFileReference; explicitFileType = '+('wrapper.application' if extension=='app' else 'wrapper.app-extension' if extension=='appex' else 'wrapper.cfbundle' if extension=='xctest' else 'archive.ar')+'; includeInIndex = 0; path = '+q(('lib' if extension=='a' else '')+name+'.'+extension)+'; sourceTree = BUILT_PRODUCTS_DIR;');products.append(product)
 dependency=[]
 for dep in deps or []:
  proxy=obj('proxy-'+name+'-'+dep,'isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+ident('target-'+dep)+'; remoteInfo = '+q(dep)+';')
  dependency.append(obj('dep-'+name+'-'+dep,'isa = PBXTargetDependency; target = '+ident('target-'+dep)+'; targetProxy = '+proxy+';'))
 cfg=configs(name,{**common,'PRODUCT_NAME':q('$(TARGET_NAME)'),**(settings or {})})
 obj('target-'+name,'isa = PBXNativeTarget; buildConfigurationList = '+cfg+'; buildPhases = '+array([sp,fp,rp])+'; buildRules = (); dependencies = '+array(dependency)+'; name = '+q(name)+'; productName = '+q(name)+'; productReference = '+product+'; productType = '+q(ptype)+'; packageProductDependencies = '+array(packageproducts or [])+';')
 targets.append(tid);return tid
core=target('CNSNNCore',[str(p.relative_to(root)) for p in sorted((root/'Core').glob('*.swift'))],'com.apple.product-type.library.static','a',settings={'DEFINES_MODULE':'YES','SKIP_INSTALL':'YES'})
# Home screen widget (WidgetKit extension), embedded in the app below.
widget=target('CNSNNWidget',[str(p.relative_to(root)) for p in sorted((root/'Widget').glob('*.swift'))],'com.apple.product-type.app-extension','appex',deps=['CNSNNCore'],settings={'PRODUCT_BUNDLE_IDENTIFIER':q('com.poupoutch.cnsnn.widget'),'INFOPLIST_FILE':q('Widget/Info.plist'),'CODE_SIGN_ENTITLEMENTS':q('Widget/CNSNNWidget.entitlements'),'MARKETING_VERSION':q('1.3.1'),'CURRENT_PROJECT_VERSION':q('1'),'SKIP_INSTALL':'YES','APPLICATION_EXTENSION_API_ONLY':'YES','LD_RUNPATH_SEARCH_PATHS':q('$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks')})
app=target('CNSNN',[str(p.relative_to(root)) for p in sorted((root/'App').rglob('*.swift'))],'com.apple.product-type.application','app',deps=['CNSNNCore'],settings={'PRODUCT_BUNDLE_IDENTIFIER':q('com.poupoutch.cnsnn'),'INFOPLIST_FILE':q('App/Resources/Info.plist'),'ASSETCATALOG_COMPILER_APPICON_NAME':q('AppIcon'),'CODE_SIGN_ENTITLEMENTS':q('App/CNSNN.entitlements'),'MARKETING_VERSION':q('1.3.1'),'CURRENT_PROJECT_VERSION':q('1'),'ENABLE_PREVIEWS':'YES'},packageproducts=packages,resources=[('App/Resources/Assets.xcassets','folder.assetcatalog'),('App/Resources/PrivacyInfo.xcprivacy','text.xml'),('App/Resources/Fonts/InstrumentSerif-Regular.ttf','file'),('App/Resources/Fonts/InstrumentSerif-Italic.ttf','file'),('App/Resources/Fonts/Fraunces-Black.ttf','file')])
# Embed the widget: dependency plus an "Embed App Extensions" copy phase (PlugIns folder).
embedfile=obj('embed-widget-file','isa = PBXBuildFile; fileRef = '+ident('product-CNSNNWidget')+'; settings = {ATTRIBUTES = (RemoveHeadersOnCopy,);};')
embed=obj('embed-widget','isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ('+embedfile+',); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
wproxy=obj('proxy-app-widget','isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+widget+'; remoteInfo = CNSNNWidget;')
wdep=obj('dep-app-widget','isa = PBXTargetDependency; target = '+widget+'; targetProxy = '+wproxy+';')
objects[app]=objects[app].replace('buildPhases = (','buildPhases = ('+embed+',',1).replace('dependencies = (','dependencies = ('+wdep+',',1)
test=target('CNSNNCoreTests',[str(p.relative_to(root)) for p in sorted((root/'Tests/Core').glob('*.swift'))],'com.apple.product-type.bundle.unit-test','xctest',deps=['CNSNNCore'],settings={'PRODUCT_BUNDLE_IDENTIFIER':q('app.cnsnn.coretests'),'GENERATE_INFOPLIST_FILE':'YES'})
apptest=target('CNSNNAppTests',[str(p.relative_to(root)) for p in sorted((root/'Tests/App').glob('*.swift'))],'com.apple.product-type.bundle.unit-test','xctest',deps=['CNSNN','CNSNNCore'],settings={'PRODUCT_BUNDLE_IDENTIFIER':q('app.cnsnn.apptests'),'GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':q('$(BUILT_PRODUCTS_DIR)/CNSNN.app/CNSNN'),'BUNDLE_LOADER':q('$(TEST_HOST)')})
integration=target('CNSNNIntegrationTests',[str(p.relative_to(root)) for p in sorted((root/'Tests/Integration').glob('*.swift'))],'com.apple.product-type.bundle.unit-test','xctest',deps=['CNSNN','CNSNNCore'],settings={'PRODUCT_BUNDLE_IDENTIFIER':q('app.cnsnn.integrationtests'),'GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':q('$(BUILT_PRODUCTS_DIR)/CNSNN.app/CNSNN'),'BUNDLE_LOADER':q('$(TEST_HOST)')})
uitest=target('CNSNNUITests',['Tests/UI/CNSNNUITests.swift','Tests/UI/CNSNNScreenshotTests.swift'],'com.apple.product-type.bundle.ui-testing','xctest',settings={'PRODUCT_BUNDLE_IDENTIFIER':q('app.cnsnn.uitests'),'GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':q('CNSNN')})
proxy=obj('proxy-ui-app','isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+app+'; remoteInfo = CNSNN;')
dep=obj('dep-ui-app','isa = PBXTargetDependency; target = '+app+'; targetProxy = '+proxy+';')
objects[uitest]=objects[uitest].replace('dependencies = ();','dependencies = ('+dep+',);')
pg=obj('products','isa = PBXGroup; children = '+array(products)+'; name = Products; sourceTree = "<group>";')
obj('main','isa = PBXGroup; children = '+array(groups+[pg])+'; sourceTree = "<group>";')
obj('project','isa = PBXProject; attributes = {LastUpgradeCheck = 2600;}; buildConfigurationList = '+projectcfg+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr,en,Base,); mainGroup = '+main+'; productRefGroup = '+pg+'; projectDirPath = ""; projectRoot = ""; targets = '+array(targets)+'; packageReferences = '+array([remote])+';')
p=root/'CNSNN.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(f'{i} = {{{b}}};' for i,b in objects.items())+'\n}; rootObject = '+ident('project')+'; }\n')
scheme=p/'xcshareddata/xcschemes/CNSNN.xcscheme';scheme.parent.mkdir(parents=True,exist_ok=True)
def ref(i,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{i}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:CNSNN.xcodeproj"/>'
scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app,'CNSNN.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test,'CNSNNCoreTests.xctest')}</TestableReference><TestableReference skipped="NO">{ref(apptest,'CNSNNAppTests.xctest')}</TestableReference><TestableReference skipped="NO">{ref(integration,'CNSNNIntegrationTests.xctest')}</TestableReference><TestableReference skipped="NO">{ref(uitest,'CNSNNUITests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'CNSNN.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'CNSNN.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
# Retain an attached local Firebase configuration when regenerating the project.
if (root/'App/Resources/GoogleService-Info.plist').exists():
    import subprocess,sys
    subprocess.run([sys.executable,str(root/'Scripts/connect_firebase.py'),str(root/'App/Resources/GoogleService-Info.plist')],check=True)
print(f'Generated project: {len(objects)} objects, {len(targets)} targets')
