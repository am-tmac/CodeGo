#!/usr/bin/env python3
"""Package CodeGo 4.7 (44), preserving build 42 bundle identifiers."""
from pathlib import Path
import hashlib
import plistlib
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / 'Build44Direct/Build/Products/Release-iphoneos/CodeGo.app'
appex = app / 'PlugIns/CodeGoWidget.appex'
# Private identifiers come from the untracked Configuration/Private.xcconfig, never from this file.
private = {}
for line in (root / 'Configuration/Private.xcconfig').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('//'):
        key, value = line.split('=', 1)
        private[key.strip()] = value.strip()
base_id = private['CODEX_APP_BUNDLE_IDENTIFIER']
ids = (base_id, base_id + '.Widget')
# Compare the actual build 42 shipping artifact, not just a matching current config.
with zipfile.ZipFile(root / 'Dist/CodexUsage-4.5-build42-unsigned.ipa') as previous:
    old_ids = tuple(plistlib.loads(previous.read(path))['CFBundleIdentifier'] for path in
        ['Payload/CodexUsage.app/Info.plist', 'Payload/CodexUsage.app/PlugIns/CodexUsageWidget.appex/Info.plist'])
assert ids == old_ids, 'Bundle IDs changed since build 42' 
for bundle, bundle_id in zip((app, appex), ids):
    assert bundle.is_dir(), bundle
    assert not (bundle / '_CodeSignature').exists(), bundle
    assert not (bundle / 'embedded.mobileprovision').exists(), bundle
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    assert (info['CFBundleIdentifier'], info['CFBundleVersion'], info['CFBundleShortVersionString'], info['MinimumOSVersion']) == (bundle_id, '44', '4.7', '17.0'), 'Unexpected build identity/version'
    assert info['CFBundleDisplayName'] == 'CodeGo'
    assert '$(' not in str(info)
    executable = bundle / info['CFBundleExecutable']
    assert 'arm64' in subprocess.check_output(['lipo', '-archs', str(executable)], text=True)
    assert subprocess.run(['codesign', '-v', str(bundle)], capture_output=True).returncode != 0
for bundle in (app, appex):
    info = str(plistlib.loads((bundle / 'Info.plist').read_bytes()))
    assert private['APP_GROUP_IDENTIFIER'] in info, bundle
    assert private['KEYCHAIN_GROUP_IDENTIFIER'] in info, bundle

app_binary = (app / 'CodeGo').read_bytes()
widget = (appex / 'CodeGoWidget').read_bytes()

# --- widget refresh control: present in both states, never one disguised as the other ---
assert 'arrow.up.forward.app'.encode() in widget          # open-App control, unauthorised state
assert '组件无刷新授权'.encode() in widget
assert '打开 App 刷新'.encode() in widget                  # the open-App control's own label
# --- the consent switch can no longer dead-end, and the override is disclosed ---
assert '可以直接开启：本机有可用的实测 keychain 组'.encode() in app_binary
assert '未完成跨进程验证'.encode() in app_binary
assert '刷新失败 · 保留缓存'.encode() in app_binary
# --- Claude sign-in is a real OAuth login, not a pasted web session ---
assert 'Anthropic 不授权第三方 App 提供 Claude.ai 登录'.encode() in app_binary
assert '用 Claude 账号登录'.encode() in app_binary
assert 'http://localhost:54545/callback'.encode() in app_binary
assert '9d1c250a-e61b-44d9-88ed-5944d1962f5e'.encode() in app_binary
assert 'https://api.anthropic.com/api/oauth/usage'.encode() in app_binary
# The new credential namespace is live, and the pre-OAuth one exists only as the delete target.
assert 'CodexUsage.Claude.oauth.v1'.encode() in app_binary
assert 'CodexUsage.Claude.session.v1'.encode() in app_binary
# --- build 27 review fixes: new user-visible strings (>= 16 bytes) prove this revision ---
assert '授权码格式无法识别，或不属于本次登录'.encode() in app_binary
assert '登录已失效，请重新点「打开授权页面」'.encode() in app_binary
assert '授权码格式无法识别，请粘贴页面上显示的整段内容'.encode() not in app_binary   # old message gone
# --- build 28: usage display setting, token cache, shared meter colours ---
assert '百分比和用量条显示剩余还是已用'.encode() in app_binary
assert 'usage-display.txt'.encode() in app_binary and 'usage-display.txt'.encode() in widget
assert '令牌已存入本机钥匙串'.encode() in app_binary
assert '登录成功，已保存刷新令牌（访问令牌未保存）'.encode() not in app_binary   # old claim gone
assert 'CodexUsage.refresh'.encode() in app_binary                            # background task name
# --- build 27 App screens: connect sheet, per-service pages, card menus, shortened captions ---
assert '令牌只存本机钥匙串'.encode() in app_binary
assert '订阅额度 · 非官方 OAuth 兼容'.encode() in app_binary
assert 'API 平台余额 · 非聊天订阅'.encode() in app_binary
assert 'Claude 订阅额度 · Claude Code OAuth 兼容方式'.encode() not in app_binary   # old caption gone
assert '体验演示'.encode() not in app_binary
assets = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', 'assetutil', '--info', str(app / 'Assets.car')], text=True)
for logo in ['LogoOpenAI', 'LogoClaude', 'LogoDeepSeek', 'LogoAntigravity', 'LogoOpenCodeGo', 'LogoCommandCode']:
    assert f'"{logo}"' in assets, logo
