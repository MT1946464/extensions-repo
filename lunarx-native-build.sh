#!/usr/bin/env bash
set -euo pipefail

VERSION_CODE=21
NATIVE_DIR="native"
MODULE="$NATIVE_DIR/src/en/lunarx"

python3 - <<'PY'
from pathlib import Path

# Bump the dedicated LunarX extension version.
p = Path('native/src/en/lunarx/build.gradle.kts')
text = p.read_text()
if 'val extVersionCode = 7' not in text:
    raise SystemExit('Expected LunarX upstream version 7 not found')
text = text.replace('val extVersionCode = 7', 'val extVersionCode = 21', 1)
p.write_text(text)

source = Path('native/src/en/lunarx/src/main/kotlin/eu/kanade/tachiyomi/extension/en/lunarx/LunarX.kt')
text = source.read_text()

# The reader API can return relative image paths. /cdn/... belongs on
# vault.lunarx.to, whereas /api/... belongs on api.lunarx.to. The upstream
# implementation sent every leading-slash path to api.lunarx.to, which
# produces a 404 for real manga images.
old_full = '''                        val full = when {
                            u.startsWith("http") -> u
                            u.startsWith("//") -> "https:" + u
                            u.startsWith("/") -> apiUrl + u
                            else -> apiUrl + "/" + u
                        }'''
new_full = '''                        val full = when {
                            u.startsWith("https://api.lunarx.to/cdn/") ->
                                u.replaceFirst("https://api.lunarx.to/cdn/", "https://vault.lunarx.to/cdn/")
                            u.startsWith("http") -> u
                            u.startsWith("//") -> "https:" + u
                            u.startsWith("/cdn/") -> "https://vault.lunarx.to" + u
                            u.startsWith("/api/") -> apiUrl + u
                            u.startsWith("/") -> apiUrl + u
                            u.startsWith("cdn/") -> "https://vault.lunarx.to/" + u
                            else -> apiUrl + "/" + u
                        }'''
if old_full not in text:
    raise SystemExit('Expected upstream LunarX image URL normalization block not found')
text = text.replace(old_full, new_full, 1)

# Match the successful browser image request supplied by the user:
# root-site Referer, browser UA + image Accept, and no Origin header. Also
# defensively correct any full API-host /cdn/ URL before requesting it.
old_image = '''        val url = page.imageUrl
            ?: throw IOException("LunarX: null image URL")
        Log.d("LunarX", "image -> ${url.take(160)}")
        // The CDN is only fed by browsers/native WebViews on the site, so
        // mirror exactly what a browser <img> request sends: a browser
        // User-Agent and the reader page as Referer, and no Origin header.
        return Request.Builder()
            .url(url)
            .header("User-Agent", BROWSER_UA)
            .header("Referer", "$baseUrl$lastChapterUrl")
            .get()
            .build()'''
new_image = '''        val rawUrl = page.imageUrl
            ?: throw IOException("LunarX: null image URL")
        val url = rawUrl.replace(
            "https://api.lunarx.to/cdn/",
            "https://vault.lunarx.to/cdn/",
        )
        Log.d("LunarX", "image -> ${url.take(160)}")
        return Request.Builder()
            .url(url)
            .header("User-Agent", BROWSER_UA)
            .header("Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
            .header("Referer", "$baseUrl/")
            .get()
            .build()'''
if old_image not in text:
    raise SystemExit('Expected upstream LunarX imageRequest block not found')
text = text.replace(old_image, new_image, 1)

old_ua = '''        private const val BROWSER_UA =
            "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"'''
new_ua = '''        private const val BROWSER_UA =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36 Edg/152.0.0.0"'''
if old_ua not in text:
    raise SystemExit('Expected upstream LunarX browser UA block not found')
text = text.replace(old_ua, new_ua, 1)
source.write_text(text)
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
    'code': 21,
    'version': '1.4.21',
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
    'This build uses the dedicated LunarX reader implementation from codegeasse1/codegeasse-mihon-extension, pinned to commit f9a96725074aee580b27ab39081175de9aee3e11, with extension version code 21 for testing.\n\n'
    'v1.4.21 routes /cdn/ image paths to vault.lunarx.to instead of api.lunarx.to. A GitHub network probe confirmed the same known image path returns HTTP 200 on Vault and HTTP 404 on the API host.\n\n'
    'Image requests also match the successful browser capture: root Referer, Chromium/Edge UA, image Accept, and no Origin.\n\n'
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
git commit -m "Publish native LunarX v1.4.21 Vault CDN routing"
git push origin HEAD:lunarx
