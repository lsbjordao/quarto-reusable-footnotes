# reusable-footnotes

Extensão Quarto para **reutilizar notas de rodapé idênticas sem gerar novos números**.

A proposta é deliberadamente simples: continue escrevendo notas com a sintaxe normal do Pandoc/Quarto (`^[...]` ou `[^id]`). Se o conteúdo AST de duas notas for exatamente igual, apenas a primeira cria uma nota real; as demais remetem ao mesmo número.

A extensão é **100% Lua/Quarto**: não há pós-processamento em Python nem dependência externa para DOCX.

## Integração experimental com `bibentry`

O repositório também inclui, em `_extensions/bibentry/`, uma **versão de desenvolvimento derivada de [`fredguth/bibentry`](https://github.com/fredguth/bibentry)**, preservando a licença MIT e a autoria de Frederico Guth. Ela está aqui para testar a integração antes de propormos as mudanças upstream.

A API continua a mesma do projeto original:

```qmd
Normal citation: [@barroso2024]

Full CSL bibliography entry: [@barroso2024]{.bibentry}

Legal-style footnote: ^[See [@barroso2024]{.bibentry}]
```

A versão modificada acrescenta:

- uso verdadeiro inline, substituindo apenas o `Span.bibentry`;
- suporte recursivo, inclusive dentro de footnotes;
- uma única passagem de `citeproc` sobre o documento completo, preservando ordenação e estilos numéricos;
- preservação da entrada na bibliografia via `nocite`, sem hacks de conteúdo escondido;
- AST portátil para HTML, PDF/LaTeX, DOCX e Typst.

No exemplo deste repositório, os filtros são executados nesta ordem:

```yaml
bibliography: references.bib

filters:
  - bibentry
  - reusable-footnotes
```

Assim, `bibentry` primeiro transforma `[@key]{.bibentry}` na entrada longa definida pelo `csl:` ativo; depois `reusable-footnotes` pode reconhecer e reutilizar footnotes bibliograficamente idênticas.

## Exemplo básico de notas reutilizáveis

```markdown
Primeira ocorrência.^[Flora e Funga do Brasil, 2026.]

Segunda ocorrência.^[Flora e Funga do Brasil, 2026.]
```

Em vez de `1` e `2`, as duas chamadas mostram `1`, com uma única nota no rodapé. No HTML, três ocorrências produzem retornos discretos como:

```text
1. Flora e Funga do Brasil, 2026. ↩︎ ↩︎ ↩︎
```

## Instalação local

Copie `_extensions/reusable-footnotes/` para o projeto e adicione:

```yaml
filters:
  - reusable-footnotes
```

Opcionalmente:

```yaml
reusable-footnotes:
  enabled: true
  backlinks: true
  docx-scope: section
```

Nenhum `post-render` é necessário.

## Como funciona por formato

### HTML

A primeira ocorrência permanece como uma nota nativa. As ocorrências posteriores são links para a mesma nota. A nota canônica recebe backlinks discretos (`↩︎`) para as chamadas adicionais.

### PDF / LaTeX

A primeira ocorrência gera a nota normalmente e recebe um `\label` interno quando será reutilizada. As chamadas seguintes são renderizadas como:

```tex
\hyperref[rfn-note-...]{\textsuperscript{\ref*{rfn-note-...}}}
```

Assim, o número reutilizado continua sendo o mesmo **e também permanece clicável**, apontando para a nota canônica. Não são usados marcadores `\footnotemark[n]` sem link para recorrências.

### DOCX

O DOCX exige um cuidado adicional: o writer padrão do Pandoc/Quarto pode reiniciar a numeração das notas a cada seção de nível 1. Por isso, desde a versão **0.2.2**, a extensão também trata a reutilização com escopo de seção por padrão.

Dentro de cada H1:

1. a primeira ocorrência continua sendo uma nota nativa do Word;
2. se aquela nota for reutilizada na mesma seção, o filtro cria um bookmark invisível dentro da nota em `footnotes.xml`;
3. as ocorrências seguintes viram hyperlinks internos em estilo `FootnoteReference`;
4. o número exibido é o número **local daquela seção**, exatamente como o Word numera a nota nativa;
5. se o mesmo conteúdo reaparecer em outra H1, ele cria uma nova nota nativa naquela seção, em vez de apontar para a numeração da seção anterior.

A implementação continua sem `NOTEREF`, sem campos cacheados e sem pós-processamento.

Se um `reference-doc` personalizado usar numeração contínua em todo o DOCX, é possível restaurar o escopo global:

```yaml
reusable-footnotes:
  docx-scope: document
```

## Configuração

```yaml
reusable-footnotes:
  enabled: true
  backlinks: true
  docx-scope: section
```

- `enabled`: liga/desliga a extensão no documento.
- `backlinks`: no HTML, adiciona um retorno discreto para cada ocorrência adicional.
- `docx-scope`: `section` (padrão) acompanha a reinicialização das notas em cada H1; `document` usa numeração contínua no DOCX.

## Escopo

- **HTML em website/book:** cada `.qmd` é renderizado como uma página; o estado da extensão reinicia nessa nova renderização.
- **HTML de documento único:** o escopo é o documento.
- **PDF:** o escopo é o documento monolítico renderizado.
- **DOCX:** o padrão é cada seção H1, acompanhando a numeração nativa do Word/Pandoc; pode ser alterado para `document`.

## Regra de igualdade

A versão 0.2.2 usa correspondência **exata do AST da nota**, com uma única normalização deliberada: `SoftBreak` é tratado como espaço. Assim, quebrar a mesma nota em linhas diferentes no arquivo-fonte não muda sua identidade.

Formatação, links, citações e múltiplos parágrafos continuam fazendo parte da identidade. Isso evita heurísticas bibliográficas ou comparações aproximadas.

## Renderização

Com Quarto:

```bash
quarto render
```

O `index.qmd` gera HTML, PDF e DOCX em `_output/`.

Sem Quarto, para desenvolvimento/testes, há um fallback baseado em Pandoc:

```bash
./scripts/render-all.sh
```

## Testes

Os testes não usam Python. Eles cobrem separadamente:

- `bibentry` em citações normais, inline e dentro de footnotes;
- distinção entre `citation` e `bibliography` layouts do CSL;
- preservação de referências via `nocite`;
- reutilização de notas em HTML, PDF/LaTeX e DOCX;
- integração `bibentry` → `reusable-footnotes`;
- ausência de `NOTEREF` e de pós-processamento Python.

Execute:

```bash
./tests/run.sh
```

## Estrutura

```text
_extensions/
├── bibentry/               # development fork for upstream PR
│   ├── _extension.yml
│   ├── bibentry.lua
│   └── LICENSE
└── reusable-footnotes/
    ├── _extension.yml
    ├── reusable-footnotes.lua
    ├── reusable-footnotes.css
    └── reusable-footnotes.html

references.bib
scripts/
└── render-all.sh

tests/
├── fixtures/
└── run.sh

_quarto.yml
index.qmd
README.md
LICENSE
```

## Licença

`reusable-footnotes` é MIT. O código vendorizado de `bibentry` mantém a licença MIT original de Frederico Guth em `_extensions/bibentry/LICENSE`.
