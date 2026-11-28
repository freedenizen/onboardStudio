#!/usr/bin/env python3
"""Turn docs/user-guide.md into an Apple Help Book bundle (OnboardStudio.help).

    Scripts/make-help-book.py --out <directory> [--version X.Y.Z] [--source <file.md>]

Writes <directory>/OnboardStudio.help: one page per `## ` section of the guide, an index, a style
sheet, the images the guide uses and, on a Mac, the search indexes `hiutil` builds. Standard
library only.

The converter handles exactly the Markdown the guide uses: headings, wrapped paragraphs, bold,
italic, inline code, links, images, ordered and unordered lists (nested, with multi-line and
multi-paragraph items), tables, fenced code blocks and backslash escapes. A link to a heading that
does not exist stops the build.
"""

import argparse
import html
import os
import plistlib
import posixpath
import re
import shutil
import subprocess
import sys
import urllib.parse

BUNDLE_NAME = "OnboardStudio.help"
BOOK_TITLE = "Onboard Studio Help"
GITHUB_BLOB = "https://github.com/freedenizen/onboardStudio/blob/main/"
RESERVED_PAGES = {"index", "style"}


class BuildError(Exception):
    pass


# ---------------------------------------------------------------------------------------------
# Block parsing

LIST_RE = re.compile(r"^( *)([-*+]|\d{1,9}[.)])( +)(\S.*)?$")
HEADING_RE = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*([^`\s]*)")
TABLE_SEP_RE = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def is_blank(line):
    return not line.strip()


def is_table_start(lines, i):
    return (
        i + 1 < len(lines)
        and "|" in lines[i]
        and "|" in lines[i + 1]
        and TABLE_SEP_RE.match(lines[i + 1]) is not None
        and lines[i].lstrip().startswith("|")
    )


def split_row(line):
    """Cells of a table row; pipes inside code spans or escaped with a backslash do not split."""
    s = line.strip()
    cells, cur, in_code, i = [], [], False, 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s) and s[i + 1] == "|":
            cur.append("|")
            i += 2
            continue
        if c == "`":
            in_code = not in_code
        if c == "|" and not in_code:
            cells.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    cells.append("".join(cur))
    if s.startswith("|"):
        cells = cells[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        cells = cells[:-1]
    return [c.strip() for c in cells]


def starts_block(lines, i):
    """True when line i begins something that interrupts a paragraph."""
    line = lines[i]
    if HEADING_RE.match(line) or FENCE_RE.match(line) or is_table_start(lines, i):
        return True
    m = LIST_RE.match(line)
    if m and m.group(4):
        marker = m.group(2)
        return not marker[0].isdigit() or marker[:-1] == "1"
    return False


def parse_blocks(lines, base):
    """Parse lines (source line number of lines[0] is `base`) into a list of block tuples."""
    blocks = []
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if is_blank(line):
            i += 1
            continue
        fm = FENCE_RE.match(line)
        if fm:
            fence = fm.group(1)
            j = i + 1
            body = []
            while j < n and not re.match(r"^ {0,3}" + re.escape(fence[0]) + "{%d,}\\s*$" % len(fence), lines[j]):
                body.append(lines[j])
                j += 1
            blocks.append(("code", fm.group(2), "\n".join(body), base + i))
            i = j + 1
            continue
        hm = HEADING_RE.match(line)
        if hm:
            blocks.append(("h", len(hm.group(1)), hm.group(2).strip(), base + i))
            i += 1
            continue
        if is_table_start(lines, i):
            header = split_row(lines[i])
            aligns = []
            for cell in split_row(lines[i + 1]):
                left, right = cell.startswith(":"), cell.endswith(":")
                aligns.append("center" if left and right else "right" if right else "left" if left else "")
            rows, j = [], i + 2
            while j < n and not is_blank(lines[j]) and "|" in lines[j]:
                rows.append(split_row(lines[j]))
                j += 1
            blocks.append(("table", header, aligns, rows, base + i))
            i = j
            continue
        lm = LIST_RE.match(line)
        if lm and indent_of(line) < 4:
            block, i = parse_list(lines, i, base)
            blocks.append(block)
            continue
        j = i + 1
        while j < n and not is_blank(lines[j]) and not starts_block(lines, j):
            j += 1
        text = "\n".join(l.strip() for l in lines[i:j])
        blocks.append(("p", text, base + i, [l for l in lines[i:j]]))
        i = j
    return blocks


def parse_list(lines, i, base):
    n = len(lines)
    first = LIST_RE.match(lines[i])
    ordered = first.group(2)[0].isdigit()
    start = int(first.group(2)[:-1]) if ordered else 1
    items = []
    list_line = base + i
    while i < n:
        m = LIST_RE.match(lines[i])
        if not m or not m.group(4):
            break
        if (m.group(2)[0].isdigit()) != ordered:
            break
        if items and indent_of(lines[i]) >= items[-1]["content_indent"]:
            break
        content_indent = len(m.group(1)) + len(m.group(2)) + min(len(m.group(3)), 4)
        item_lines = [m.group(4)]
        item_base = base + i
        internal_blank = False
        j = i + 1
        while j < n:
            line = lines[j]
            if is_blank(line):
                k = j
                while k < n and is_blank(lines[k]):
                    k += 1
                if k < n and indent_of(lines[k]) >= content_indent:
                    item_lines.extend([""] * (k - j))
                    internal_blank = True
                    j = k
                    continue
                break
            if indent_of(line) >= content_indent:
                item_lines.append(line[content_indent:])
            elif LIST_RE.match(line) and LIST_RE.match(line).group(4):
                break
            elif is_blank(lines[j - 1]) or HEADING_RE.match(line) or FENCE_RE.match(line):
                break
            else:
                item_lines.append(line.lstrip())  # lazy continuation of the item's paragraph
            j += 1
        items.append(
            {
                "content_indent": content_indent,
                "blocks": parse_blocks(item_lines, item_base),
                "loose": internal_blank,
            }
        )
        i = j
        k = i
        while k < n and is_blank(lines[k]):
            k += 1
        nm = LIST_RE.match(lines[k]) if k < n else None
        if nm and nm.group(4) and (nm.group(2)[0].isdigit()) == ordered and indent_of(lines[k]) < 4:
            i = k
        else:
            break
    return ("list", ordered, start, items, list_line), i


# ---------------------------------------------------------------------------------------------
# Inline rendering

PH_OPEN, PH_CLOSE = "\ue000", "\ue001"


class Context:
    """What inline rendering needs to know about the page and the guide."""

    def __init__(self, anchors, source_dir, repo_rel_dir, images):
        self.anchors = anchors  # slug -> page file
        self.source_dir = source_dir
        self.repo_rel_dir = repo_rel_dir  # directory of the source, relative to the repo root
        self.images = images  # set of relative image paths used
        self.page = "index.html"
        self.block_lines = []  # (first line number, raw lines) of the block being rendered
        self.line = 0


def slugify(text):
    text = text.strip().lower()
    out = []
    for ch in text:
        if ch == " ":
            out.append("-")
        elif ch == "-" or ch == "_" or ch.isalnum():
            out.append(ch)
    return "".join(out)


def plain_text(md):
    """The text a reader sees, without Markdown markup (for slugs and descriptions)."""
    md = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", md)
    md = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", md)
    md = re.sub(r"\\([\\`*_{}\[\]()#+\-.!|<>~])", r"\1", md)
    md = md.replace("`", "")
    md = md.replace("*", "")
    return re.sub(r"\s+", " ", md).strip()


def locate(ctx, needle):
    """Line number in the guide where `needle` appears in the block being rendered."""
    first, lines = ctx.block_lines
    for offset, line in enumerate(lines):
        if needle in line:
            return first + offset
    return first


def fail_at(ctx, needle, message):
    raise BuildError("%s:%d: %s" % (ctx.source_name, locate(ctx, needle), message))


def resolve_link(ctx, target):
    if target.startswith("#"):
        anchor = target[1:]
        page = ctx.anchors.get(anchor)
        if page is None:
            fail_at(ctx, "](" + target, "broken link %s: no heading with that anchor" % target)
        frag = "#" + urllib.parse.quote(anchor, safe="-_")
        return frag if page == ctx.page else page + frag
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
        return target
    path, _, frag = target.partition("#")
    joined = posixpath.normpath(posixpath.join(ctx.repo_rel_dir, path))
    if joined.startswith("../"):
        fail_at(ctx, "](" + target, "link %s leaves the repository" % target)
    return GITHUB_BLOB + urllib.parse.quote(joined) + ("#" + frag if frag else "")


def image_html(ctx, alt, src):
    rel = posixpath.normpath(src)
    if rel.startswith("/") or rel.startswith(".."):
        fail_at(ctx, "](" + src, "image %s is outside the guide's directory" % src)
    if not os.path.isfile(os.path.join(ctx.source_dir, rel)):
        fail_at(ctx, "](" + src, "missing image file %s" % src)
    ctx.images.add(rel)
    return '<img src="%s" alt="%s">' % (html.escape(rel, quote=True), html.escape(plain_text(alt), quote=True))


LINK_RE = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
BOLD_RE = re.compile(r"\*\*(?=\S)(.+?)(?<=\S)\*\*", re.S)
ITALIC_RE = re.compile(r"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])", re.S)
CODE_RE = re.compile(r"(`+)(.+?)(?<!`)\1(?!`)", re.S)


def inline(ctx, text):
    stash = []

    def hold(markup):
        stash.append(markup)
        return "%s%d%s" % (PH_OPEN, len(stash) - 1, PH_CLOSE)

    def code(m):
        body = re.sub(r"\s+", " ", m.group(2))
        if len(body) > 2 and body[0] == " " and body[-1] == " " and body.strip():
            body = body[1:-1]
        return hold("<code>%s</code>" % html.escape(body, quote=False))

    # Code spans first, so nothing inside them is touched again.
    text = CODE_RE.sub(code, text)
    # A backslash right before ** is a literal backslash (the guide writes **⌘\** for the key).
    text = re.sub(r"\\(?=\*\*)", lambda m: hold("\\"), text)
    text = re.sub(
        r"\\([\\`*_{}\[\]()#+\-.!|<>~])", lambda m: hold(html.escape(m.group(1), quote=False)), text
    )

    def link(m):
        bang, label, target = m.group(1), m.group(2), m.group(3)
        if bang:
            return hold(image_html(ctx, label, target))
        href = resolve_link(ctx, target)
        return hold('<a href="%s">%s</a>' % (html.escape(href, quote=True), inline(ctx, label)))

    text = LINK_RE.sub(link, text)
    text = html.escape(text, quote=False)
    text = BOLD_RE.sub(lambda m: "<strong>%s</strong>" % ITALIC_RE.sub(r"<em>\1</em>", m.group(1)), text)
    text = ITALIC_RE.sub(r"<em>\1</em>", text)
    pattern = re.compile("%s(\\d+)%s" % (PH_OPEN, PH_CLOSE))
    while pattern.search(text):
        text = pattern.sub(lambda m: stash[int(m.group(1))], text)
    return text


# ---------------------------------------------------------------------------------------------
# Block rendering

def render_blocks(ctx, blocks, headings, out, tight=False):
    for b in blocks:
        kind = b[0]
        if kind == "h":
            _, level, text, _line = b
            slug = headings[id(b)]
            ctx.block_lines = (b[3], [text])
            out.append(
                '<a name="%s"></a>\n<h%d id="%s">%s</h%d>' % (slug, level, slug, inline(ctx, text), level)
            )
        elif kind == "p":
            ctx.block_lines = (b[2], b[3])
            body = inline(ctx, b[1])
            out.append(body if tight else "<p>%s</p>" % body)
        elif kind == "code":
            lang = ' class="language-%s"' % html.escape(b[1], quote=True) if b[1] else ""
            out.append("<pre><code%s>%s</code></pre>" % (lang, html.escape(b[2], quote=False)))
        elif kind == "table":
            _, header, aligns, rows, line = b
            ctx.block_lines = (line, [])

            def cell(tag, text, col):
                style = ' style="text-align:%s"' % aligns[col] if col < len(aligns) and aligns[col] else ""
                return "<%s%s>%s</%s>" % (tag, style, inline(ctx, text), tag)

            out.append("<table>")
            out.append("<thead><tr>%s</tr></thead>" % "".join(cell("th", c, k) for k, c in enumerate(header)))
            out.append("<tbody>")
            for row in rows:
                row = (row + [""] * len(header))[: len(header)]
                out.append("<tr>%s</tr>" % "".join(cell("td", c, k) for k, c in enumerate(row)))
            out.append("</tbody>\n</table>")
        elif kind == "list":
            _, ordered, start, items, _line = b
            tag = "ol" if ordered else "ul"
            attr = ' start="%d"' % start if ordered and start != 1 else ""
            out.append("<%s%s>" % (tag, attr))
            for item in items:
                inner = []
                render_blocks(ctx, item["blocks"], headings, inner, tight=not item["loose"])
                out.append("<li>" + "\n".join(inner) + "</li>")
            out.append("</%s>" % tag)


def first_sentence(blocks):
    for b in blocks:
        if b[0] != "p":
            continue
        text = plain_text(b[1])
        if not text:
            continue
        m = re.search(r"(?<=[.!?])\s", text)
        sentence = text[: m.start()] if m else text
        return sentence if len(sentence) <= 250 else sentence[:247].rstrip() + "..."
    return BOOK_TITLE


# ---------------------------------------------------------------------------------------------
# Output

CSS = """\
:root { color-scheme: light dark; }
body {
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  max-width: 44rem; margin: 0 auto; padding: 1.5rem 1.25rem 4rem;
  color: #1d1d1f; background: #fff;
}
a { color: #0066cc; }
nav.top { font-size: 0.9em; margin-bottom: 1rem; }
h1, h2, h3, h4 { line-height: 1.25; }
h2 { margin-top: 2rem; }
h3 { margin-top: 1.6rem; }
img { max-width: 100%; height: auto; border-radius: 6px; }
code, pre { font: 0.9em ui-monospace, SFMono-Regular, Menlo, monospace; }
code { background: rgba(127, 127, 127, 0.15); padding: 0.1em 0.3em; border-radius: 4px; }
pre { background: rgba(127, 127, 127, 0.12); padding: 0.8em 1em; border-radius: 6px; overflow-x: auto; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; margin: 1em 0; }
th, td { border: 1px solid rgba(127, 127, 127, 0.5); padding: 0.35em 0.7em; text-align: left; vertical-align: top; }
th { background: rgba(127, 127, 127, 0.12); }
li { margin: 0.25em 0; }
@media (prefers-color-scheme: dark) {
  body { color: #f5f5f7; background: #1e1e1e; }
  a { color: #64a8ff; }
}
"""


def page_html(title, description, body, index=False):
    apple_title = '<meta name="AppleTitle" content="%s">\n' % BOOK_TITLE if index else ""
    return (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n<head>\n'
        '<meta charset="utf-8">\n'
        "<title>%s</title>\n"
        "%s"
        '<meta name="robots" content="index, anchors">\n'
        '<meta name="description" content="%s">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        '<link rel="stylesheet" href="style.css">\n'
        "</head>\n<body>\n%s\n</body>\n</html>\n"
    ) % (html.escape(title, quote=False), apple_title, html.escape(description, quote=True), body)


def build(source, out_dir, version):
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source = os.path.abspath(source)
    source_dir = os.path.dirname(source)
    rel = os.path.relpath(source_dir, repo)
    repo_rel_dir = "docs" if rel.startswith("..") else ("" if rel == "." else rel.replace(os.sep, "/"))
    with open(source, encoding="utf-8") as f:
        lines = [l.rstrip("\n").expandtabs(4) for l in f.read().split("\n")]
    blocks = parse_blocks(lines, 1)

    # Slugs for every heading, in document order, the way GitHub makes them; and which page each
    # lands on.
    headings, anchors, seen = {}, {}, {}
    page_of_block = {}
    title = BOOK_TITLE
    preamble, sections = [], []
    current = None
    for b in blocks:
        if b[0] == "h":
            base = slugify(plain_text(b[2]))
            count = seen.get(base, 0)
            seen[base] = count + 1
            slug = base if count == 0 else "%s-%d" % (base, count)
            headings[id(b)] = slug
            if b[1] == 1 and not sections and title == BOOK_TITLE and not preamble:
                title = plain_text(b[2])
            if b[1] == 2:
                if slug in RESERVED_PAGES:
                    raise BuildError("section %r would overwrite the %s page" % (b[2], slug))
                current = {"slug": slug, "heading": b, "blocks": []}
                sections.append(current)
        if current is None:
            preamble.append(b)
        else:
            current["blocks"].append(b)
        page_file = "index.html" if current is None else current["slug"] + ".html"
        if b[0] == "h":
            anchors[headings[id(b)]] = page_file
    if not sections:
        raise BuildError("%s has no `## ` section" % source)

    images = set()
    ctx = Context(anchors, source_dir, repo_rel_dir, images)
    ctx.source_name = os.path.relpath(source, repo) if not os.path.relpath(source, repo).startswith("..") else source

    lproj = os.path.join(out_dir, BUNDLE_NAME, "Contents", "Resources", "en.lproj")
    bundle = os.path.join(out_dir, BUNDLE_NAME)
    if os.path.exists(bundle):
        shutil.rmtree(bundle)
    os.makedirs(lproj)

    pages = {}

    # The index: title, the text before the first section, then the topics.
    ctx.page = "index.html"
    body = []
    render_blocks(ctx, preamble, headings, body)
    topics = ['<a name="topics"></a>', "<h2 id=\"topics\">Topics</h2>", "<ul>"]
    for s in sections:
        topics.append('<li><a href="%s.html">%s</a></li>' % (s["slug"], inline(ctx, s["heading"][2])))
    topics.append("</ul>")
    pages["index.html"] = page_html(
        title if title != BOOK_TITLE else BOOK_TITLE,
        first_sentence(preamble),
        "\n".join(body + topics),
        index=True,
    )

    for s in sections:
        fname = s["slug"] + ".html"
        ctx.page = fname
        body = ['<nav class="top"><a href="index.html">%s</a></nav>' % html.escape(title, quote=False)]
        render_blocks(ctx, s["blocks"], headings, body)
        pages[fname] = page_html(
            "%s - %s" % (plain_text(s["heading"][2]), BOOK_TITLE),
            first_sentence(s["blocks"]),
            "\n".join(body),
        )

    for fname, content in pages.items():
        with open(os.path.join(lproj, fname), "w", encoding="utf-8") as f:
            f.write(content)
    with open(os.path.join(lproj, "style.css"), "w", encoding="utf-8") as f:
        f.write(CSS)
    for rel_image in sorted(images):
        dest = os.path.join(lproj, rel_image)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(os.path.join(source_dir, rel_image), dest)

    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleIdentifier": "com.freedenizen.onboardstudio.help",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": BOOK_TITLE,
        "CFBundlePackageType": "BNDL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "CFBundleSignature": "hbwr",
        "HPDBookAccessPath": "index.html",
        "HPDBookIndexPath": "search.helpindex",
        "HPDBookCSIndexPath": "search.cshelpindex",
        "HPDBookTitle": BOOK_TITLE,
        "HPDBookType": "3",
    }
    with open(os.path.join(bundle, "Contents", "Info.plist"), "wb") as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_XML)

    if shutil.which("hiutil"):
        for mode, name in (("lsm", "search.helpindex"), ("corespotlight", "search.cshelpindex")):
            cmd = ["hiutil", "-I", mode, "-Caf", os.path.join(lproj, name), lproj]
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if result.returncode != 0:
                raise BuildError("hiutil failed (%s): %s" % (" ".join(cmd), result.stdout.strip()))
    else:
        print("make-help-book: hiutil not found; skipping the search indexes", file=sys.stderr)

    print("wrote %s (%d pages: the index and %d sections)" % (bundle, len(pages), len(sections)))


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description="Build the Onboard Studio Help Book from the user guide.")
    ap.add_argument("--out", required=True, help="directory to write OnboardStudio.help into")
    ap.add_argument("--version", default="1.0", help="bundle version (default 1.0)")
    ap.add_argument(
        "--source",
        default=os.path.join(repo, "docs", "user-guide.md"),
        help="Markdown file to convert (default docs/user-guide.md)",
    )
    args = ap.parse_args()
    try:
        build(args.source, args.out, args.version)
    except BuildError as e:
        print("make-help-book: error: %s" % e, file=sys.stderr)
        return 1
    except OSError as e:
        print("make-help-book: error: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
