# LunarX for Tachimanga

This build uses the dedicated LunarX reader implementation from codegeasse1/codegeasse-mihon-extension, pinned to commit f9a96725074aee580b27ab39081175de9aee3e11, with extension version code 21 for testing.

v1.4.21 routes /cdn/ image paths to vault.lunarx.to instead of api.lunarx.to. A GitHub network probe confirmed the same known image path returns HTTP 200 on Vault and HTTP 404 on the API host.

Image requests also match the successful browser capture: root Referer, Chromium/Edge UA, image Accept, and no Origin.

Repository URL: `https://raw.githubusercontent.com/MT1946464/extensions-repo/lunarx/index.min.json`
