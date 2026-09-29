#!/usr/bin/env python3
"""
Dependency-free Markdown -> styled HTML converter, tuned for the thesis report.

Handles exactly the Markdown features used in THESIS_REPORT.md:
  - ATX headings (# .. ######), with a page break before each chapter (h1)
  - GitHub-style tables with column alignment
  - Ordered / unordered lists
  - Blockquotes
  - Horizontal rules (---)
  - Inline: **bold**, *italic*, `code`
It deliberately leaves underscores literal (the doc uses * for emphasis), so
identifiers like S_AXI_HP0 and the title-page blanks survive untouched.

Usage:  python3 md_to_html.py input.md output.html "Document Title"
"""
import sys, re, html

def inline(text):
    """Inline formatting. Code spans are protected from emphasis & escaped."""
    parts = re.split(r'(`[^`]+`)', text)
    out = []
    for p in parts:
        if len(p) >= 2 and p.startswith('`') and p.endswith('`'):
            out.append('<code>' + html.escape(p[1:-1]) + '</code>')
        else:
            s = html.escape(p)
            s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
            s = re.sub(r'\*([^*]+)\*', r'<em>\1</em>', s)
            out.append(s)
    return ''.join(out)

def is_table_sep(line):
    return bool(re.match(r'^\s*\|?[\s:|-]+\|[\s:|-]*$', line)) and '-' in line

def split_row(line):
    line = line.strip()
    if line.startswith('|'):
        line = line[1:]
    if line.endswith('|'):
        line = line[:-1]
    return [c.strip() for c in line.split('|')]

def aligns_from_sep(sep_cells):
    al = []
    for c in sep_cells:
        c = c.strip()
        left = c.startswith(':')
        right = c.endswith(':')
        if left and right:
            al.append('center')
        elif right:
            al.append('right')
        else:
            al.append('left')
    return al

def convert(md):
    lines = md.split('\n')
    out = []
    i = 0
    n = len(lines)
    first_h1_seen = False

    while i < n:
        line = lines[i]

        # blank
        if line.strip() == '':
            i += 1
            continue

        # horizontal rule
        if re.match(r'^\s*---+\s*$', line) or re.match(r'^\s*\*\*\*\s*$', line):
            out.append('<hr/>')
            i += 1
            continue

        # heading
        m = re.match(r'^(#{1,6})\s+(.*)$', line)
        if m:
            level = len(m.group(1))
            txt = inline(m.group(2).strip())
            cls = ''
            if level == 1:
                if first_h1_seen:
                    cls = ' class="chapter"'
                else:
                    cls = ' class="doctitle"'
                    first_h1_seen = True
            out.append(f'<h{level}{cls}>{txt}</h{level}>')
            i += 1
            continue

        # table: header line followed by separator line
        if '|' in line and i + 1 < n and is_table_sep(lines[i + 1]):
            header = split_row(line)
            aligns = aligns_from_sep(split_row(lines[i + 1]))
            i += 2
            body = []
            while i < n and '|' in lines[i] and lines[i].strip() != '':
                body.append(split_row(lines[i]))
                i += 1
            out.append('<table>')
            out.append('<thead><tr>')
            for j, h in enumerate(header):
                a = aligns[j] if j < len(aligns) else 'left'
                out.append(f'<th style="text-align:{a}">{inline(h)}</th>')
            out.append('</tr></thead><tbody>')
            for row in body:
                out.append('<tr>')
                for j, c in enumerate(row):
                    a = aligns[j] if j < len(aligns) else 'left'
                    out.append(f'<td style="text-align:{a}">{inline(c)}</td>')
                out.append('</tr>')
            out.append('</tbody></table>')
            continue

        # blockquote
        if line.lstrip().startswith('>'):
            buf = []
            while i < n and lines[i].lstrip().startswith('>'):
                buf.append(re.sub(r'^\s*>\s?', '', lines[i]))
                i += 1
            out.append('<blockquote>' + inline(' '.join(buf)) + '</blockquote>')
            continue

        # unordered list
        if re.match(r'^\s*[-*]\s+', line):
            out.append('<ul>')
            while i < n and re.match(r'^\s*[-*]\s+', lines[i]):
                item = re.sub(r'^\s*[-*]\s+', '', lines[i])
                out.append('<li>' + inline(item) + '</li>')
                i += 1
            out.append('</ul>')
            continue

        # ordered list
        if re.match(r'^\s*\d+\.\s+', line):
            out.append('<ol>')
            while i < n and re.match(r'^\s*\d+\.\s+', lines[i]):
                item = re.sub(r'^\s*\d+\.\s+', '', lines[i])
                out.append('<li>' + inline(item) + '</li>')
                i += 1
            out.append('</ol>')
            continue

        # paragraph: gather consecutive plain lines
        buf = []
        while i < n and lines[i].strip() != '':
            l = lines[i]
            if (re.match(r'^(#{1,6})\s', l) or re.match(r'^\s*---+\s*$', l)
                    or ('|' in l and i + 1 < n and is_table_sep(lines[i + 1]))
                    or l.lstrip().startswith('>')
                    or re.match(r'^\s*[-*]\s+', l)
                    or re.match(r'^\s*\d+\.\s+', l)):
                break
            buf.append(l)
            i += 1
        if buf:
            out.append('<p>' + inline(' '.join(buf)) + '</p>')

    return '\n'.join(out)

CSS = """
@page { size: A4; margin: 2.5cm 2.2cm; }
body { font-family: 'Liberation Serif','Times New Roman',serif; font-size: 11.5pt;
       line-height: 1.45; color: #111; }
h1.doctitle { text-align: center; font-size: 19pt; line-height: 1.3; margin: 1.2em 0; }
h1.chapter { page-break-before: always; font-size: 16pt; border-bottom: 2px solid #333;
             padding-bottom: 4px; margin-top: 0.4em; }
h1 { font-size: 16pt; }
h2 { font-size: 13.5pt; margin-top: 1.1em; }
h3 { font-size: 12pt; margin-top: 0.9em; }
p  { text-align: justify; margin: 0.5em 0; }
table { border-collapse: collapse; width: 100%; margin: 0.8em 0; font-size: 10.5pt; }
th, td { border: 1px solid #888; padding: 4px 7px; vertical-align: top; }
th { background: #e8e8e8; }
tbody tr:nth-child(even) { background: #f6f6f6; }
blockquote { border-left: 3px solid #999; margin: 0.6em 0; padding: 0.2em 0 0.2em 1em;
             color: #333; font-style: italic; }
code { font-family: 'Liberation Mono','Courier New',monospace; font-size: 9.8pt;
       background: #f0f0f0; padding: 0 2px; }
hr { border: none; border-top: 1px solid #ccc; margin: 1em 0; }
ul, ol { margin: 0.4em 0 0.4em 1.2em; }
li { margin: 0.15em 0; }
"""

def main():
    inp, outp = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else 'Document'
    with open(inp, encoding='utf-8') as f:
        md = f.read()
    bodyhtml = convert(md)
    doc = (f'<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8"/>'
           f'<title>{html.escape(title)}</title><style>{CSS}</style></head>'
           f'<body>\n{bodyhtml}\n</body></html>')
    with open(outp, 'w', encoding='utf-8') as f:
        f.write(doc)
    print(f'wrote {outp} ({len(doc)} bytes)')

if __name__ == '__main__':
    main()
