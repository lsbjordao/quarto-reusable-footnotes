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

count_fixed() {
  local literal="$1"
  local file="$2"
  local matches
  matches="$(grep -oF "$literal" "$file" 2>/dev/null || true)"
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
docx_reuse_links="$(count_matches '<w:hyperlink w:anchor="rfn_note_[0-9]+"' "$TMP/document.xml")"
docx_bookmarks="$(count_matches 'w:name="rfn_note_[0-9]+"' "$TMP/footnotes.xml")"
docx_real_notes="$(count_matches '<w:footnote w:id="' "$TMP/footnotes.xml")"
docx_noteref_fields="$(count_matches '<w:fldSimple[^>]*w:instr=" NOTEREF' "$TMP/document.xml")"

assert_eq 9 "$docx_native_refs" "referências DOCX nativas"
assert_eq 9 "$docx_reuse_links" "links DOCX reutilizados"
assert_eq 7 "$docx_bookmarks" "bookmarks nas notas DOCX canônicas"
assert_eq 9 "$docx_real_notes" "notas DOCX reais"
assert_eq 0 "$docx_noteref_fields" "campos DOCX NOTEREF legados"

# Regression for the reported numbering bug: the displayed number is literal
# and must agree with the canonical bookmark encoded in the same link.
assert_eq 2 "$(count_fixed '<w:hyperlink w:anchor="rfn_note_000001" w:history="1"><w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:t>1</w:t></w:r></w:hyperlink>' "$TMP/document.xml")" "recorrências DOCX da nota 1"
assert_eq 2 "$(count_fixed '<w:hyperlink w:anchor="rfn_note_000002" w:history="1"><w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:t>2</w:t></w:r></w:hyperlink>' "$TMP/document.xml")" "recorrências DOCX da nota 2"
for number in 3 4 5 6 9; do
  padded="$(printf '%06d' "$number")"
  literal="<w:hyperlink w:anchor=\"rfn_note_${padded}\" w:history=\"1\"><w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:t>${number}</w:t></w:r></w:hyperlink>"
  assert_eq 1 "$(count_fixed "$literal" "$TMP/document.xml")" "recorrência DOCX da nota $number"
done

if grep -q '__REUSABLE_FOOTNOTE_GROUP_' "$TMP/footnotes.xml"; then
  echo "ERRO: marcador legado de pós-processamento encontrado no DOCX." >&2
  exit 1
fi

if find . -type f -name '*.py' -print -quit | grep -q .; then
  echo "ERRO: o repositório ainda contém arquivo Python." >&2
  exit 1
fi

echo "OK DOCX: 9 notas reais + 9 links internos com números canônicos; nenhum campo NOTEREF e nenhum Python."
echo "Todos os testes passaram."
