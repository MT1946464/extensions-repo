from pathlib import Path

p = Path('repo/lunarx-build.sh')
text = p.read_text()

text = text.replace('VERSION_CODE=17', 'VERSION_CODE=18', 1)
text = text.replace('version_code = 17', 'version_code = 18')
text = text.replace(
    'Publish LunarX v1.4.17 endpoint and repo-signing fix',
    'Publish LunarX v1.4.18 image header fix',
)

old = '''new_image = 'return GET(page.imageUrl!!.replace("https://storage.lunaranime.ru", "https://vault.lunarx.to"), imageHeaders)' '''.strip()
new = '''new_image = 'return GET(page.imageUrl!!.replace("https://storage.lunaranime.ru", "https://vault.lunarx.to"), imageHeaders.newBuilder().removeAll("Origin").set("Referer", "$baseUrl/").set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36 Edg/152.0.0.0").build())' '''.strip()

if old not in text:
    raise SystemExit('Could not find v17 image request replacement')
text = text.replace(old, new, 1)

p.write_text(text)
