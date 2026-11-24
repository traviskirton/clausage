#!/usr/bin/env python3
"""From the approved notes in release-notes/<version>.md (a headline sentence, then bullets):

- site/releases/index.html: every version's headline and details, newest first. Each version is a section with the
  anchor `v<version>` (the app links to clausage.ai/releases/#v0.0.9). A version's date is its release tag's date, or
  today while it's being released.
- With `--sparkle <dir>`: for each `Clausage-<version>-<build>.zip` in <dir>, a `.html` beside it holding only the
  headline, which generate_appcast embeds as that update's description.

Drafts (`<!-- draft -->`) are left out.

    tools/releases-page.py                      write the page
    tools/releases-page.py --sparkle release    also write the headline files next to the release zips
    tools/releases-page.py --drafts <file>      preview with drafts included, written to <file> instead
"""
import datetime
import html
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NOTES = ROOT / "release-notes"
OUT = ROOT / "site" / "releases" / "index.html"
MARK = "<!-- draft -->"


def version_key(v):
    return tuple(int(p) for p in v.split("."))


def release_date(version):
    try:
        iso = subprocess.run(["git", "log", "-1", "--format=%cs", f"release-{version}"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout.strip()
        d = datetime.date.fromisoformat(iso)
    except (subprocess.CalledProcessError, ValueError):
        d = datetime.date.today()
    return f"{d:%B} {d.day}, {d.year}"


def inline(text):
    """Escapes, then **bold** and `code`."""
    t = html.escape(text, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"`(.+?)`", r"<code>\1</code>", t)
    return t


def headline(md):
    """The first non-bullet line: the one sentence that goes to Sparkle."""
    return next((l.strip() for l in md.splitlines() if l.strip() and not l.startswith("- ")), "")


def body(md):
    """The headline (and any other paragraphs) as prose, "- " lines as one list."""
    out, items = [], []
    for line in md.splitlines():
        line = line.rstrip()
        if line.startswith("- "):
            items.append(f"<li>{inline(line[2:])}</li>")
            continue
        if items:
            out.append('<ul class="roomy">\n' + "\n".join(items) + "\n</ul>")
            items = []
        if line.strip():
            out.append(f'<p class="prose">{inline(line.strip())}</p>')
    if items:
        out.append('<ul class="roomy">\n' + "\n".join(items) + "\n</ul>")
    return "\n".join(out)


def main():
    drafts = "--drafts" in sys.argv
    out = pathlib.Path(sys.argv[sys.argv.index("--drafts") + 1]).resolve() if drafts else OUT
    versions = []
    for p in NOTES.glob("*.md"):
        if not re.fullmatch(r"\d+(\.\d+)*", p.stem):
            continue
        text = p.read_text()
        if MARK in text and not drafts:
            continue
        versions.append((p.stem, text.replace(MARK, "").strip()))
    versions.sort(key=lambda v: version_key(v[0]), reverse=True)

    toc = "\n".join(f'<a href="#v{v}">{v}</a>' for v, _ in versions)
    sections = "\n\n".join(
        f'<div id="v{v}" class="clause">\n<span class="clause-num">{release_date(v)}</span>\n'
        f'<h2 class="h3">Clausage {v}</h2>\n{body(md)}\n</div>'
        for v, md in versions)

    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Releases · Clausage</title>
<meta name="description" content="What changed in each version of Clausage for Mac.">
<meta name="theme-color" content="#FFFCF6">
<link rel="canonical" href="https://clausage.ai/releases/">
<meta property="og:site_name" content="Clausage">
<meta property="og:type" content="website">
<link rel="icon" href="/assets/mark.svg" type="image/svg+xml">
<link rel="preload" href="/assets/bricolage-grotesque-700.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/assets/site.css">
</head>
<body>
<header class="wrap nav">
<a class="logo" href="/"><img class="mark" src="/assets/mark.svg" width="30" height="30" alt=""><span class="wordmark">clausage</span></a>
<nav>
<a href="/#widgets">Widgets</a>
<a href="/privacy/">Privacy</a>
<a href="https://github.com/traviskirton/clausage">GitHub</a>
<a class="pill" href="/#download">Download</a>
</nav>
</header>

<main>
<section class="wrap page-head">
<span class="chip">Releases</span>
<h1 class="page-title">Fresh off the counter.</h1>
<p class="page-lede">What changed in each version of Clausage for Mac, newest first.</p>
</section>

<section class="wrap policy">
<aside class="toc">
<span>Versions</span>
<nav>
{toc}
</nav>
</aside>

<article class="article">

{sections}

</article>
</section>
</main>

<footer class="wrap page-footer">
<span class="fine">Clausage is an independent app, not made by or affiliated with Anthropic. Claude is a trademark of Anthropic.</span>
<nav><a href="https://github.com/traviskirton/clausage">GitHub</a><a href="https://www.instagram.com/clau.sage/">Instagram</a><a href="/privacy/">Privacy</a><a href="/support/">Support</a><a href="/acknowledgements/">Acknowledgements</a><a href="mailto:counter@clausage.ai?subject=Feedback&amp;body=I%20like%20your%20clausage.">Send feedback</a></nav>
</footer>
</body>
</html>
"""
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(f"Wrote {out} ({len(versions)} versions)")

    if "--sparkle" in sys.argv:
        zips = pathlib.Path(sys.argv[sys.argv.index("--sparkle") + 1]).resolve()
        notes = dict(versions)
        for z in zips.glob("Clausage-*-*.zip"):
            v = z.stem.split("-")[1]
            if v in notes:
                z.with_suffix(".html").write_text(f"<p>{inline(headline(notes[v]))}</p>\n")


if __name__ == "__main__":
    main()
