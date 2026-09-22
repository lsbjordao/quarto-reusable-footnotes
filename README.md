# reusable-footnotes

Extensão Quarto para **reutilizar notas de rodapé idênticas sem gerar novos números**.

A proposta é deliberadamente simples: continue escrevendo notas com a sintaxe normal do Pandoc/Quarto (`^[...]` ou `[^id]`). Se o conteúdo AST de duas notas for exatamente igual, apenas a primeira cria uma nota real; as demais remetem ao mesmo número.

A extensão é **100% Lua/Quarto**: não há pós-processamento em Python nem dependência externa para DOCX.

## Exemplo

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

Isso evita o erro em que, por exemplo, a primeira nota de uma seção aparecia nativamente como `1`, mas sua recorrência era exibida como `3`, `5` ou outro número global do documento.

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

Os testes não usam Python. Eles verificam, entre outras coisas:

- 9 notas reais + 9 recorrências no HTML;
- 9 recorrências PDF geradas como hyperlinks para 7 notas canônicas;
- ausência de `\footnotemark[n]` sem link nas recorrências do PDF;
- 9 notas reais + 9 hyperlinks internos no DOCX;
- numeração DOCX local por seção (`1`, `2`, ...), sem reaproveitar números globais incorretos;
- uma mesma nota em duas H1 diferentes gera duas notas nativas locais;
- ausência de `NOTEREF` e de arquivos Python.

Execute:

```bash
./tests/run.sh
```

## Estrutura

```text
_extensions/reusable-footnotes/
├── _extension.yml
├── reusable-footnotes.lua
├── reusable-footnotes.css
└── reusable-footnotes.html

scripts/
└── render-all.sh

tests/
└── run.sh

_quarto.yml
index.qmd
README.md
LICENSE
```

## Licença

MIT.
