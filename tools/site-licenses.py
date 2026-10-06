#!/usr/bin/env python3
"""Fill every <pre data-license="path"> in site/acknowledgements/index.html with that file's text, HTML-escaped.

Paths are relative to the repo root. Run after packages change (./build.sh fetches them into build/SourcePackages).
"""
import html, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
page = root / "site/acknowledgements/index.html"
src = page.read_text()

def fill(m):
    path = root / m.group(1)
    if not path.exists():
        sys.exit(f"missing license file: {path}")
    return f'<pre data-license="{m.group(1)}">{html.escape(path.read_text().strip())}</pre>'

out, n = re.subn(r'<pre data-license="([^"]+)">.*?</pre>', fill, src, flags=re.S)
page.write_text(out)
print(f"filled {n} license blocks")
