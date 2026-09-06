#!/usr/bin/env bash
set -euo pipefail

VERSION_CODE=17

DECRYPTOR_DST="source/src/all/lunaranime/src/eu/kanade/tachiyomi/extension/all/lunaranime/LunarDecryptor.kt"
LUNAR_DST="source/src/all/lunaranime/src/eu/kanade/tachiyomi/extension/all/lunaranime/LunarAnime.kt"

cp repo/lunarx-patches/LunarDecryptor.kt "$DECRYPTOR_DST"

python3 - <<'PY'
from pathlib import Path

version_code = 17

gradle = Path('source/src/all/lunaranime/build.gradle.kts')
text = gradle.read_text()
text = text.replace('name = "Lunar Manga"', 'name = "LunarX Manga"')
text = text.replace('versionCode = 12', f'versionCode = {version_code}')
text = text.replace('baseUrl = "https://lunaranime.ru"', 'baseUrl = "https://lunarx.to"')
marker = 'name = "LunarX Manga"\n'
if marker not in text:
    raise SystemExit('Could not find Lunar extension name block')
text = text.replace(marker, marker + '    pkgName = "all.lunarx"\n', 1)
gradle.write_text(text)

versions = Path('source/gradle/kei.versions.toml')
text = versions.read_text()
if 'android-sdk-min = "26"' not in text:
    raise SystemExit('Expected Keiyoushi minSdk 26 not found')
versions.write_text(text.replace('android-sdk-min = "26"', 'android-sdk-min = "21"', 1))

proguard = Path('source/common/proguard-rules.pro')
text = proguard.read_text()
if '#-dontoptimize' not in text:
    raise SystemExit('Expected commented -dontoptimize rule not found')
proguard.write_text(text.replace('#-dontoptimize', '-dontoptimize', 1))

lunar = Path('source/src/all/lunaranime/src/eu/kanade/tachiyomi/extension/all/lunaranime/LunarAnime.kt')
text = lunar.read_text()
text = text.replace('https://api.lunaranime.ru', 'https://api.lunarx.to')
text = text.replace('https://storage.lunaranime.ru', 'https://vault.lunarx.to')

old_headers = '''    override fun headersBuilder(): Headers.Builder = super.headersBuilder()
        .add("Referer", "$baseUrl/")'''
new_headers = '''    override fun headersBuilder(): Headers.Builder = super.headersBuilder()
        .add("Referer", "$baseUrl/")
        .add("Origin", baseUrl)'''
if old_headers not in text:
    raise SystemExit('Expected headersBuilder block not found')
text = text.replace(old_headers, new_headers, 1)

old_chapters = '''        val passwordUrl = API_URL.toHttpUrl().newBuilder()
            .addPathSegments("api/manga/password/info")
            .addPathSegment(slug)
            .build()
        val passwordRequest = GET(passwordUrl.toString(), headers)
        val passwordInfo = client.newCall(passwordRequest).execute().parseAs<LunarPasswordInfoResponse>()

        val requestUrl = API_URL.toHttpUrl().newBuilder()
            .addPathSegments("api/manga")
            .addPathSegment(slug)
            .build()
        val request = GET(requestUrl.toString(), headers)

        val result = client.newCall(request).execute().parseAs<LunarChapterListResponse>()

        result.data.filter {
            lang == "all" || it.language == internalLang
        }.map { chapter ->
            val isLocked = passwordInfo.hasSeriesPassword ||
                passwordInfo.chapterPasswords.any {
                    it.chapterNumber == chapter.chapter && (it.language == null || it.language == chapter.language)
                }
            chapter.toSChapter(slug, isLocked)
        }.reversed()'''
new_chapters = '''        val requestUrl = API_URL.toHttpUrl().newBuilder()
            .addPathSegments("api/manga")
            .addPathSegment(slug)
            .build()
        val request = GET(requestUrl.toString(), headers)

        val result = client.newCall(request).execute().parseAs<LunarChapterListResponse>()

        result.data.filter {
            lang == "all" || it.language == internalLang
        }.map { chapter ->
            chapter.toSChapter(slug, false)
        }.reversed()'''
if old_chapters not in text:
    raise SystemExit('Expected legacy chapter-list block not found')
text = text.replace(old_chapters, new_chapters, 1)

old_pages = '''        val response = client.newCall(GET(chapterUrl)).execute()
        if (!response.isSuccessful) error("HTTP ${response.code} fetching chapter")

        // Required requests or fake images are returned
        viewChapter(slug, chapterNumber, language)

        // I see decryption is always required now
        val decryptedImages = crypto.decryptChapterImages(response, slug, chapterNumber, language)'''
new_pages = '''        // Required request or fake images are returned.
        viewChapter(slug, chapterNumber, language)

        // Updated LunarX token/session payload path.
        val decryptedImages = crypto.getChapterImages(slug, chapterNumber, language)'''
if old_pages not in text:
    raise SystemExit('Expected old chapter decryption block not found')
text = text.replace(old_pages, new_pages, 1)

old_image = 'return GET(page.imageUrl!!, imageHeaders)'
new_image = 'return GET(page.imageUrl!!.replace("https://storage.lunaranime.ru", "https://vault.lunarx.to"), imageHeaders)'
if old_image not in text:
    raise SystemExit('Expected imageRequest line not found')
text = text.replace(old_image, new_image, 1)

text = text.replace(
    'if (url.contains("vault.lunarx.to")) {',
    'if (url.contains("vault.lunarx.to") || url.contains("storage.lunarx.to")) {',
)
lunar.write_text(text)
PY

(
  cd source
  ./gradlew :src:all:lunaranime:assembleRelease
)

