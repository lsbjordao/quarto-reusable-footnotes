-- reusable-footnotes.lua
-- Quarto/Pandoc filter: repeated footnotes with the same AST content share a
-- single real note within the current rendered document/page.

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

local function add_latex_note_label(note, label)
  -- A label inside the canonical footnote resolves to that footnote number and,
  -- with hyperref, also provides the destination for repeated clickable marks.
  local blocks = note.content
  local first = blocks[1]
  local raw = pandoc.RawInline('latex', string.format('\\label{%s}', label))

  if first and (first.t == 'Para' or first.t == 'Plain') then
    table.insert(first.content, 1, raw)
  else
    table.insert(blocks, 1, pandoc.Plain({ raw }))
  end

  note.content = blocks
  return note
end

local function latex_reuse_link(label)
  -- \ref* supplies the number without creating a nested hyperlink; the outer
  -- \hyperref makes the repeated superscript jump to the canonical footnote.
  return pandoc.RawInline(
    'latex',
    string.format(
      '\\hyperref[%s]{\\textsuperscript{\\ref*{%s}}}',
      label,
      label
    )
  )
end

local function add_docx_note_anchor(note, bookmark_id, bookmark_name)
  -- Put the bookmark inside the actual footnote body. Repeated markers can then
  -- link directly to the canonical note without relying on Word field updates.
  local start_xml = string.format(
    '<w:bookmarkStart w:id="%d" w:name="%s"/>',
    bookmark_id,
    bookmark_name
  )
  local end_xml = string.format('<w:bookmarkEnd w:id="%d"/>', bookmark_id)
  local blocks = note.content
  local first = blocks[1]

  if first and (first.t == 'Para' or first.t == 'Plain') then
    table.insert(first.content, 1, pandoc.RawInline('openxml', end_xml))
    table.insert(first.content, 1, pandoc.RawInline('openxml', start_xml))
  else
    table.insert(blocks, 1, pandoc.Plain({
      pandoc.RawInline('openxml', start_xml),
      pandoc.RawInline('openxml', end_xml),
    }))
  end

  note.content = blocks
  return note
end

local function docx_reuse_link(bookmark_name, number)
  -- Use a plain internal hyperlink with a literal canonical number instead of
  -- NOTEREF. This avoids stale/cached field results displaying another note's
  -- number before Word refreshes its fields.
  local xml = string.format(
    '<w:hyperlink w:anchor="%s" w:history="1">' ..
      '<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>' ..
      '<w:t>%d</w:t></w:r>' ..
    '</w:hyperlink>',
    bookmark_name,
    number
  )
  return pandoc.RawInline('openxml', xml)
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

  local canonical_number = {}
  local occurrence = {}
  local latex_labels = {}
  local docx_bookmarks = {}
  local next_number = 0
  local next_bookmark_id = 2000000000

  local transformed = doc:walk({
    Note = function(note)
      local key = note_key(note)
      occurrence[key] = (occurrence[key] or 0) + 1
      local current_occurrence = occurrence[key]

      if canonical_number[key] == nil then
        next_number = next_number + 1
        canonical_number[key] = next_number

        if FORMAT:match('latex') and counts[key] > 1 then
          local label = string.format('rfn-note-%06d', next_number)
          latex_labels[key] = label
          note = add_latex_note_label(note, label)
        elseif FORMAT:match('html') and cfg.backlinks then
          note = append_html_backlinks(note, next_number, counts[key])
        elseif (FORMAT:match('docx') or FORMAT:match('openxml')) and counts[key] > 1 then
          next_bookmark_id = next_bookmark_id + 1
          local bookmark = {
            id = next_bookmark_id,
            name = string.format('rfn_note_%06d', next_number),
          }
          docx_bookmarks[key] = bookmark
          note = add_docx_note_anchor(note, bookmark.id, bookmark.name)
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
        local label = latex_labels[key]
        if label then
          return latex_reuse_link(label)
        end
        return pandoc.RawInline('latex', string.format('\\footnotemark[%d]', number))
      elseif FORMAT:match('docx') or FORMAT:match('openxml') then
        local bookmark = docx_bookmarks[key]
        if bookmark then
          return docx_reuse_link(bookmark.name, number)
        end
        return note
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
