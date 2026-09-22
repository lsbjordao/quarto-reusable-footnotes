-- reusable-footnotes.lua
-- Quarto/Pandoc filter: repeated footnotes with exactly the same AST content
-- share the same number within the current rendered document/page.

local function note_key(note)
  -- Treat editorial line wrapping as ordinary whitespace. This means the same
  -- note still matches if one occurrence was wrapped at a different source line.
  local normalized = pandoc.Pandoc(note.content):walk({
    SoftBreak = function()
      return pandoc.Space()
    end
  })

  -- Native AST serialization preserves semantic differences (formatting, links,
  -- citations, multiple paragraphs) while ignoring the original footnote label,
  -- which Pandoc has already resolved before filters run.
  return pandoc.write(normalized, "native")
end

local function meta_bool(value, default)
  if value == nil then return default end
  if type(value) == "boolean" then return value end
  local s = pandoc.utils.stringify(value):lower()
  if s == "true" or s == "yes" or s == "1" then return true end
  if s == "false" or s == "no" or s == "0" then return false end
  return default
end

local function config_from(meta)
  local cfg = {
    enabled = true,
    backlinks = true,
  }

  local raw = meta["reusable-footnotes"]
  if raw == nil then return cfg end

  if pandoc.utils.type(raw) == "MetaMap" then
    cfg.enabled = meta_bool(raw.enabled, true)
    cfg.backlinks = meta_bool(raw.backlinks, true)
  else
    cfg.enabled = meta_bool(raw, true)
  end
  return cfg
end

local function append_html_backlinks(note, number, total_occurrences)
  if total_occurrences <= 1 then return note end

  local pieces = { '<span class="reusable-footnote-backlinks" aria-label="Retornos adicionais">' }
  for occurrence = 2, total_occurrences do
    table.insert(
      pieces,
      string.format(
        '<a href="#fnref%d-r%d" class="reusable-footnote-back" role="doc-backlink" aria-label="Voltar à ocorrência %d">↩︎</a>',
        number,
        occurrence,
        occurrence
      )
    )
    table.insert(pieces, ' ')
  end
  table.insert(pieces, '</span>')

  local raw = pandoc.RawInline('html', table.concat(pieces))
  local blocks = note.content
  local last = blocks[#blocks]

  if last and (last.t == 'Para' or last.t == 'Plain') then
    table.insert(last.content, pandoc.Space())
    table.insert(last.content, raw)
  else
    table.insert(blocks, pandoc.Plain({ raw }))
  end

  note.content = blocks
  return note
end


local function append_docx_group_marker(note, group_id)
  local marker = string.format("__REUSABLE_FOOTNOTE_GROUP_%06d__", group_id)
  local xml = string.format(
    '<w:r><w:rPr><w:vanish/></w:rPr><w:t>%s</w:t></w:r>',
    marker
  )
  local raw = pandoc.RawInline('openxml', xml)
  local blocks = note.content
  local last = blocks[#blocks]
  if last and (last.t == 'Para' or last.t == 'Plain') then
    table.insert(last.content, raw)
  else
    table.insert(blocks, pandoc.Plain({ raw }))
  end
  note.content = blocks
  return note
end

local function include_html_assets()
  if not quarto or not quarto.doc or not quarto.doc.include_file then return end
  quarto.doc.include_file('in-header', 'reusable-footnotes.html')
end

function Pandoc(doc)
  local cfg = config_from(doc.meta)
  if not cfg.enabled then return doc end

  local counts = {}
  doc:walk({
    Note = function(note)
      local key = note_key(note)
      counts[key] = (counts[key] or 0) + 1
    end
  })

  -- DOCX needs a post-render OOXML pass. Give all members of a repeated group
  -- the same invisible marker so the post-processor can recover the semantic
  -- grouping even when Pandoc splits equivalent text into different Word runs.
  if FORMAT:match('docx') or FORMAT:match('openxml') then
    local group_for_key = {}
    local next_group = 0
    return doc:walk({
      Note = function(note)
        local key = note_key(note)
        if (counts[key] or 0) <= 1 then return note end
        if group_for_key[key] == nil then
          next_group = next_group + 1
          group_for_key[key] = next_group
        end
        return append_docx_group_marker(note, group_for_key[key])
      end
    })
  end

  local canonical_number = {}
  local occurrence = {}
  local next_number = 0

  local transformed = doc:walk({
    Note = function(note)
      local key = note_key(note)
      occurrence[key] = (occurrence[key] or 0) + 1
      local current_occurrence = occurrence[key]

      if canonical_number[key] == nil then
        next_number = next_number + 1
        canonical_number[key] = next_number

        if FORMAT:match('html') and cfg.backlinks then
          note = append_html_backlinks(note, next_number, counts[key])
        end
        return note
      end

      local number = canonical_number[key]

      if FORMAT:match('html') then
        return pandoc.RawInline(
          'html',
          string.format(
            '<a href="#fn%d" class="footnote-ref reusable-footnote-ref" id="fnref%d-r%d" role="doc-noteref"><sup>%d</sup></a>',
            number,
            number,
            current_occurrence,
            number
          )
        )
      elseif FORMAT:match('latex') then
        -- Reuse the already-created marker without creating another footnote.
        return pandoc.RawInline('latex', string.format('\\footnotemark[%d]', number))
      else
        -- Conservative fallback for formats without a dedicated renderer.
        return note
      end
    end
  })

  if FORMAT:match('html') then
    include_html_assets()
  end

  return transformed
end
