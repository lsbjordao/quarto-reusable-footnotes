<p align="center">
  <img src="assets/logo.png" alt="reusable-footnotes logo" width="640">
</p>

# reusable-footnotes

Quarto extension for **page-local reusable footnotes**.

The main use case is printable scholarly writing—especially **Law**, but also History and other Humanities—where bibliographic references are placed in page footnotes. The same source may need to appear again on a later page, while repeated citations on the *same* page should not print the same long footnote twice.

The intended behavior is:

```text
page 1     A¹ ... A¹ ... B²
           ─────────────────
           ¹ Full reference A
           ² Full reference B

page 2     A³ ... A³ ... B⁴       # continuous numbering
           ─────────────────
           ³ Full reference A
           ⁴ Full reference B
```

or, with numbering restarted on every page:

```text
page 1     A¹ ... A¹ ... B²
page 2     A¹ ... A¹ ... B²
```

The source identity is reused; the physical footnote instance is page-local.

## Writing notes

Keep using normal Pandoc/Quarto footnotes:

```qmd
First occurrence.^[Flora e Funga do Brasil, 2026.]

Another occurrence.^[Flora e Funga do Brasil, 2026.]
```

For bibliographic footnotes, this repository also vendors a development version of Fred Guth's [`bibentry`](https://github.com/fredguth/bibentry), preserving its MIT license and authorship:

```qmd
Normal citation: [@silva2026]

Full CSL entry: [@silva2026]{.bibentry}

Full CSL entry in a footnote: ^[See [@silva2026]{.bibentry}]
```

`@silva2026` remains an ordinary Pandoc citation. `.bibentry` simply asks for the bibliography-layout representation of the same BibTeX entry.

## Configuration

A complete configuration for the **page-local numbering** mode used by the repository example is:

```yaml
bibliography: references.bib

filters:
  - bibentry
  - reusable-footnotes

reusable-footnotes:
  enabled: true
  backlinks: true
  scope: page
  numbering: page
  docx-scope: pagebreak

format:
  html:
    toc: true
  pdf:
    toc: true
    pdf-engine: lualatex
  docx:
    toc: false
    reference-doc: _extensions/reusable-footnotes/reference-page.docx
```

### Options

- `enabled`: enable or disable the filter.
- `backlinks`: add discreet return links for repeated footnote calls in HTML.
- `scope`: `page` (default) or `document` for legacy document-wide reuse in PDF/LaTeX.
- `numbering`: `page` or `continuous`.
- `docx-scope`: `pagebreak`, `section`, or `document`.
- `html-order`: ordered list of `.qmd` pages used when HTML website/book numbering should continue globally across separately rendered pages.

### Page-local reuse with continuous numbering

Use this when the same note should print once per page, but numbering should continue through the document:

```yaml
reusable-footnotes:
  enabled: true
  backlinks: true
  scope: page
  numbering: continuous
  docx-scope: pagebreak
```

Conceptually:

```text
page 1: 1, 2
page 2: 3, 4
page 3: 5, 6
```

Repeated occurrences on each page reuse that page's local canonical number.

For continuous DOCX numbering, omit `reference-page.docx` or use your own reference DOCX with continuous footnote numbering.

### Page-local reuse with numbering restarted on every page

Use:

```yaml
reusable-footnotes:
  enabled: true
  backlinks: true
  scope: page
  numbering: page
  docx-scope: pagebreak

format:
  docx:
    reference-doc: _extensions/reusable-footnotes/reference-page.docx
```

Conceptually:

```text
page 1: 1, 2
page 2: 1, 2
page 3: 1, 2
```

The supplied `reference-page.docx` configures Word's native footnote counter with `w:numRestart="eachPage"`.

### DOCX page boundaries

For deterministic page-local reuse in DOCX, insert explicit Quarto page breaks:

```qmd
Page one text.^[Same note.]

Again on page one.^[Same note.]

{{< pagebreak >}}

Page two text.^[Same note.]
```

with:

```yaml
reusable-footnotes:
  docx-scope: pagebreak
```

Pandoc's Lua-filter phase runs before Word performs final pagination, so automatic Word page breaks cannot be known at filter time. Explicit `{{< pagebreak >}}` boundaries give the extension deterministic page scopes while Word still handles final page layout normally.

## PDF / LaTeX

PDF is the most complete implementation of the page-local model.

With:

```yaml
reusable-footnotes:
  scope: page
  numbering: continuous
```

identical notes are printed only once on each **physical PDF page**, but may appear again on later pages. Numbering continues through the document.

With:

```yaml
reusable-footnotes:
  scope: page
  numbering: page
```

identical notes are still page-local, but the footnote counter restarts at `1` on every physical page.

The implementation uses LaTeX's `fixfoot` package for page-aware repeated notes and `perpage` when page-local numbering is requested. These packages exchange page information through the LaTeX auxiliary file, so normal multi-pass PDF compilation determines the real page after layout.

## DOCX

