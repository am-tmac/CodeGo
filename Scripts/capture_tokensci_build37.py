from pathlib import Path
import subprocess,plistlib,os,time,hashlib,json
r=Path(__file__).resolve().parents[1];app=r/'Build37PreviewDerived/Build/Products/Debug-iphonesimulator/CodexUsage.app';bundle=plistlib.loads((app/'Info.plist').read_bytes())['CFBundleIdentifier'];udid='33C008E0-72FF-4BDB-B5B4-FAB91E5EE067'
subprocess.run(['xcrun','simctl','terminate',udid,bundle],capture_output=True)
subprocess.run(['xcrun','simctl','install',udid,str(app)],check=True)
out=r/'Build37Screenshots';out.mkdir(exist_ok=True);manifest=[]
for theme in ['dark','light']:
 subprocess.run(['xcrun','simctl','ui',udid,'appearance',theme],check=True)
 for section in ['overview','activity','analytics','chart','rankings','composition','habits','expanded','range7cost']:
  subprocess.run(['xcrun','simctl','terminate',udid,bundle],capture_output=True)
  env=os.environ.copy();env['SIMCTL_CHILD_PREVIEW_SECTION']={'expanded':'rankings','range7cost':'chart'}.get(section,section);env['SIMCTL_CHILD_PREVIEW_RANGE']='7' if section=='range7cost' else '30';env['SIMCTL_CHILD_PREVIEW_COST']='1' if section=='range7cost' else '0';env['SIMCTL_CHILD_PREVIEW_EXPANDED']='1' if section=='expanded' else '0'
  subprocess.run(['xcrun','simctl','launch',udid,bundle],env=env,check=True,stdout=subprocess.DEVNULL);time.sleep(10)
  p=out/f'{theme}-{section}.png';subprocess.run(['xcrun','simctl','io',udid,'screenshot',str(p)],check=True,capture_output=True);manifest.append({'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'manifest.json').write_text(json.dumps(manifest,indent=2));print('Screenshots:',len(manifest),'unique:',len(set(x['sha256'] for x in manifest)))
