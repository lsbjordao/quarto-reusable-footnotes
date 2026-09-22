-- reusable-footnotes.lua
-- Reuse identical footnotes within a page while allowing the same note to
-- appear again on later pages. PDF/LaTeX uses fixfoot for true page-aware
-- behavior; HTML uses the current rendered HTML file as the page scope; DOCX
-- supports document/section/explicit-pagebreak scopes because physical Word
-- pagination happens after Pandoc's AST phase.

local utils = pandoc.utils

local function note_key(note)
  local normalized = pandoc.Pandoc(note.content):walk({
    SoftBreak = function() return pandoc.Space() end,
    Cite = function(cite)
      for _, citation in ipairs(cite.citations) do
        citation.note_num = 0
        citation.hash = 0
      end
      return cite
    end
  })
  return pandoc.write(normalized, "native")
end

local function meta_bool(value, default)
  if value == nil then return default end
  if type(value) == "boolean" then return value end
  local s = utils.stringify(value):lower()
  if s == "true" or s == "yes" or s == "1" then return true end
  if s == "false" or s == "no" or s == "0" then return false end
  return default
end

local function meta_string(value, default)
  if value == nil then return default end
  local s = utils.stringify(value):lower()
  if s == "" then return default end
  return s
end

local function meta_string_list(value)
  local result = pandoc.List()
  if value == nil then return result end
  local kind = utils.type(value)
  if kind == "List" or kind == "MetaList" then
    for _, item in ipairs(value) do
      local s = utils.stringify(item)
      if s ~= "" then result:insert(s) end
    end
  else
    local s = utils.stringify(value)
    if s ~= "" then result:insert(s) end
  end
  return result
end

local function config_from(meta)
  local cfg = {
    enabled = true,
    backlinks = true,
    scope = "page",
    numbering = "continuous",
    docx_scope = "pagebreak",
    html_order = pandoc.List(),
  }

  local raw = meta["reusable-footnotes"]
  if raw == nil then return cfg end

  if utils.type(raw) == "MetaMap" or utils.type(raw) == "table" then
    cfg.enabled = meta_bool(raw.enabled, true)
    cfg.backlinks = meta_bool(raw.backlinks, true)
    cfg.scope = meta_string(raw.scope, "page")
    cfg.numbering = meta_string(raw.numbering, "continuous")
    cfg.docx_scope = meta_string(raw["docx-scope"], "pagebreak")
    cfg.html_order = meta_string_list(raw["html-order"])
  else
    cfg.enabled = meta_bool(raw, true)
  end

  if cfg.scope ~= "page" and cfg.scope ~= "document" then
    cfg.scope = "page"
  end
  if cfg.numbering ~= "continuous" and cfg.numbering ~= "page" then
    cfg.numbering = "continuous"
  end
  if cfg.docx_scope ~= "pagebreak" and cfg.docx_scope ~= "section" and cfg.docx_scope ~= "document" then
    cfg.docx_scope = "pagebreak"
  end
  return cfg
end

