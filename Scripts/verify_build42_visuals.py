#!/usr/bin/env python3
"""Isolated fixture rendering: real SwiftUI cards, no keys/network, repeatable PNG + SHA manifest.
The copy keeps all bundle/signing IDs; the shipping sources never contain fixtures.
"""
from pathlib import Path
import subprocess, shutil, os, plistlib, time, json, hashlib
r = Path(__file__).resolve().parents[1]
out = r/'Build42Preview'
out.mkdir(exist_ok=True)
for name in ['App', 'Shared', 'Widget', 'Configuration', 'CodexUsage.xcodeproj']:
    shutil.copytree(r/name, out/name, dirs_exist_ok=True, ignore=shutil.ignore_patterns('Private.xcconfig', 'xcuserdata'))
p = out/'App/CodexUsageApp.swift'
s = p.read_text().replace('else { ContentView(model: model) }', 'else { Build42PreviewRoot() }')
assert 'else { Build42PreviewRoot() }' in s
s += r'''
struct Build42PreviewRoot: View {
    @Environment(\.colorScheme) var scheme
    let go = OpenCodeGoSnapshot(usage: try! OpenCodeGoUsage.parse(Data(#"{"usage":{"rolling":{"percent":25,"resetAt":"2030-06-18T10:00:00Z"},"weekly":{"percent":62,"resetAt":"2030-06-22T10:00:00Z"},"monthly":{"percent":17,"resetAt":"2030-07-01T10:00:00Z"}}}"#.utf8)), updatedAt: Date())
    let command = CommandCodeSnapshot(usage: try! CommandCodeUsage.parse(Data(#"{"credits":{"monthlyCredits":7.25,"purchasedCredits":2,"windowLimits":{"fiveHour":{"cap":"4","used":"1","resetAt":"1908000000"},"weekly":{"cap":20,"used":4,"resetAt":1908300000000}}}}"#.utf8), subscription: Data(#"{"data":{"planId":"individual-go","currentPeriodEnd":"2030-07-01T10:00:00Z"}}"#.utf8)), updatedAt: Date())
    var codex: UsageSnapshot {
        var usage = try! JSONDecoder().decode(UsageResponse.self, from: Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":20},"secondary_window":{"used_percent":40}}}"#.utf8))
        usage.resetCreditDetails = try! CodexResetCredits.parse(Data(#"{"available_count":2,"total_earned_count":5,"credits":[{"status":"available","expires_at":"2030-07-18T00:39:53.731630Z"},{"status":"available"}]}"#.utf8))
        return UsageSnapshot(usage: usage, updatedAt: Date(), accountLabel: "离线示例")
    }
    var page: String { ProcessInfo.processInfo.environment["PREVIEW_PAGE"] ?? "opencodego" }
    var palette: AppPalette { .resolve(scheme) }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("build 42 · 离线接口示例").font(.headline).foregroundStyle(palette.primary)
                if page == "codex" {
                    AccountCard(id: "fixture", title: "Codex", caption: "离线示例", snapshot: codex, expanded: .constant(true), canSelectWidget: false, palette: palette, onRefresh: {}, onSelectWidget: {}, onReauthorize: {}, onRemove: {}, slotValue: "示例")
                } else if page == "widgets" {
                    HStack(spacing: 16) {
                        APIUsageCompactView(title: "OpenCode Go", snapshot: ProviderCardData(go), command: false, failed: false, cacheOnly: false, palette: .resolve(.system, scheme: scheme), display: .remaining)
                        APIUsageCompactView(title: "Command Code", snapshot: ProviderCardData(command), command: true, failed: false, cacheOnly: false, palette: .resolve(.system, scheme: scheme), display: .remaining)
                    }.padding(12).frame(height: 170).background(palette.card, in: RoundedRectangle(cornerRadius: 20))
                    CompactUsageView(showResetCredits: true, snapshot: codex, palette: .resolve(.system, scheme: scheme)).padding(12).frame(width: 170, height: 170).background(palette.card, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    APIUsageAccountCard(brand: page == "opencodego" ? .opencodego : .commandcode, snapshot: page == "opencodego" ? ProviderCardData(go) : ProviderCardData(command), expanded: .constant(true), palette: palette, onRefresh: {}, onUpdateKey: {}, onRemove: {}, busy: false, accountContext: "离线示例")
                }
            }.padding(16)
        }.background(palette.background)
    }
}
'''
p.write_text(s)
log = r/'Logs/build42-visual-build.log'
with log.open('w') as f:
    subprocess.run(['xcodebuild','-project','CodexUsage.xcodeproj','-scheme','CodexUsage','-destination','platform=iOS Simulator,name=iPhone 17 Pro','-derivedDataPath',str(r/'Build42PreviewDerived'),'CODE_SIGN_IDENTITY=-','CODE_SIGNING_ALLOWED=YES','build'],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True)
app = r/'Build42PreviewDerived/Build/Products/Debug-iphonesimulator/CodexUsage.app'
bundle = plistlib.loads((app/'Info.plist').read_bytes())['CFBundleIdentifier']
devices = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
udid = next(d['udid'] for ds in devices['devices'].values() for d in ds if d['name']=='iPhone 17 Pro')
subprocess.run(['xcrun','simctl','boot',udid],capture_output=True)
subprocess.run(['xcrun','simctl','install',udid,str(app)],check=True)
shots = r/'Logs/build42-screenshots';shots.mkdir(exist_ok=True);manifest=[]
for theme in ['light','dark']:
    subprocess.run(['xcrun','simctl','ui',udid,'appearance',theme],check=True)
    for page in ['opencodego','commandcode','codex','widgets']:
        subprocess.run(['xcrun','simctl','terminate',udid,bundle],capture_output=True)
        env=dict(os.environ,SIMCTL_CHILD_PREVIEW_PAGE=page)
        subprocess.run(['xcrun','simctl','launch',udid,bundle],env=env,check=True,stdout=subprocess.DEVNULL)
        time.sleep(2)
        path=shots/f'{theme}-{page}.png'
        subprocess.run(['xcrun','simctl','io',udid,'screenshot',str(path)],check=True,capture_output=True)
        manifest.append({'path':str(path.relative_to(r)), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
assert len(set(item['sha256'] for item in manifest)) == 8
(shots/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Restore the actual Debug build after preview capture; fixture app never remains installed.
subprocess.run(['xcrun','simctl','terminate',udid,bundle],capture_output=True)
subprocess.run(['xcrun','simctl','install',udid,str(r/'Build42Sim/Build/Products/Debug-iphonesimulator/CodexUsage.app')],check=True)
print('8 unique simulator screenshots; manifest:',shots/'manifest.json')
