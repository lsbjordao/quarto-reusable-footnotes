#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v unzip >/dev/null 2>&1 || {
  echo "ERRO: unzip é necessário para inspecionar o DOCX." >&2
  exit 1
}

if command -v pandoc >/dev/null 2>&1; then
  PANDOC=(pandoc)
elif command -v quarto >/dev/null 2>&1; then
  PANDOC=(quarto pandoc)
else
  echo "ERRO: Pandoc ou Quarto é necessário para os testes." >&2
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
    echo "ERRO: $message — esperado $expected, encontrado $actual." >&2
    exit 1
  fi
}

./scripts/render-all.sh

HTML="_output/index.html"
DOCX="_output/index.docx"
[[ -f "$HTML" ]] || { echo "ERRO: $HTML não foi gerado." >&2; exit 1; }
[[ -f "$DOCX" ]] || { echo "ERRO: $DOCX não foi gerado." >&2; exit 1; }

html_reused="$(count_matches 'class="footnote-ref reusable-footnote-ref"' "$HTML")"
html_notes="$(count_matches '<li id="fn[0-9]+"' "$HTML")"
html_backlink_groups="$(count_matches 'class="reusable-footnote-backlinks"' "$HTML")"

assert_eq 9 "$html_reused" "recorrências HTML reutilizadas"
assert_eq 9 "$html_notes" "notas HTML reais"
assert_eq 7 "$html_backlink_groups" "grupos HTML de backlinks"
echo "OK HTML: 9 notas reais, 9 recorrências e backlinks discretos."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# PDF/LaTeX regression: every reused mark must be a hyperlink to a label placed
# in the canonical footnote, not a bare \footnotemark.
"${PANDOC[@]}" index.qmd \
  -f markdown \
  --lua-filter=_extensions/reusable-footnotes/reusable-footnotes.lua \
  -t latex \
  -o "$TMP/index.tex"

pdf_labels="$(count_matches '\\label\{rfn-note-[0-9]+\}' "$TMP/index.tex")"
pdf_reuse_links="$(count_matches '\\hyperref\[rfn-note-[0-9]+\]' "$TMP/index.tex")"
pdf_bare_reuses="$(count_matches '\\footnotemark\[[0-9]+\]' "$TMP/index.tex")"

assert_eq 7 "$pdf_labels" "labels LaTeX das notas reutilizadas"
assert_eq 9 "$pdf_reuse_links" "links LaTeX das recorrências"
assert_eq 0 "$pdf_bare_reuses" "marcadores PDF reutilizados sem link"
echo "OK PDF: as 9 recorrências são hyperlinks para as 7 notas canônicas."

unzip -p "$DOCX" word/document.xml > "$TMP/document.xml"
unzip -p "$DOCX" word/footnotes.xml > "$TMP/footnotes.xml"

docx_native_refs="$(count_matches '<w:footnoteReference' "$TMP/document.xml")"
docx_reuse_links="$(count_matches '<w:hyperlink w:anchor="rfn_note_s[0-9]+_n[0-9]+"' "$TMP/document.xml")"
docx_bookmarks="$(count_matches 'w:name="rfn_note_s[0-9]+_n[0-9]+"' "$TMP/footnotes.xml")"
docx_real_notes="$(count_matches '<w:footnote w:id="' "$TMP/footnotes.xml")"
docx_noteref_fields="$(count_matches '<w:fldSimple[^>]*w:instr=" NOTEREF' "$TMP/document.xml")"

assert_eq 9 "$docx_native_refs" "referências DOCX nativas"
assert_eq 9 "$docx_reuse_links" "links DOCX reutilizados"
assert_eq 7 "$docx_bookmarks" "bookmarks nas notas DOCX canônicas"
assert_eq 9 "$docx_real_notes" "notas DOCX reais"
assert_eq 0 "$docx_noteref_fields" "campos DOCX NOTEREF legados"

# Regression for section-local numbering. Quarto/Pandoc DOCX restarts native
# footnotes at each top-level section. In the example, eight reused markers must
# therefore display 1 and only the second distinct note in section 3 displays 2.
sed 's#<w:hyperlink#\n<w:hyperlink#g; s#</w:hyperlink>#</w:hyperlink>\n#g' \
  "$TMP/document.xml" > "$TMP/document-lines.xml"
grep 'w:anchor="rfn_note_s' "$TMP/document-lines.xml" > "$TMP/reusable-links.xml"

docx_reused_ones="$(grep -c '<w:t>1</w:t>' "$TMP/reusable-links.xml" || true)"
docx_reused_twos="$(grep -c '<w:t>2</w:t>' "$TMP/reusable-links.xml" || true)"
docx_reused_high="$(grep -Ec '<w:t>[3-9][0-9]*</w:t>' "$TMP/reusable-links.xml" || true)"

assert_eq 8 "$docx_reused_ones" "recorrências DOCX com número local 1"
assert_eq 1 "$docx_reused_twos" "recorrência DOCX com número local 2"
assert_eq 0 "$docx_reused_high" "recorrências DOCX com números globais incorretos"

# A repeated note in a new H1 section must become a new native footnote there,
# because the native numbering restarts in that section.
cat > "$TMP/cross-section.md" <<'EOF'
# A

Primeira.^[Mesma nota.]

Repetida na seção A.^[Mesma nota.]

# B

Primeira na seção B.^[Mesma nota.]

Repetida na seção B.^[Mesma nota.]
EOF

"${PANDOC[@]}" "$TMP/cross-section.md" \
  -f markdown \
  --lua-filter=_extensions/reusable-footnotes/reusable-footnotes.lua \
  -o "$TMP/cross-section.docx"
unzip -p "$TMP/cross-section.docx" word/document.xml > "$TMP/cross-document.xml"
unzip -p "$TMP/cross-section.docx" word/footnotes.xml > "$TMP/cross-footnotes.xml"
assert_eq 2 "$(count_matches '<w:footnoteReference' "$TMP/cross-document.xml")" "notas nativas em duas seções"
assert_eq 2 "$(count_matches '<w:hyperlink w:anchor="rfn_note_s[0-9]+_n000001"' "$TMP/cross-document.xml")" "recorrências locais em duas seções"
assert_eq 2 "$(count_matches 'w:name="rfn_note_s[0-9]+_n000001"' "$TMP/cross-footnotes.xml")" "bookmarks locais em duas seções"

if grep -q '__REUSABLE_FOOTNOTE_GROUP_' "$TMP/footnotes.xml"; then
  echo "ERRO: marcador legado de pós-processamento encontrado no DOCX." >&2
  exit 1
fi

if find . -type f -name '*.py' -print -quit | grep -q .; then
  echo "ERRO: o repositório ainda contém arquivo Python." >&2
  exit 1
fi

echo "OK DOCX: numeração reutilizada acompanha o escopo da seção; nenhum número global indevido."
echo "Todos os testes passaram."
