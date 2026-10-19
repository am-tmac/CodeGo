#!/usr/bin/env python3
"""Build and package an unsigned CodeGo IPA for the version currently in the Xcode project.

    python3 Scripts/release.py            # build + package
    python3 Scripts/release.py --package  # package an existing BuildRelease/ build only

Private identifiers (bundle ID, App Group, Keychain group, team prefix) come only from the
untracked Configuration/Private.xcconfig and are passed to xcodebuild explicitly, so the
shipped bundle IDs never drift from the ones already installed on the device.
Output: Dist/CodeGo-<version>-build<build>-unsigned.ipa (+ SHA-256 on stdout).
"""
from pathlib import Path
import hashlib
import plistlib
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DERIVED = ROOT / 'BuildRelease'
APP = DERIVED / 'Build/Products/Release-iphoneos/CodeGo.app'
APPEX = APP / 'PlugIns/CodeGoWidget.appex'


def private_config():
    values = {}
    for line in (ROOT / 'Configuration/Private.xcconfig').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('//'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    return values


def project_version():
    project = (ROOT / 'CodeGo.xcodeproj/project.pbxproj').read_text()
    marketing = set(re.findall(r'MARKETING_VERSION = ([0-9.]+);', project))
    build = set(re.findall(r'CURRENT_PROJECT_VERSION = ([0-9]+);', project))
    assert len(marketing) == 1 and len(build) == 1, f'targets disagree on version: {marketing} {build}'
    return marketing.pop(), build.pop()


def build(private, version, number):
    keys = ['CODEX_APP_BUNDLE_IDENTIFIER', 'APP_GROUP_IDENTIFIER', 'KEYCHAIN_GROUP_IDENTIFIER', 'AppIdentifierPrefix']
    command = ['xcodebuild', '-project', 'CodeGo.xcodeproj', '-scheme', 'CodeGo', '-configuration', 'Release',
               '-sdk', 'iphoneos', '-xcconfig', 'Configuration/Private.xcconfig', '-derivedDataPath', str(DERIVED),
               'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
               f'CURRENT_PROJECT_VERSION={number}', f'MARKETING_VERSION={version}']
    command += [f'{key}={private[key]}' for key in keys if key in private]
    command += ['build']
    log = ROOT / 'Logs' / f'build{number}-release.log'
    log.parent.mkdir(exist_ok=True)
    with log.open('w') as handle:
        result = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT)
    if result.returncode:
        sys.exit(f'xcodebuild failed ({result.returncode}); see {log}')


def verify(private, version, number):
    ids = (private['CODEX_APP_BUNDLE_IDENTIFIER'], private['CODEX_APP_BUNDLE_IDENTIFIER'] + '.Widget')
    for bundle, bundle_id in zip((APP, APPEX), ids):
        assert bundle.is_dir(), bundle
        assert not (bundle / '_CodeSignature').exists(), f'{bundle} is signed'
        assert not (bundle / 'embedded.mobileprovision').exists(), bundle
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        got = (info['CFBundleIdentifier'], info['CFBundleVersion'], info['CFBundleShortVersionString'], info['MinimumOSVersion'])
        assert got == (bundle_id, number, version, '17.0'), f'unexpected identity {got}'
        assert info['CFBundleDisplayName'] == 'CodeGo', info['CFBundleDisplayName']
        assert '$(' not in str(info), 'unexpanded build setting in Info.plist'
        text = str(info)
        assert private['APP_GROUP_IDENTIFIER'] in text and private['KEYCHAIN_GROUP_IDENTIFIER'] in text, bundle
        executable = bundle / info['CFBundleExecutable']
        assert 'arm64' in subprocess.check_output(['lipo', '-archs', str(executable)], text=True)
    app_binary = (APP / 'CodeGo').read_bytes()
    widget = (APPEX / 'CodeGoWidget').read_bytes()
    # Persisted identifiers that must never change across releases (installed data depends on them).
    for marker in ['CodexUsage.OAuth.private', 'CodexUsage.Claude.oauth.v1', 'CodexUsage.DeepSeek.api-key.v1',
                   'CodexUsage.OpenCodeGo.api-key.v1', 'CodexUsage.CommandCode.api-key.v1',
                   'CodexUsage.TokensCI.read-token.v1', 'CodexUsage.cardOrder.v1']:
        assert marker.encode() in app_binary, marker
    for kind in ['CodexUsageWidget', 'TokensCIWidget']:
        assert kind.encode() in widget, kind
    assets = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', 'assetutil', '--info', str(APP / 'Assets.car')], text=True)
    for appearance in ['UIAppearanceDark', 'ISAppearanceTintable']:
        assert appearance in assets, f'AppIcon missing {appearance}'
    return ids


def package(version, number, ids):
    out = ROOT / 'Dist' / f'CodeGo-{version}-build{number}-unsigned.ipa'
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(APP.rglob('*')):
            if path.is_file():
                archive.write(path, Path('Payload') / APP.name / path.relative_to(APP))
    with zipfile.ZipFile(out) as archive:
        assert archive.testzip() is None
        for suffix, bundle_id in (('', ids[0]), ('PlugIns/CodeGoWidget.appex/', ids[1])):
            info = plistlib.loads(archive.read('Payload/CodeGo.app/' + suffix + 'Info.plist'))
            assert (info['CFBundleIdentifier'], info['CFBundleVersion']) == (bundle_id, number)
    return out


def main():
    private = private_config()
    version, number = project_version()
    if '--package' not in sys.argv:
        build(private, version, number)
    ids = verify(private, version, number)
    out = package(version, number, ids)
    print(out)
    print('sha256:', hashlib.sha256(out.read_bytes()).hexdigest())
    print(f'CodeGo {version} ({number}); bundle IDs from private config')


if __name__ == '__main__':
    main()
