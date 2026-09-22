#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v unzip >/dev/null 2>&1 || {
  echo "ERRO: unzip é necessário para inspecionar o DOCX." >&2
  exit 1
}

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
unzip -p "$DOCX" word/document.xml > "$TMP/document.xml"
unzip -p "$DOCX" word/footnotes.xml > "$TMP/footnotes.xml"

docx_native_refs="$(count_matches '<w:footnoteReference' "$TMP/document.xml")"
docx_noterefs="$(count_matches 'NOTEREF rfn_ref_[0-9]+' "$TMP/document.xml")"
docx_bookmarks="$(count_matches 'w:name="rfn_ref_[0-9]+"' "$TMP/document.xml")"
docx_real_notes="$(count_matches '<w:footnote w:id="' "$TMP/footnotes.xml")"

assert_eq 9 "$docx_native_refs" "referências DOCX nativas"
assert_eq 9 "$docx_noterefs" "campos DOCX NOTEREF"
assert_eq 7 "$docx_bookmarks" "bookmarks DOCX canônicos"
assert_eq 9 "$docx_real_notes" "notas DOCX reais"

if grep -q '__REUSABLE_FOOTNOTE_GROUP_' "$TMP/footnotes.xml"; then
  echo "ERRO: marcador legado de pós-processamento encontrado no DOCX." >&2
  exit 1
fi

if find . -type f -name '*.py' -print -quit | grep -q .; then
  echo "ERRO: o repositório ainda contém arquivo Python." >&2
  exit 1
fi

echo "OK DOCX: 9 notas reais + 9 NOTEREF para as recorrências; nenhum Python."
echo "Todos os testes passaram."
