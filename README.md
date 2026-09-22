# reusable-footnotes

Extensão Quarto para **reutilizar notas de rodapé idênticas sem gerar novos números**.

A proposta é deliberadamente simples: continue escrevendo notas com a sintaxe normal do Pandoc/Quarto (`^[...]` ou `[^id]`). Se o conteúdo AST de duas notas for exatamente igual, apenas a primeira cria uma nota real; as demais remetem ao mesmo número.

A partir da versão **0.2.0**, a extensão é **100% Lua/Quarto**: não há pós-processamento em Python nem dependência externa para DOCX.

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
```

Nenhum `post-render` é necessário.

## Como funciona por formato

### HTML

A primeira ocorrência permanece como uma nota nativa. As ocorrências posteriores são links para a mesma nota. A nota canônica recebe backlinks discretos (`↩︎`) para as chamadas adicionais.

### PDF / LaTeX

A primeira ocorrência gera a nota normalmente. As demais usam `\footnotemark[n]`, reutilizando o marcador já criado sem repetir o texto da nota.

### DOCX

A implementação usa somente Lua + OpenXML emitido pelo próprio Pandoc:

1. a primeira ocorrência continua sendo uma nota nativa do Word;
2. se aquela nota for reutilizada, o filtro envolve a primeira marca de referência com um bookmark invisível;
3. as ocorrências seguintes viram campos Word `NOTEREF` apontando para esse bookmark;
4. o campo usa `\f` para manter a formatação de referência de nota e `\h` para criar o hyperlink.

`NOTEREF` é o mecanismo nativo do Word para fazer múltiplas referências à mesma nota. Assim, o DOCX contém uma única nota real em `footnotes.xml`, enquanto as chamadas posteriores acompanham a mesma referência.

## Configuração

```yaml
reusable-footnotes:
  enabled: true
  backlinks: true
```

- `enabled`: liga/desliga a extensão no documento.
- `backlinks`: no HTML, adiciona um retorno discreto para cada ocorrência adicional.

## Escopo

- **HTML em website/book:** cada `.qmd` é renderizado como uma página; o estado da extensão reinicia nessa nova renderização.
- **HTML de documento único:** o escopo é o documento.
- **PDF/DOCX:** o escopo é o documento monolítico renderizado.

Isso produz exatamente o comportamento esperado para books/websites: a mesma nota reutiliza o número dentro da página atual, mas pode receber uma nova numeração quando reaparece em outra página `.qmd`.

## Regra de igualdade

A versão 0.2.0 usa correspondência **exata do AST da nota**, com uma única normalização deliberada: `SoftBreak` é tratado como espaço. Assim, quebrar a mesma nota em linhas diferentes no arquivo-fonte não muda sua identidade.

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

Os testes também não usam Python. Eles dependem apenas das ferramentas de linha de comando utilizadas pelo projeto (`bash`, `grep`, `unzip`, Pandoc/Quarto):

```bash
./tests/run.sh
```

O teste DOCX verifica que o exemplo contém 9 notas reais e 9 recorrências `NOTEREF`, em vez de 18 notas independentes.

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
