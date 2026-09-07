#!/usr/bin/env bash
set -euo pipefail

VERSION_CODE=22
NATIVE_DIR="native"
MODULE="$NATIVE_DIR/src/en/lunarx"
PACKAGE="eu.kanade.tachiyomi.extension.en.lunarxvaulttest"
APK_NAME="tachiyomi-en.lunarxvaulttest-v1.4.22.apk"

python3 - <<'PY'
from pathlib import Path

# Give this diagnostic build a completely fresh app/package identity so
# Tachimanga cannot reuse the previously installed LunarX extension.
gradle = Path('native/src/en/lunarx/build.gradle.kts')
text = gradle.read_text()
for old, new in [
    ('val extName = "LunarX"', 'val extName = "LunarX Vault Test"'),
    ('val extVersionCode = 7', 'val extVersionCode = 22'),
    ('namespace = "eu.kanade.tachiyomi.extension.en.lunarx"', 'namespace = "eu.kanade.tachiyomi.extension.en.lunarxvaulttest"'),
    ('applicationId = "eu.kanade.tachiyomi.extension.en.lunarx"', 'applicationId = "eu.kanade.tachiyomi.extension.en.lunarxvaulttest"'),
]:
    if old not in text:
        raise SystemExit(f'Expected Gradle text not found: {old}')
    text = text.replace(old, new, 1)
gradle.write_text(text)

source = Path('native/src/en/lunarx/src/main/kotlin/eu/kanade/tachiyomi/extension/en/lunarx/LunarX.kt')
text = source.read_text()

if 'package eu.kanade.tachiyomi.extension.en.lunarx' not in text:
    raise SystemExit('Expected LunarX package declaration not found')
text = text.replace(
    'package eu.kanade.tachiyomi.extension.en.lunarx',
    'package eu.kanade.tachiyomi.extension.en.lunarxvaulttest',
    1,
)
if 'override val name = "LunarX"' not in text:
    raise SystemExit('Expected LunarX source name not found')
text = text.replace('override val name = "LunarX"', 'override val name = "LunarX Vault Test"', 1)

# Confirmed by a live GitHub Actions probe:
#   vault.lunarx.to/cdn/... -> 200
#   api.lunarx.to/cdn/...   -> 404
# Therefore /cdn paths returned by the reader must be routed to Vault.
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

# Match the successful browser image request supplied by the user, and
# defensively fix any full API-host /cdn URL before the request is sent.
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
            ?: throw IOException("LunarX Vault Test: null image URL")
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

python3 - "$APK_PATH" "$SIGNING_FINGERPRINT" "$APK_NAME" <<'PY'
import json
import shutil
import sys
from pathlib import Path

apk = Path(sys.argv[1])
fingerprint = sys.argv[2]
apk_name = sys.argv[3]
repo = Path('repo')
apk_dir = repo / 'apk'
apk_dir.mkdir(parents=True, exist_ok=True)

for old in apk_dir.glob('tachiyomi-en.lunarxvaulttest-v*.apk'):
    old.unlink()
shutil.copy2(apk, apk_dir / apk_name)

entry = {
    'name': 'Tachiyomi: LunarX Vault Test',
    'pkg': 'eu.kanade.tachiyomi.extension.en.lunarxvaulttest',
    'apk': apk_name,
    'lang': 'en',
    'code': 22,
    'version': '1.4.22',
    'nsfw': 1,
    'sources': [{
        'name': 'LunarX Vault Test',
        'lang': 'en',
        'id': '7381161132566237407',
        'baseUrl': 'https://lunarx.to',
    }],
}
(repo / 'index.min.json').write_text(json.dumps([entry], separators=(',', ':')) + '\n')
(repo / 'repo.json').write_text(json.dumps({
    'meta': {
        'name': 'MT1946464 LunarX Vault Test',
        'website': 'https://github.com/MT1946464/extensions-repo/tree/lunarx',
        'signingKeyFingerprint': fingerprint,
    }
}, indent=2) + '\n')
(repo / 'README-LUNARX.md').write_text(
    '# LunarX Vault Test for Tachimanga\n\n'
    'Fresh package/source identity diagnostic build, based on the dedicated LunarX reader.\n\n'
    'Confirmed CDN routing: `/cdn/...` is sent to `https://vault.lunarx.to`; `/api/...` remains on `https://api.lunarx.to`.\n\n'
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
git commit -m "Publish LunarX Vault Test v1.4.22"
git push origin HEAD:lunarx