# --- build 30: prove the updated authorization and per-account feedback paths landed ---
assert 'Claude 用量访问被拒绝'.encode() in app_binary
assert '暂无缓存数据'.encode() in app_binary
assert '仅缓存 · 打开 App 更新授权'.encode() in widget
assert '无缓存 · 打开 App 更新授权'.encode() in widget
# --- deleted path, negative markers: a stale payload cannot pass as this revision ---
for gone in ['连接 Claude 账号', '登录页面由网站提供', '已阻止非 Claude 或已知登录提供商']:
    assert gone.encode() not in app_binary, gone

assert '保存账号不代表授权或读取已成功'.encode() in app_binary
# The short accessibility identifier is covered by the navigation contract, not byte scanning.
assert '缓存读取占比'.encode() in app_binary
assert '非请求命中率'.encode() in app_binary
assert '缺报日留空'.encode() in app_binary
assert 'Token 用量由 tokens.ci 提供支持'.encode() in app_binary
assert b'PREVIEW_SECTION' not in app_binary
assert b'Alice39s' not in app_binary
assert '仅缓存 · 打开 App 更新'.encode() in widget
assert 'CodexUsage.TokensCI.read-token.v1'.encode() in app_binary
assert 'TokensCIWidget'.encode() in widget
for binary in (app_binary, widget):
    for gone in ['月预估', '月度预估', '不外推']:
        assert gone.encode() not in binary, gone   # build 42: monthly estimate removed
for binary in (app_binary, widget):
    assert '今日 Token · 上报日'.encode() in binary
    assert '今日 Token · UTC'.encode() not in binary

# --- build 39 bug fixes: new strings prove this revision ---
assert 'Claude 这次登录没有返回续期凭据'.encode() in app_binary      # M2
assert 'Codex 用量格式异常，保留缓存'.encode() in app_binary          # decode error no longer shown as network
assert 'Codex 刷新失败，保留缓存'.encode() in app_binary

for binary in (app_binary, widget):
    for marker in ['https://opencode.ai/zen/go/v1/usage', 'https://api.commandcode.ai/alpha/billing/credits', 'https://api.commandcode.ai/alpha/billing/subscriptions', 'rate-limit-reset-credits', 'CodexUsage.OpenCodeGo.api-key.v1', 'CodexUsage.CommandCode.api-key.v1']:
        assert marker.encode() in binary, marker

out = root / 'Dist/CodeGo-4.7-build44-unsigned.ipa'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in app.rglob('*'):
        if path.is_file():
            archive.write(path, Path('Payload') / app.name / path.relative_to(app))
with zipfile.ZipFile(out) as archive:
    assert archive.testzip() is None
    for suffix, bundle_id in (('', ids[0]), ('PlugIns/CodeGoWidget.appex/', ids[1])):
        info = plistlib.loads(archive.read('Payload/CodeGo.app/' + suffix + 'Info.plist'))
        assert (info['CFBundleIdentifier'], info['CFBundleVersion'], info['CFBundleShortVersionString']) == (bundle_id, '44', '4.7')
print(out)
print('sha256:', hashlib.sha256(out.read_bytes()).hexdigest())
print('bundle IDs preserved from private config; version: 4.7 (44)')
