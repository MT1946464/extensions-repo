#!/usr/bin/env bash
set -euo pipefail

VERSION_CODE=19
NATIVE_DIR="native"
MODULE="$NATIVE_DIR/src/en/lunarx"

python3 - <<'PY'
from pathlib import Path
p = Path('native/src/en/lunarx/build.gradle.kts')
text = p.read_text()
if 'val extVersionCode = 7' not in text:
    raise SystemExit('Expected LunarX upstream version 7 not found')
text = text.replace('val extVersionCode = 7', 'val extVersionCode = 19', 1)
p.write_text(text)
PY

(
  cd "$NATIVE_DIR"
  gradle :src:en:lunarx:assembleDebug --stacktrace
)

APK_PATH=$(find "$MODULE/build/outputs/apk/debug" -type f -name '*.apk' | head -n1)
if [[ -z "${APK_PATH:-}" ]]; then
  echo "No native LunarX APK found" >&2
  exit 1
fi

APKSIGNER=$(find "${ANDROID_HOME:-$ANDROID_SDK_ROOT}/build-tools" -type f -name apksigner | sort -V | tail -n1)
if [[ -z "${APKSIGNER:-}" ]]; then
  echo "apksigner not found" >&2
  exit 1
fi

CERT_OUTPUT=$("$APKSIGNER" verify --print-certs "$APK_PATH")
SIGNING_FINGERPRINT=$(printf '%s\n' "$CERT_OUTPUT" | awk '/certificate SHA-256 digest/ {print tolower($NF); exit}')
if [[ ! "$SIGNING_FINGERPRINT" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid debug signing certificate fingerprint: $SIGNING_FINGERPRINT" >&2
  exit 1
fi

python3 - "$APK_PATH" "$SIGNING_FINGERPRINT" <<'PY'
import json
import shutil
import sys
from pathlib import Path

apk = Path(sys.argv[1])
fingerprint = sys.argv[2]
repo = Path('repo')
apk_dir = repo / 'apk'
apk_dir.mkdir(parents=True, exist_ok=True)

for old in apk_dir.glob('tachiyomi-en.lunarx-v*.apk'):
    old.unlink()
shutil.copy2(apk, apk_dir / apk.name)

entry = {
    'name': 'Tachiyomi: LunarX',
    'pkg': 'eu.kanade.tachiyomi.extension.en.lunarx',
    'apk': apk.name,
    'lang': 'en',
    'code': 19,
    'version': '1.4.19',
    'nsfw': 1,
    'sources': [{
        'name': 'LunarX',
        'lang': 'en',
        'id': '3044049178005900465',
        'baseUrl': 'https://lunarx.to',
    }],
}
(repo / 'index.min.json').write_text(json.dumps([entry], separators=(',', ':')) + '\n')
(repo / 'repo.json').write_text(json.dumps({
    'meta': {
        'name': 'MT1946464 LunarX Native',
        'website': 'https://github.com/MT1946464/extensions-repo/tree/lunarx',
        'signingKeyFingerprint': fingerprint,
    }
}, indent=2) + '\n')
(repo / 'README-LUNARX.md').write_text(
    '# LunarX for Tachimanga\n\n'
    'This build uses the dedicated LunarX reader implementation from codegeasse1/codegeasse-mihon-extension, pinned to commit f9a96725074aee580b27ab39081175de9aee3e11, with extension version code 19 for testing.\n\n'
    'Repository URL: `https://raw.githubusercontent.com/MT1946464/extensions-repo/lunarx/index.min.json`\n'
)
PY

cd repo
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
if git diff --cached --quiet; then
  echo "No changes to publish"
  exit 0
fi
git commit -m "Publish native LunarX v1.4.19"
git push origin HEAD:lunarx
