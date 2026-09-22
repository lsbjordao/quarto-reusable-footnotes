#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures"
BIBENTRY="$ROOT/_extensions/bibentry/bibentry.lua"
REUSABLE="$ROOT/_extensions/reusable-footnotes/reusable-footnotes.lua"
REFERENCE_PAGE="$ROOT/_extensions/reusable-footnotes/reference-page.docx"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v unzip >/dev/null 2>&1 || {
  echo "ERROR: unzip is required." >&2
  exit 1
}

if command -v pandoc >/dev/null 2>&1; then
  PANDOC=(pandoc)
elif command -v quarto >/dev/null 2>&1; then
  PANDOC=(quarto pandoc)
else
  echo "ERROR: Pandoc or Quarto is required." >&2
  exit 1
fi

count_matches() {
  local pattern="$1"
  local file="$2"
  local matches
  matches="$(grep -oE "$pattern" "$file" 2>/dev/null || true)"
  if [[ -z "$matches" ]]; then
    printf '0\n'
  else
    printf '%s\n' "$matches" | wc -l | tr -d ' '
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $message — expected $expected, found $actual." >&2
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# bibentry regression: inline + nested native footnote
# -----------------------------------------------------------------------------
cd "$FIXTURES"
"${PANDOC[@]}" bibentry-input.md --lua-filter="$BIBENTRY" --citeproc -t plain -o "$TMP/bibentry.txt"
"${PANDOC[@]}" bibentry-input.md --lua-filter="$BIBENTRY" --citeproc -s -o "$TMP/bibentry.docx"

grep -Fq 'Normal citation: INLINE[' "$TMP/bibentry.txt"
grep -Fq 'Standalone: FULL[' "$TMP/bibentry.txt"
grep -Fq 'Inline context: BEFORE FULL[' "$TMP/bibentry.txt"
grep -Fq 'NOTE FULL[' "$TMP/bibentry.txt"
unzip -p "$TMP/bibentry.docx" word/footnotes.xml | grep -Fq 'A book used only through bibentry'

echo "OK bibentry: full CSL entries still work inline and inside footnotes."

# -----------------------------------------------------------------------------
# HTML: one scrolling file = one logical page
# -----------------------------------------------------------------------------
cat > "$TMP/html.md" <<'EOF'
First.^[Same note.]

Again.^[Same note.]

Different.^[Another note.]
EOF

"${PANDOC[@]}" "$TMP/html.md" --lua-filter="$REUSABLE" -s -o "$TMP/html.html"
assert_eq 1 "$(count_matches 'class="footnote-ref reusable-footnote-ref"' "$TMP/html.html")" "HTML reused marker"
assert_eq 2 "$(count_matches '<li id="fn[0-9]+"' "$TMP/html.html")" "HTML canonical notes"

echo "OK HTML: current HTML file behaves as one logical page."

# -----------------------------------------------------------------------------
# LaTeX/PDF page scope: fixfoot handles the final physical page after layout
# -----------------------------------------------------------------------------
cat > "$TMP/pdf-page.md" <<'EOF'
---
reusable-footnotes:
  scope: page
  numbering: page
---

First.^[Same note.]

Again on the same page.^[Same note.]

```{=latex}
\newpage
```

Same source on another page.^[Same note.]

Again on page two.^[Same note.]
EOF

"${PANDOC[@]}" "$TMP/pdf-page.md" --lua-filter="$REUSABLE" -s -t latex -o "$TMP/pdf-page.tex"
grep -Fq '\usepackage{fixfoot}' "$TMP/pdf-page.tex"
grep -Fq '\usepackage{perpage}' "$TMP/pdf-page.tex"
grep -Fq '\MakePerPage{footnote}' "$TMP/pdf-page.tex"
assert_eq 1 "$(count_matches '\\DeclareFixedFootnote\{\\rfnnote[a-z]+\}' "$TMP/pdf-page.tex")" "one fixed-footnote definition for one unique note"
assert_eq 4 "$(count_matches '\\rfnnotea([[:space:][:punct:]]|$)' "$TMP/pdf-page.tex")" "four calls to the same page-aware fixed footnote"

if command -v lualatex >/dev/null 2>&1 && kpsewhich fixfoot.sty >/dev/null 2>&1 && kpsewhich perpage.sty >/dev/null 2>&1; then
  "${PANDOC[@]}" "$TMP/pdf-page.md" --lua-filter="$REUSABLE" -s --pdf-engine=lualatex -o "$TMP/pdf-page.pdf"
  test -s "$TMP/pdf-page.pdf"
  echo "OK PDF: page-aware example compiled with fixfoot + perpage."
else
  echo "OK LaTeX: page-aware fixfoot/perpage code generated (PDF compile skipped)."
fi

# Continuous numbering must keep page-aware reuse but omit per-page reset.
sed 's/numbering: page/numbering: continuous/' "$TMP/pdf-page.md" > "$TMP/pdf-continuous.md"
"${PANDOC[@]}" "$TMP/pdf-continuous.md" --lua-filter="$REUSABLE" -s -t latex -o "$TMP/pdf-continuous.tex"
grep -Fq '\usepackage{fixfoot}' "$TMP/pdf-continuous.tex"
if grep -Fq '\MakePerPage{footnote}' "$TMP/pdf-continuous.tex"; then
  echo "ERROR: continuous PDF numbering unexpectedly enabled per-page reset." >&2
  exit 1
fi

echo "OK PDF numbering: page and continuous modes are distinct."

# -----------------------------------------------------------------------------
# DOCX: explicit Quarto-style OpenXML pagebreaks define deterministic page scopes
# -----------------------------------------------------------------------------
cat > "$TMP/docx-page.md" <<'EOF'
---
reusable-footnotes:
  scope: page
  numbering: page
  docx-scope: pagebreak
---

Page one.^[Same note.]

Again page one.^[Same note.]

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

Page two.^[Same note.]

Again page two.^[Same note.]
EOF

"${PANDOC[@]}" "$TMP/docx-page.md" \
  --lua-filter="$REUSABLE" \
  --reference-doc="$REFERENCE_PAGE" \
  -o "$TMP/docx-page.docx"

unzip -p "$TMP/docx-page.docx" word/document.xml > "$TMP/docx-document.xml"
unzip -p "$TMP/docx-page.docx" word/footnotes.xml > "$TMP/docx-footnotes.xml"
unzip -p "$TMP/docx-page.docx" word/settings.xml > "$TMP/docx-settings.xml"

assert_eq 2 "$(count_matches '<w:footnoteReference' "$TMP/docx-document.xml")" "one native note per explicit page"
assert_eq 2 "$(count_matches '<w:hyperlink w:anchor="rfn_note_s[0-9]+_n[0-9]+"' "$TMP/docx-document.xml")" "one reused marker per explicit page"
assert_eq 2 "$(grep -oF 'Same note.' "$TMP/docx-footnotes.xml" | wc -l | tr -d ' ')" "same note text repeated once per explicit page"
grep -Fq 'w:numRestart w:val="eachPage"' "$TMP/docx-settings.xml"

# With page numbering each page-local canonical note is displayed as 1.
grep -Fq 'rfn_note_s000000_n000001' "$TMP/docx-document.xml"
grep -Fq 'rfn_note_s000001_n000001' "$TMP/docx-document.xml"

echo "OK DOCX: explicit pagebreak scopes reuse locally and restart numbering per page."

# Continuous DOCX numbering should carry the next canonical number to page two.
sed 's/numbering: page/numbering: continuous/' "$TMP/docx-page.md" > "$TMP/docx-continuous.md"
"${PANDOC[@]}" "$TMP/docx-continuous.md" --lua-filter="$REUSABLE" -o "$TMP/docx-continuous.docx"
unzip -p "$TMP/docx-continuous.docx" word/document.xml > "$TMP/docx-continuous.xml"
grep -Fq 'rfn_note_s000000_n000001' "$TMP/docx-continuous.xml"
grep -Fq 'rfn_note_s000001_n000002' "$TMP/docx-continuous.xml"

echo "OK DOCX numbering: page and continuous modes are distinct."

# -----------------------------------------------------------------------------
# Integration: bibentry expands first, reusable-footnotes scopes the result
# -----------------------------------------------------------------------------
cat > "$TMP/integration.md" <<EOF
---
bibliography: $FIXTURES/bibentry-refs.bib
csl: $FIXTURES/bibentry-test.csl
reusable-footnotes:
  scope: page
  numbering: continuous
  docx-scope: pagebreak
---

First proposition.^[See [@alpha2024]{.bibentry}]

Same page, same source.^[See [@alpha2024]{.bibentry}]

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

Next page, same source.^[See [@alpha2024]{.bibentry}]
EOF

"${PANDOC[@]}" "$TMP/integration.md" \
  --lua-filter="$BIBENTRY" \
  --lua-filter="$REUSABLE" \
  --citeproc -o "$TMP/integration.docx"

unzip -p "$TMP/integration.docx" word/document.xml > "$TMP/integration-document.xml"
unzip -p "$TMP/integration.docx" word/footnotes.xml > "$TMP/integration-footnotes.xml"
assert_eq 2 "$(count_matches '<w:footnoteReference' "$TMP/integration-document.xml")" "integrated canonical notes across two explicit pages"
assert_eq 1 "$(count_matches '<w:hyperlink w:anchor="rfn_note_s[0-9]+_n[0-9]+"' "$TMP/integration-document.xml")" "integrated same-page reuse"
assert_eq 2 "$(grep -oF 'A book used only through bibentry' "$TMP/integration-footnotes.xml" | wc -l | tr -d ' ')" "full CSL entry appears once on each explicit page"

echo "OK integration: BibTeX/CSL entry is reusable within a page and repeated on a later page."

if find "$ROOT" -type f -name '*.py' -print -quit | grep -q .; then
  echo "ERROR: repository still contains a Python file." >&2
  exit 1
fi

echo "All tests passed."
