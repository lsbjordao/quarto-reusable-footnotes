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

local function docx_bookmark_start(bookmark_id, bookmark_name)
  return pandoc.RawInline(
    'openxml',
    string.format(
      '<w:bookmarkStart w:id="%d" w:name="%s"/>',
      bookmark_id,
      bookmark_name
    )
  )
end

local function docx_bookmark_end(bookmark_id)
  return pandoc.RawInline(
    'openxml',
    string.format('<w:bookmarkEnd w:id="%d"/>', bookmark_id)
  )
end

local function docx_noteref(bookmark_name, cached_number)
  -- NOTEREF is Word's native cross-reference field for multiple references to
  -- one footnote/endnote. \f applies the Footnote Reference character style;
  -- \h makes the field a hyperlink to the bookmarked original reference.
  -- w:dirty asks Word to refresh the cached field result when appropriate.
  local xml = string.format(
    '<w:fldSimple w:instr=" NOTEREF %s \\f \\h " w:dirty="true">' ..
      '<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>' ..
      '<w:t>%d</w:t></w:r>' ..
    '</w:fldSimple>',
    bookmark_name,
    cached_number
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

        if FORMAT:match('html') and cfg.backlinks then
          note = append_html_backlinks(note, next_number, counts[key])
        elseif (FORMAT:match('docx') or FORMAT:match('openxml')) and counts[key] > 1 then
          -- Word's NOTEREF field requires a bookmark around the original
          -- footnote reference mark in the document body (not inside the note).
          next_bookmark_id = next_bookmark_id + 1
          local bookmark = {
            id = next_bookmark_id,
            name = string.format('rfn_ref_%06d', next_number),
          }
          docx_bookmarks[key] = bookmark
          return {
            docx_bookmark_start(bookmark.id, bookmark.name),
            note,
            docx_bookmark_end(bookmark.id),
          }
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
      elseif FORMAT:match('docx') or FORMAT:match('openxml') then
        local bookmark = docx_bookmarks[key]
        if bookmark then
          return docx_noteref(bookmark.name, number)
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
