#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures"
BIBENTRY="$ROOT/_extensions/bibentry/bibentry.lua"
REUSABLE="$ROOT/_extensions/reusable-footnotes/reusable-footnotes.lua"
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
# bibentry alone
# -----------------------------------------------------------------------------
cd "$FIXTURES"

"${PANDOC[@]}" bibentry-input.md --lua-filter="$BIBENTRY" --citeproc -t plain -o "$TMP/bibentry.txt"
"${PANDOC[@]}" bibentry-input.md --lua-filter="$BIBENTRY" --citeproc -t native -o "$TMP/bibentry.native"
"${PANDOC[@]}" bibentry-input.md --lua-filter="$BIBENTRY" --citeproc -s -o "$TMP/bibentry.html"
"${PANDOC[@]}" bibentry-input.md --lua-filter="$BIBENTRY" --citeproc -s -o "$TMP/bibentry.docx"
"${PANDOC[@]}" bibentry-input.md --lua-filter="$BIBENTRY" --citeproc -t latex -o "$TMP/bibentry.tex"

grep -Fq 'Normal citation: INLINE[' "$TMP/bibentry.txt"
grep -Fq 'Standalone: FULL[' "$TMP/bibentry.txt"
grep -Fq 'Inline context: BEFORE FULL[' "$TMP/bibentry.txt"
grep -Fq 'NOTE FULL[' "$TMP/bibentry.txt"
grep -Fq '( "ref-alpha2024" , [ "csl-entry" ]' "$TMP/bibentry.native"

if grep -Fq 'left:-10000px' "$TMP/bibentry.html"; then
  echo "ERROR: legacy hidden-citation CSS found in bibentry HTML output." >&2
  exit 1
fi

unzip -p "$TMP/bibentry.docx" word/footnotes.xml | grep -Fq 'A book used only through bibentry'
grep -Fq '\footnote{' "$TMP/bibentry.tex"
grep -Fq 'A book used only through bibentry' "$TMP/bibentry.tex"

echo "OK bibentry: full CSL entries work inline and inside native footnotes."

# -----------------------------------------------------------------------------
# reusable-footnotes alone
# -----------------------------------------------------------------------------
cat > "$TMP/reusable.md" <<'EOF'
# Section A

First.^[Same note.]

Again.^[Same note.]

Different.^[Another note.]

# Section B

First here.^[Same note.]

Again here.^[Same note.]
EOF

cd "$ROOT"
"${PANDOC[@]}" "$TMP/reusable.md" -f markdown --lua-filter="$REUSABLE" -s -o "$TMP/reusable.html"
"${PANDOC[@]}" "$TMP/reusable.md" -f markdown --lua-filter="$REUSABLE" -t latex -o "$TMP/reusable.tex"
"${PANDOC[@]}" "$TMP/reusable.md" -f markdown --lua-filter="$REUSABLE" -o "$TMP/reusable.docx"

assert_eq 3 "$(count_matches 'class="footnote-ref reusable-footnote-ref"' "$TMP/reusable.html")" "HTML reused markers"
assert_eq 2 "$(count_matches '<li id="fn[0-9]+"' "$TMP/reusable.html")" "HTML canonical notes"
assert_eq 1 "$(count_matches '\\label\{rfn-note-[0-9]+\}' "$TMP/reusable.tex")" "LaTeX reusable labels"
assert_eq 3 "$(count_matches '\\hyperref\[rfn-note-[0-9]+\]' "$TMP/reusable.tex")" "LaTeX reused hyperlinks"

unzip -p "$TMP/reusable.docx" word/document.xml > "$TMP/reusable-document.xml"
unzip -p "$TMP/reusable.docx" word/footnotes.xml > "$TMP/reusable-footnotes.xml"
assert_eq 3 "$(count_matches '<w:footnoteReference' "$TMP/reusable-document.xml")" "DOCX native references"
assert_eq 2 "$(count_matches '<w:hyperlink w:anchor="rfn_note_s[0-9]+_n[0-9]+"' "$TMP/reusable-document.xml")" "DOCX reused hyperlinks"
assert_eq 2 "$(count_matches 'w:name="rfn_note_s[0-9]+_n[0-9]+"' "$TMP/reusable-footnotes.xml")" "DOCX canonical bookmarks"

echo "OK reusable-footnotes: recurrence works in HTML, LaTeX, and section-scoped DOCX."

# -----------------------------------------------------------------------------
# integration: bibentry first, reusable-footnotes second
# -----------------------------------------------------------------------------
cat > "$TMP/integration.md" <<EOF
---
bibliography: $FIXTURES/bibentry-refs.bib
csl: $FIXTURES/bibentry-test.csl
---

# Legal-style footnotes

First proposition.^[See [@alpha2024]{.bibentry}]

Second proposition, same source and same note text.^[See [@alpha2024]{.bibentry}]
EOF

"${PANDOC[@]}" "$TMP/integration.md" -f markdown \
  --lua-filter="$BIBENTRY" \
  --lua-filter="$REUSABLE" \
  --citeproc -s -o "$TMP/integration.html"

"${PANDOC[@]}" "$TMP/integration.md" -f markdown \
  --lua-filter="$BIBENTRY" \
  --lua-filter="$REUSABLE" \
  --citeproc -o "$TMP/integration.docx"

assert_eq 1 "$(count_matches 'class="footnote-ref reusable-footnote-ref"' "$TMP/integration.html")" "integrated HTML reused marker"
assert_eq 1 "$(count_matches '<li id="fn[0-9]+"' "$TMP/integration.html")" "integrated HTML canonical note"
grep -Fq 'FULL[' "$TMP/integration.html"

unzip -p "$TMP/integration.docx" word/document.xml > "$TMP/integration-document.xml"
unzip -p "$TMP/integration.docx" word/footnotes.xml > "$TMP/integration-footnotes.xml"
assert_eq 1 "$(count_matches '<w:footnoteReference' "$TMP/integration-document.xml")" "integrated DOCX native note"
assert_eq 1 "$(count_matches '<w:hyperlink w:anchor="rfn_note_s[0-9]+_n[0-9]+"' "$TMP/integration-document.xml")" "integrated DOCX reused marker"
grep -Fq 'A book used only through bibentry' "$TMP/integration-footnotes.xml"

echo "OK integration: bibentry expands the CSL entry before reusable-footnotes deduplicates it."

if find "$ROOT" -type f -name '*.py' -print -quit | grep -q .; then
  echo "ERROR: repository still contains a Python file." >&2
  exit 1
fi

echo "All tests passed."