Word has two distinct issues: **numbering** and **detecting physical page boundaries**.

### Numbering

WordprocessingML supports native footnote numbering restart with:

```xml
<w:footnotePr>
  <w:numRestart w:val="eachPage"/>
</w:footnotePr>
```

The repository includes:

```text
_extensions/reusable-footnotes/reference-page.docx
```

Use it when `numbering: page` is desired:

```yaml
format:
  docx:
    reference-doc: _extensions/reusable-footnotes/reference-page.docx

reusable-footnotes:
  numbering: page
```

For continuous DOCX numbering, omit that `reference-doc` (or use your own continuous-numbering reference document) and set `numbering: continuous`.

### Page-local reuse

Pandoc's AST exists **before Word performs pagination**. Therefore a Lua filter cannot know a natural Word page break caused by later font metrics, printer settings, margins, or editing.

For deterministic DOCX page-local reuse, use Quarto's native pagebreak:

```qmd
Page one text.^[Same note.]

Again on page one.^[Same note.]

{{< pagebreak >}}

Page two text.^[Same note.]
```

with:

```yaml
reusable-footnotes:
  docx-scope: pagebreak
```

Within each explicit pagebreak-delimited page, repeated notes share the canonical note. After the pagebreak, the same content creates a new real footnote.

`docx-scope: section` retains the older H1-based behavior, and `docx-scope: document` provides document-wide reuse.

Automatic physical-page deduplication in a freely flowing DOCX would require a **post-layout Word/office-automation step**, because the final pages do not exist yet at Lua-filter time. `reusable-footnotes` deliberately remains a no-Python, static Quarto/Pandoc extension.

## HTML

HTML has no physical pages in a standalone scrolling document, so a single HTML file is treated as one logical page.

For a Quarto **website or HTML book**, each `.qmd` is rendered as its own HTML page. Reuse remains local to that rendered page, but numbering can follow either policy.

### HTML page-local numbering

Each page starts at `1`:

```yaml
reusable-footnotes:
  scope: page
  numbering: page
```

Live examples:

- [Website — page-local numbering](https://lsbjordao.github.io/quarto-reusable-footnotes/examples/website/)
- [Book — page-local numbering](https://lsbjordao.github.io/quarto-reusable-footnotes/examples/book/)

### HTML global numbering

The page still owns its own footnotes, but displayed numbers continue through the website/book. Because Quarto renders HTML pages independently, declare their deterministic order:

```yaml
reusable-footnotes:
  scope: page
  numbering: continuous
  html-order:
    - index.qmd
    - doctrine.qmd
    - constitution.qmd
```

The extension counts canonical footnotes in preceding source pages and applies the corresponding HTML numbering offset while keeping all anchors page-local.

Live examples:

- [Website — global numbering](https://lsbjordao.github.io/quarto-reusable-footnotes/examples/website-global/) → `1, 2` / `3, 4` / `5, 6`
- [Book — global numbering](https://lsbjordao.github.io/quarto-reusable-footnotes/examples/book-global/) → `1, 2` / `3, 4` / `5, 6`

Preview all four modes locally with:

```bash
quarto preview examples/website
quarto preview examples/website-global
quarto preview examples/book
quarto preview examples/book-global
```

## Integration with `bibentry`

The vendored `bibentry` development version adds:

- true inline replacement, preserving surrounding prose;
- recursive AST support, including `.bibentry` inside native footnotes;
- one citeproc pass over the complete document, preserving numeric CSL ordering;
- bibliography preservation through `nocite` rather than hidden CSS/Typst content;
- portable AST output for HTML, PDF/LaTeX, DOCX, and Typst.

The intention is to upstream those improvements to `fredguth/bibentry` rather than maintain a competing bibliography renderer here.

## Equality rule

Footnotes are matched using their normalized Pandoc AST. `SoftBreak` is treated as an ordinary space, and occurrence-specific citation note numbers are ignored. Formatting, links, citation identities, locators, and multiple paragraphs remain significant.

That means:

```qmd
^[See [@silva2026]{.bibentry}]
```

matches another identical occurrence, while:

```qmd
^[See [@silva2026]{.bibentry}, p. 185.]
```

is a distinct footnote from:

```qmd
^[See [@silva2026]{.bibentry}, p. 241.]
```

## Render

```bash
quarto render
```

The example `index.qmd` generates HTML, PDF, and DOCX in `_output/` and contains explicit multi-page examples demonstrating recurrence of the same bibliographic source on later pages.

To render the main project and all four HTML examples:

```bash
./scripts/render-all.sh
```

## Tests

```bash
./tests/run.sh
```

The tests cover `bibentry`, HTML reuse, page-aware LaTeX/PDF behavior, DOCX explicit-pagebreak scopes, and integration between `bibentry` and `reusable-footnotes`.

## License

`reusable-footnotes` is MIT licensed. The vendored `bibentry` code keeps Frederico Guth's original MIT license in `_extensions/bibentry/LICENSE`.
