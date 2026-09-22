# HTML examples

This directory contains two independent Quarto projects demonstrating page-local reusable footnotes in HTML.

## Website

`examples/website/` contains three website pages. The same bibliographic sources appear in more than one page, while repeated calls within a single page reuse that page's canonical footnote.

```bash
quarto preview examples/website
```

## Book

`examples/book/` contains three HTML book chapters. Each chapter is rendered as its own HTML page and therefore starts a new reusable-footnote scope.

```bash
quarto preview examples/book
```

Both examples reuse the root `references.bib` and the development filters in `_extensions/`.
