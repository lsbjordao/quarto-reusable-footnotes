# reusable-footnotes

Extensão Quarto para **reutilizar notas de rodapé idênticas sem gerar novos
números**.

A proposta é deliberadamente simples: continue escrevendo notas com a sintaxe
normal do Pandoc/Quarto (`^[...]` ou `[^id]`). Se o conteúdo AST de duas notas
for exatamente igual, apenas a primeira cria uma nota real; as demais apontam
para o mesmo número.

## Exemplo

```markdown
Primeira ocorrência.^[Flora e Funga do Brasil, 2026.]

Segunda ocorrência.^[Flora e Funga do Brasil, 2026.]
```

Em vez de `1` e `2`, as duas chamadas mostram `1`, com uma única nota no
rodapé. No HTML, três ocorrências produzem retornos discretos como:

```text
1. Flora e Funga do Brasil, 2026. ↩︎ ↩︎ ↩︎
```

## Instalação local

Copie `_extensions/reusable-footnotes/` para o projeto e adicione:

```yaml
filters:
  - reusable-footnotes
```

Para DOCX, inclua também o pós-processamento:

```yaml
project:
  post-render:
    - python _extensions/reusable-footnotes/reusable-footnotes-docx.py
```

O pós-processador é necessário porque o writer DOCX do Pandoc cria uma nota
Word distinta para cada nó `Note`. Durante a conversão, o filtro acrescenta
marcas invisíveis de grupo; o script (somente biblioteca padrão do Python)
remove essas marcas, consolida as notas equivalentes e substitui chamadas
posteriores por um sobrescrito com o número canônico e hiperlink interno.

## Configuração

```yaml
reusable-footnotes:
  enabled: true
  backlinks: true
```

- `enabled`: liga/desliga a extensão no documento.
- `backlinks`: no HTML, adiciona um retorno discreto para cada ocorrência.

## Escopo

- **HTML em website/book:** cada `.qmd` é renderizado como uma página; o estado
  da extensão reinicia nessa nova renderização.
- **HTML de documento único:** o escopo é o documento.
- **PDF/DOCX:** o escopo é o documento monolítico renderizado.

## Regra de igualdade

A versão 0.1.0 usa correspondência **exata do AST da nota**, com uma única
normalização deliberada: `SoftBreak` é tratado como espaço. Assim, quebrar a
mesma nota em linhas diferentes no arquivo-fonte não muda sua identidade.
Formatação, links, citações e múltiplos parágrafos continuam fazendo parte da
identidade. Isso evita heurísticas bibliográficas ou comparações aproximadas.

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

## Estrutura

```text
_extensions/reusable-footnotes/
├── _extension.yml
├── reusable-footnotes.lua
├── reusable-footnotes.css
├── reusable-footnotes.html
└── reusable-footnotes-docx.py

scripts/
└── render-all.sh

tests/
└── test-docx.py

_quarto.yml
index.qmd
README.md
LICENSE
```

## Licença

MIT.
