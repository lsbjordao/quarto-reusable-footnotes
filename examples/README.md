# HTML examples

This directory contains four independent Quarto projects demonstrating page-local reusable footnotes in HTML.

There are two numbering policies:

- **page numbering**: each rendered HTML page starts again at `1`;
- **global numbering**: each rendered HTML page still owns its own reusable-footnote scope, but the visible numbers continue across the website or book.

## Website — page numbering

`examples/website/` contains three website pages. The same bibliographic sources appear in more than one page, while repeated calls within a single page reuse that page's canonical footnote. Each page starts numbering at `1`.

```bash
quarto preview examples/website
```

## Website — global numbering

`examples/website-global/` uses the same page-local reuse model, but numbering continues across pages (`1, 2` → `3, 4` → `5, 6`).

```bash
quarto preview examples/website-global
```

The project declares the page order explicitly:

```yaml
reusable-footnotes:
  scope: page
  numbering: continuous
  html-order:
    - index.qmd
    - doctrine.qmd
    - constitution.qmd
```

## Book — page numbering

`examples/book/` contains three HTML book chapters. Each chapter is rendered as its own HTML page and therefore starts a new reusable-footnote scope and restarts numbering at `1`.

```bash
quarto preview examples/book
```

## Book — global numbering

`examples/book-global/` keeps the reusable-footnote scope local to each chapter page while continuing the visible numbers across chapters.

```bash
quarto preview examples/book-global
```

It also uses `html-order` to define the deterministic chapter sequence used to calculate the numbering offset.

All four examples reuse the root `references.bib` and the development filters in `_extensions/`.
