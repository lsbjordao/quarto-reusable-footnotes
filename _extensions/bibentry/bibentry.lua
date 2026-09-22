-- bibentry.lua — render [@key]{.bibentry} using the active CSL bibliography layout.
--
-- Based on fredguth/bibentry (MIT, Frederico Guth), extended to support true
-- inline replacement, arbitrary nesting depth (including native footnotes),
-- bibliography preservation without hidden format-specific content, and stable
-- bibliography numbering by running citeproc once on the whole document.

PANDOC_VERSION:must_be_at_least {2,19,1}

local utils = require 'pandoc.utils'
local citeproc = utils.citeproc

local function has_class(el, class_name)
  return el.classes and el.classes:includes(class_name)
end

local function blocks_to_inlines(blocks)
  return utils.blocks_to_inlines(blocks, {pandoc.Space()})
end

local function collect_bibliography_entries(doc)
  -- Run citeproc once on a clone of the original document. Besides being much
  -- cheaper than one citeproc call per .bibentry, this preserves bibliography
  -- sorting and numbering for styles such as IEEE because each extracted entry
  -- is rendered in the context of the complete document.
  local probe = doc:clone()
  probe.meta['suppress-bibliography'] = nil
  local processed = citeproc(probe)

  local entries = {}
  processed:walk({
    Div = function(div)
      if has_class(div, 'csl-entry') then
        local id = div.identifier or ''
        id = id:gsub('^ref%-', '')
        if id ~= '' then
          entries[id] = blocks_to_inlines(div.content)
        end
      end
    end
  })
  return entries
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
    -- Preserve an unusual existing value and add the bibentry citations in a
    -- MetaBlocks value, which citeproc accepts for nocite.
    local old = utils.stringify(meta.nocite)
    meta.nocite = pandoc.MetaBlocks({
      pandoc.Plain({pandoc.Str(old)}),
      pandoc.Plain({cite})
    })
  end
end

function Pandoc(doc)
  local entries = collect_bibliography_entries(doc)
  local referenced = pandoc.List()
  local seen = {}

  local function remember(id)
    if not seen[id] then
      seen[id] = true
      referenced:insert(id)
    end
  end

  local function render_cite(cite)
    local result = pandoc.List()

    for _, citation in ipairs(cite.citations) do
      local id = citation.id
      local entry = entries[id]
      remember(id)

      if entry == nil then
        -- Let the document's normal citeproc pass handle unresolved entries.
        return cite
      end

      if #result > 0 then
        result:insert(pandoc.Str(';'))
        result:insert(pandoc.Space())
      end
      result:extend(entry)
    end

    return result
  end

  local transformed = doc:walk({
    Span = function(span)
      if not has_class(span, 'bibentry') then return nil end

      local found = false
      local replacement = span:walk({
        Cite = function(cite)
          found = true
          return render_cite(cite)
        end
      })

      if not found then
        return nil
      end

      -- Remove only the wrapper used as the bibentry marker. Any surrounding
      -- inline text remains untouched.
      return replacement.content
    end
  })

  -- The visible Cite nodes inside .bibentry spans have been replaced. Register
  -- their IDs through nocite so they still participate in the final References
  -- section without format-specific hidden content.
  append_nocite(transformed.meta, referenced)
  return transformed
end
