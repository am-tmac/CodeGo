from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
private = {}
for line in (root/'Configuration/Private.xcconfig').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('//'):
        key, value = line.split('=', 1)
        private[key.strip()] = value.strip()
keys = ['CODEX_APP_BUNDLE_IDENTIFIER', 'APP_GROUP_IDENTIFIER', 'KEYCHAIN_GROUP_IDENTIFIER', 'AppIdentifierPrefix']
command = ['xcodebuild', '-project', 'CodexUsage.xcodeproj', '-scheme', 'CodexUsage', '-configuration', 'Release', '-sdk', 'iphoneos', '-xcconfig', 'Configuration/Private.xcconfig', '-derivedDataPath', 'Build34Direct', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CURRENT_PROJECT_VERSION=34', 'MARKETING_VERSION=3.0']
command += [key+'='+private[key] for key in keys if key in private]
command += ['build']
with (root/'Logs/build34-release.log').open('w') as log:
    result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
print('Release exit:', result.returncode)
raise SystemExit(result.returncode)
