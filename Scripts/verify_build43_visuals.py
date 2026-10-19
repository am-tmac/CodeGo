#!/usr/bin/env python3
"""Isolated fixture rendering: real SwiftUI cards, no keys/network, repeatable PNG + SHA manifest.
The copy keeps all bundle/signing IDs; the shipping sources never contain fixtures.
"""
from pathlib import Path
import subprocess, shutil, os, plistlib, time, json, hashlib
r = Path(__file__).resolve().parents[1]
out = r/'Build43Preview'
out.mkdir(exist_ok=True)
for name in ['App', 'Shared', 'Widget', 'Configuration', 'CodeGo.xcodeproj']:
    shutil.copytree(r/name, out/name, dirs_exist_ok=True, ignore=shutil.ignore_patterns('Private.xcconfig', 'xcuserdata'))
p = out/'App/CodeGoApp.swift'
s = p.read_text().replace('else { ContentView(model: model) }', 'else { Build43PreviewRoot() }')
assert 'else { Build43PreviewRoot() }' in s
s += r'''
struct Build43PreviewRoot: View {
    @Environment(\.colorScheme) var scheme
    var codex: UsageSnapshot {
        var usage = try! JSONDecoder().decode(UsageResponse.self, from: Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":20},"secondary_window":{"used_percent":40}}}"#.utf8))
        usage.resetCreditDetails = try! CodexResetCredits.parse(Data(#"{"credits":[{"status":"available","expires_at":"2030-07-18T00:39:53Z"},{"status":"available"},{"status":"available","expires_at":"2020-01-01T00:00:00Z"},{"status":"used"}]}"#.utf8))
        return UsageSnapshot(usage: usage, updatedAt: Date())
    }
    var medium: Bool { ProcessInfo.processInfo.environment["PREVIEW_PAGE"] == "medium" }
    var palette: AppPalette { .resolve(scheme) }
    var body: some View {
        VStack(spacing: 24) {
            Text("CodeGo · build 43").font(.headline)
            Text(medium ? "中号组件 · 两个 Codex 槽位" : "小号组件").font(.subheadline)
            HStack(spacing: 16) {
                CompactUsageView(snapshot: codex, palette: .resolve(.system, scheme: scheme))
                if medium {
                    CompactUsageView(snapshot: codex, palette: .resolve(.system, scheme: scheme))
                }
            }.padding(12).frame(width: medium ? 364 : 170, height: 170)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.background)
    }
}
'''
p.write_text(s)
udid = (r/'Logs/build43-simulator-id.txt').read_text().strip()
log = r/'Logs/build43-visual-build.log'
with log.open('w') as f:
    subprocess.run(['xcodebuild','-project','CodeGo.xcodeproj','-scheme','CodeGo','-destination','platform=iOS Simulator,id='+udid,'-derivedDataPath',str(r/'Build43PreviewDerived'),'CODE_SIGN_IDENTITY=-','CODE_SIGNING_ALLOWED=YES','build'],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True)
app = r/'Build43PreviewDerived/Build/Products/Debug-iphonesimulator/CodeGo.app'
bundle = plistlib.loads((app/'Info.plist').read_bytes())['CFBundleIdentifier']
subprocess.run(['xcrun','simctl','boot',udid],capture_output=True)
subprocess.run(['xcrun','simctl','install',udid,str(app)],check=True)
shots = r/'Logs/build43-screenshots';shots.mkdir(exist_ok=True);manifest=[]
for theme in ['light','dark']:
    subprocess.run(['xcrun','simctl','ui',udid,'appearance',theme],check=True)
    for page in ['small','medium']:
        subprocess.run(['xcrun','simctl','terminate',udid,bundle],capture_output=True)
        env=dict(os.environ,SIMCTL_CHILD_PREVIEW_PAGE=page)
        subprocess.run(['xcrun','simctl','launch',udid,bundle],env=env,check=True,stdout=subprocess.DEVNULL)
        time.sleep(2)
        path=shots/f'{theme}-{page}.png'
        subprocess.run(['xcrun','simctl','io',udid,'screenshot',str(path)],check=True,capture_output=True)
        manifest.append({'path':str(path.relative_to(r)), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
assert len(set(item['sha256'] for item in manifest)) == 4
(shots/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Restore the actual Debug build after preview capture; fixture app never remains installed.
subprocess.run(['xcrun','simctl','terminate',udid,bundle],capture_output=True)
subprocess.run(['xcrun','simctl','install',udid,str(r/'Build43Sim/Build/Products/Debug-iphonesimulator/CodeGo.app')],check=True)
print('4 unique simulator screenshots; manifest:',shots/'manifest.json')