APK_PATH=$(find source/src/all/lunaranime/build/outputs/apk/release -type f -name '*.apk' | head -n1)
if [[ -z "${APK_PATH:-}" ]]; then
  echo "No APK found to sign" >&2
  exit 1
fi

KEYSTORE="source/lunarx-ci-signing.jks"
keytool -genkeypair \
  -keystore "$KEYSTORE" \
  -storepass lunarxpass \
  -keypass lunarxpass \
  -alias lunarx \
  -keyalg RSA \
  -keysize 2048 \
  -validity 3650 \
  -dname "CN=LunarX Tachimanga, OU=Extensions, O=MT1946464, C=AU" \
  -noprompt >/dev/null 2>&1

APKSIGNER=$(find "${ANDROID_HOME:-$ANDROID_SDK_ROOT}/build-tools" -type f -name apksigner | sort -V | tail -n1)
if [[ -z "${APKSIGNER:-}" ]]; then
  echo "apksigner not found" >&2
  exit 1
fi

"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias lunarx \
  --ks-pass pass:lunarxpass \
  --key-pass pass:lunarxpass \
  "$APK_PATH"

CERT_OUTPUT=$("$APKSIGNER" verify --print-certs "$APK_PATH")
echo "$CERT_OUTPUT"
SIGNING_FINGERPRINT=$(printf '%s\n' "$CERT_OUTPUT" | awk '/certificate SHA-256 digest/ {print tolower($NF); exit}')
if [[ ! "$SIGNING_FINGERPRINT" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid signing certificate fingerprint: $SIGNING_FINGERPRINT" >&2
  exit 1
fi
printf '%s\n' "$SIGNING_FINGERPRINT" > source/lunarx-signing-fingerprint.txt

echo "LunarX signing fingerprint: $SIGNING_FINGERPRINT"

python3 - <<'PY'
import json
import shutil
from pathlib import Path

version_code = 17
module = Path('source/src/all/lunaranime/build')
info_path = module / 'keiyoushi-source-info.json'
if not info_path.exists():
    raise SystemExit(f'Missing source metadata: {info_path}')
info = json.loads(info_path.read_text())

fingerprint_path = Path('source/lunarx-signing-fingerprint.txt')
if not fingerprint_path.exists():
    raise SystemExit('Missing signing fingerprint')
signing_fingerprint = fingerprint_path.read_text().strip()

apks = list((module / 'outputs/apk/release').glob('*.apk'))
jars = list((module / 'outputs/jar/release').glob('*.jar'))
if len(apks) != 1:
    raise SystemExit(f'Expected one APK, found {apks}')
if len(jars) != 1:
    raise SystemExit(f'Expected one JAR, found {jars}')
apk = apks[0]
jar = jars[0]

repo = Path('repo')
apk_dir = repo / 'apk'
jar_dir = repo / 'jar'
apk_dir.mkdir(parents=True, exist_ok=True)
jar_dir.mkdir(parents=True, exist_ok=True)

for pattern in ('tachiyomi-all.lunaranime-v*', 'tachiyomi-all.lunarx-v*'):
    for old in apk_dir.glob(pattern):
        old.unlink()
    for old in jar_dir.glob(pattern):
        old.unlink()

shutil.copy2(apk, apk_dir / apk.name)
shutil.copy2(jar, jar_dir / jar.name)
shutil.copy2(jar, apk_dir / jar.name)

sources = []
for src in info['sources']:
    item = {
        'name': src['name'],
        'lang': src['lang'],
        'id': str(src['id']),
        'baseUrl': src['baseUrl'],
    }
    if 'versionId' in src:
        item['versionId'] = src['versionId']
    sources.append(item)

entry = {
    'name': f"Tachiyomi: {info['name']}",
    'pkg': info['packageName'],
    'apk': apk.name,
    'lang': 'all',
    'code': version_code,
    'version': info['versionName'],
    'nsfw': 0,
    'sources': sources,
}
(repo / 'index.min.json').write_text(json.dumps([entry], ensure_ascii=False, separators=(',', ':')) + '\n')

for stale in ('index.json', 'index.pb', 'release-assets.json'):
    p = repo / stale
    if p.exists():
        p.unlink()

(repo / 'repo.json').write_text(
    json.dumps({
        'meta': {
            'name': 'MT1946464 LunarX',
            'website': 'https://github.com/MT1946464/extensions-repo/tree/lunarx',
            'signingKeyFingerprint': signing_fingerprint,
        }
    }, indent=2) + '\n'
)

repo_url = 'https://raw.githubusercontent.com/MT1946464/extensions-repo/lunarx/index.min.json'
apk_url = 'https://raw.githubusercontent.com/MT1946464/extensions-repo/lunarx/apk/' + apk.name
jar_url = 'https://raw.githubusercontent.com/MT1946464/extensions-repo/lunarx/apk/' + jar.name

(repo / 'index.html').write_text(
    '<!doctype html><html><body><a href="apk/' + apk.name + '">Tachiyomi: LunarX Manga</a></body></html>\n'
)
(repo / 'README-LUNARX.md').write_text(
    '# LunarX Manga for Tachimanga\n\n'
    'Independent Tachimanga compatibility build.\n\n'
    'Repository URL: `' + repo_url + '`\n\n'
    'Direct APK: `' + apk_url + '`\n\n'
    'Direct JAR: `' + jar_url + '`\n\n'
    'Compatibility changes: minSdk 21, optimization disabled, unique package, LunarX domains, updated chapter payload decryptor, Origin header, obsolete password endpoint removed, and APK signing metadata.\n'
)
PY

cd repo
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
if git diff --cached --quiet; then
  echo "No published changes"
  exit 0
fi
git commit -m "Publish LunarX v1.4.17 endpoint and repo-signing fix"
git push origin HEAD:lunarx