local function append_html_backlinks(note, number, total_occurrences)
  if total_occurrences <= 1 then return note end
  local pieces = { '<span class="reusable-footnote-backlinks" aria-label="Additional returns">' }
  for occurrence = 2, total_occurrences do
    pieces[#pieces + 1] = string.format(
      '<a href="#fnref%d-r%d" class="reusable-footnote-back" role="doc-backlink" aria-label="Back to occurrence %d">↩︎</a>',
      number, occurrence, occurrence
    )
    pieces[#pieces + 1] = ' '
  end
  pieces[#pieces + 1] = '</span>'
  local raw = pandoc.RawInline('html', table.concat(pieces))
  local blocks = note.content
  local last = blocks[#blocks]
  if last and (last.t == 'Para' or last.t == 'Plain') then
    last.content:insert(pandoc.Space())
    last.content:insert(raw)
  else
    blocks:insert(pandoc.Plain({raw}))
  end
  note.content = blocks
  return note
end

local function include_html_assets()
  if quarto and quarto.doc and quarto.doc.include_file then
    quarto.doc.include_file('in-header', 'reusable-footnotes.html')
  end
end

local function normalize_path(path)
  path = tostring(path or ''):gsub('\\', '/')
  path = path:gsub('/+', '/')
  path = path:gsub('^%./', '')
  return path
end

local function join_path(base, relative)
  relative = normalize_path(relative)
  if relative:match('^/') or relative:match('^%a:/') then return relative end
  return normalize_path(base) .. '/' .. relative
end

local function count_unique_notes_in_source(path)
  local handle = io.open(path, 'r')
  if not handle then return 0 end
  local source = handle:read('*a')
  handle:close()

  local ok, parsed = pcall(pandoc.read, source, 'markdown')
  if not ok or parsed == nil then return 0 end

  local seen = {}
  local count = 0
  parsed:walk({
    Note = function(note)
      local key = note_key(note)
      if not seen[key] then
        seen[key] = true
        count = count + 1
      end
      return nil
    end
  })
  return count
end

local function html_global_offset(cfg)
  if cfg.numbering ~= 'continuous' or #cfg.html_order == 0 then return 0 end
  if not quarto or not quarto.project or not quarto.doc then return 0 end
  if not quarto.project.directory or not quarto.doc.input_file then return 0 end

  local project_dir = normalize_path(quarto.project.directory)
  local current = normalize_path(quarto.doc.input_file)
  local prefix = project_dir .. '/'
  local relative_current = current
  if current:sub(1, #prefix) == prefix then
    relative_current = current:sub(#prefix + 1)
  end
  relative_current = normalize_path(relative_current)

  local offset = 0
  local found = false
  for _, source_path in ipairs(cfg.html_order) do
    local relative = normalize_path(source_path)
    if relative == relative_current then
      found = true
      break
    end
    offset = offset + count_unique_notes_in_source(join_path(project_dir, relative))
  end

  if not found then return 0 end
  return offset
end

local function append_html_global_numbering_script(doc, offset)
  if offset <= 0 then return doc end
  local script = string.format([[
<script>
document.addEventListener("DOMContentLoaded", function () {
  const offset = %d;
  document.querySelectorAll('a[role="doc-noteref"] > sup').forEach(function (sup) {
    const local = Number.parseInt(sup.textContent, 10);
    if (!Number.isNaN(local)) sup.textContent = String(local + offset);
  });
  const list = document.querySelector('section.footnotes > ol');
  if (list) list.setAttribute('start', String(offset + 1));
});
</script>]], offset)
  doc.blocks:insert(pandoc.RawBlock('html', script))
  return doc
end

local function add_header_latex(meta, text)
  if quarto and quarto.doc and quarto.doc.include_text then
    quarto.doc.include_text('in-header', text)
    return
  end
  local raw = pandoc.RawBlock('latex', text)
  local existing = meta['header-includes']
  if existing == nil then
    meta['header-includes'] = pandoc.MetaBlocks({raw})
    return
  end
  local kind = utils.type(existing)
  if kind == 'Blocks' then
    existing:insert(raw)
  elseif kind == 'List' or kind == 'MetaList' then
    existing:insert(pandoc.MetaBlocks({raw}))
  else
    meta['header-includes'] = pandoc.MetaList({existing, pandoc.MetaBlocks({raw})})
  end
end

local function collect_citation_ids(blocks, ids, seen)
  pandoc.Pandoc(blocks):walk({
    Cite = function(cite)
      for _, citation in ipairs(cite.citations) do
        if not seen[citation.id] then
          seen[citation.id] = true
          ids:insert(citation.id)
        end
      end
      return nil
    end
  })
end

local function append_nocite(meta, ids)
  if #ids == 0 then return end
  local citations = pandoc.List()
  for _, id in ipairs(ids) do
    citations:insert(pandoc.Citation(id, 'NormalCitation'))
  end
  local cite = pandoc.Cite({}, citations)
  if meta.nocite == nil then
    meta.nocite = pandoc.MetaInlines({cite})
    return
  end
  local kind = utils.type(meta.nocite)
  if kind == 'Inlines' then
    meta.nocite:insert(pandoc.Space())
    meta.nocite:insert(cite)
  elseif kind == 'Blocks' then
    meta.nocite:insert(pandoc.Plain({cite}))
  else
    meta.nocite = pandoc.MetaList({meta.nocite, pandoc.MetaInlines({cite})})
  end
end

local function note_blocks_for_latex(note, meta)
  local mini = pandoc.Pandoc(note.content, meta):clone()
  mini.meta['suppress-bibliography'] = pandoc.MetaBool(true)
  local ok, processed = pcall(utils.citeproc, mini)
  if ok then return processed.blocks end
  return note.content
end

local function alpha_id(n)
  local chars = {}
  repeat
    local r = (n - 1) % 26
    table.insert(chars, 1, string.char(97 + r))
    n = math.floor((n - 1) / 26)
  until n == 0
  return table.concat(chars)
end

local function process_latex_page_scope(doc, cfg)
  local ids_by_key = {}
  local note_by_key = {}
  local order = pandoc.List()
  local cited_ids = pandoc.List()
  local seen_cites = {}

  doc:walk({
    Note = function(note)
      local key = note_key(note)
      if ids_by_key[key] == nil then
        local id = #order + 1
        ids_by_key[key] = id
        note_by_key[key] = note
        order:insert(key)
      end
      collect_citation_ids(note.content, cited_ids, seen_cites)
      return nil
    end
  })

  if #order == 0 then return doc end

  local preamble = { '\\usepackage{fixfoot}' }
  if cfg.numbering == 'page' then
    preamble[#preamble + 1] = '\\usepackage{perpage}'
    preamble[#preamble + 1] = '\\MakePerPage{footnote}'
  end

  for _, key in ipairs(order) do
    local id = ids_by_key[key]
    local tag = alpha_id(id)
    local blocks = note_blocks_for_latex(note_by_key[key], doc.meta)
    local body = pandoc.write(pandoc.Pandoc(blocks, doc.meta), 'latex')
    body = body:gsub('%s+$', '')
    preamble[#preamble + 1] = string.format('\\long\\def\\rfnbody%s{%s}', tag, body)
    preamble[#preamble + 1] = string.format(
      '\\DeclareFixedFootnote{\\rfnnote%s}{\\protect\\rfnbody%s}', tag, tag
    )
  end

  add_header_latex(doc.meta, table.concat(preamble, '\n'))
  append_nocite(doc.meta, cited_ids)

  return doc:walk({
    Note = function(note)
      local id = ids_by_key[note_key(note)]
      return pandoc.RawInline('latex', string.format('\\rfnnote%s', alpha_id(id)))
    end
  })
end

local function add_latex_note_label(note, label)
  local blocks = note.content
  local first = blocks[1]
  local raw = pandoc.RawInline('latex', string.format('\\label{%s}', label))
  if first and (first.t == 'Para' or first.t == 'Plain') then
    table.insert(first.content, 1, raw)
  else
    table.insert(blocks, 1, pandoc.Plain({raw}))
  end
  note.content = blocks
  return note
end

local function latex_reuse_link(label)
  return pandoc.RawInline('latex', string.format(
    '\\hyperref[%s]{\\textsuperscript{\\ref*{%s}}}', label, label
  ))
end

local function process_latex_document_scope(doc)
  local counts = {}
  doc:walk({Note=function(note)
    local key=note_key(note); counts[key]=(counts[key] or 0)+1
  end})
  local numbers, occ, labels = {}, {}, {}
  local next_number = 0
  return doc:walk({Note=function(note)
    local key=note_key(note)
    occ[key]=(occ[key] or 0)+1
    if numbers[key] == nil then
      next_number=next_number+1
      numbers[key]=next_number
      if counts[key] > 1 then
        local label=string.format('rfn-note-%06d', next_number)
        labels[key]=label
        note=add_latex_note_label(note,label)
      end
      return note
    end
    return latex_reuse_link(labels[key])
  end})
end

local function process_html(doc, cfg)
  local counts = {}
  doc:walk({Note=function(note)
    local key=note_key(note); counts[key]=(counts[key] or 0)+1
  end})
  local numbers, occ = {}, {}
  local next_number = 0
  local transformed = doc:walk({Note=function(note)
    local key=note_key(note)
    occ[key]=(occ[key] or 0)+1
    if numbers[key] == nil then
      next_number=next_number+1
      numbers[key]=next_number
      if cfg.backlinks then note=append_html_backlinks(note,next_number,counts[key]) end
      return note
    end
    local number=numbers[key]
    return pandoc.RawInline('html', string.format(
      '<a href="#fn%d" class="footnote-ref reusable-footnote-ref" id="fnref%d-r%d" role="doc-noteref"><sup>%d</sup></a>',
      number, number, occ[key], number
    ))
  end})
  include_html_assets()
  return append_html_global_numbering_script(transformed, html_global_offset(cfg))
end

local function add_docx_note_anchor(note, bookmark_id, bookmark_name)
  local start_xml = string.format('<w:bookmarkStart w:id="%d" w:name="%s"/>', bookmark_id, bookmark_name)
  local end_xml = string.format('<w:bookmarkEnd w:id="%d"/>', bookmark_id)
  local blocks = note.content
  local first = blocks[1]
  if first and (first.t == 'Para' or first.t == 'Plain') then
    table.insert(first.content, 1, pandoc.RawInline('openxml', end_xml))
    table.insert(first.content, 1, pandoc.RawInline('openxml', start_xml))
  else
    table.insert(blocks, 1, pandoc.Plain({pandoc.RawInline('openxml',start_xml),pandoc.RawInline('openxml',end_xml)}))
  end
  note.content=blocks
  return note
end

local function docx_reuse_link(bookmark_name, number)
  return pandoc.RawInline('openxml', string.format(
    '<w:hyperlink w:anchor="%s" w:history="1"><w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:t>%d</w:t></w:r></w:hyperlink>',
    bookmark_name, number
  ))
end

local function is_docx_pagebreak(block)
  if block.t ~= 'RawBlock' then return false end
  if block.format == 'openxml' and block.text:match('w:br[^>]-w:type=["\']page["\']') then return true end
  if (block.format == 'tex' or block.format == 'latex') and block.text:match('^%s*\\(newpage|pagebreak)') then return true end
  return false
end

local function docx_scope_id(cfg, state)
  if cfg.docx_scope == 'document' then return 0 end
  if cfg.docx_scope == 'section' then return state.section end
  return state.pagebreak
end

local function process_docx(doc, cfg)
  local counts = {}
  local state = {section=0,pagebreak=0}
  for _, block in ipairs(doc.blocks) do
    if cfg.docx_scope == 'section' and block.t=='Header' and block.level==1 then state.section=state.section+1 end
    if cfg.docx_scope == 'pagebreak' and is_docx_pagebreak(block) then state.pagebreak=state.pagebreak+1 end
    local sid=docx_scope_id(cfg,state)
    pandoc.walk_block(block,{Note=function(note)
      local key=tostring(sid)..'\31'..note_key(note)
      counts[key]=(counts[key] or 0)+1
      return note
    end})
  end

  local canonical_number, bookmarks, next_number_by_scope = {}, {}, {}
  local next_number_global = 0
  local next_bookmark_id=2000000000
  state={section=0,pagebreak=0}
  for i,block in ipairs(doc.blocks) do
    if cfg.docx_scope == 'section' and block.t=='Header' and block.level==1 then state.section=state.section+1 end
    if cfg.docx_scope == 'pagebreak' and is_docx_pagebreak(block) then state.pagebreak=state.pagebreak+1 end
    local sid=docx_scope_id(cfg,state)
    doc.blocks[i]=pandoc.walk_block(block,{Note=function(note)
      local key=tostring(sid)..'\31'..note_key(note)
      if canonical_number[key] == nil then
        local number
        if cfg.numbering == 'page' and cfg.docx_scope == 'pagebreak' then
          number=(next_number_by_scope[sid] or 0)+1
          next_number_by_scope[sid]=number
        elseif cfg.numbering == 'page' and cfg.docx_scope == 'section' then
          number=(next_number_by_scope[sid] or 0)+1
          next_number_by_scope[sid]=number
        else
          next_number_global=next_number_global+1
          number=next_number_global
        end
        canonical_number[key]=number
        if (counts[key] or 0)>1 then
          next_bookmark_id=next_bookmark_id+1
          local bookmark={id=next_bookmark_id,name=string.format('rfn_note_s%06d_n%06d',sid,number)}
          bookmarks[key]=bookmark
          note=add_docx_note_anchor(note,bookmark.id,bookmark.name)
        end
        return note
      end
      local bookmark=bookmarks[key]
      if bookmark then return docx_reuse_link(bookmark.name,canonical_number[key]) end
      return note
    end})
  end
  return doc
end

local function is_docx_format()
  return FORMAT:match('docx') or FORMAT:match('openxml')
end

function Pandoc(doc)
  local cfg=config_from(doc.meta)
  if not cfg.enabled then return doc end

  if is_docx_format() then return process_docx(doc,cfg) end
  if FORMAT:match('latex') then
    if cfg.scope == 'page' then return process_latex_page_scope(doc,cfg) end
    return process_latex_document_scope(doc)
  end
  if FORMAT:match('html') then return process_html(doc,cfg) end
  return doc
end
