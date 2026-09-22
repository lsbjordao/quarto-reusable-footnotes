#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p _output

if command -v quarto >/dev/null 2>&1; then
  quarto render
  quarto render examples/website
  quarto render examples/website-global
  quarto render examples/book
  quarto render examples/book-global
  echo "Main outputs and all four HTML examples rendered." >&2
  exit 0
fi

echo "quarto não encontrado; usando fallback Pandoc apenas para os três formatos principais." >&2
BIBENTRY="_extensions/bibentry/bibentry.lua"
REUSABLE="_extensions/reusable-footnotes/reusable-footnotes.lua"
CSS="_extensions/reusable-footnotes/reusable-footnotes.css"

pandoc index.qmd \
  -f markdown \
  --standalone \
  --embed-resources \
  --toc \
  --lua-filter="$BIBENTRY" \
  --lua-filter="$REUSABLE" \
  --citeproc \
  --css="$CSS" \
  --metadata title="reusable-footnotes" \
  -o _output/index.html

pandoc index.qmd \
  -f markdown \
  --standalone \
  --toc \
  --lua-filter="$BIBENTRY" \
  --lua-filter="$REUSABLE" \
  --citeproc \
  --pdf-engine=lualatex \
  -V geometry:margin=25mm \
  -V mainfont="DejaVu Serif" \
  -V monofont="DejaVu Sans Mono" \
  -o _output/index.pdf

pandoc index.qmd \
  -f markdown \
  --standalone \
  --lua-filter="$BIBENTRY" \
  --lua-filter="$REUSABLE" \
  --citeproc \
  -o _output/index.docx

echo "Saídas principais geradas em $ROOT/_output; exemplos HTML exigem Quarto CLI." >&2
