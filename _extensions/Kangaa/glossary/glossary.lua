local glossary_entries = {}
local glossary_map = {}
local used_entries = {}
local used_count = 0
local glossary_page = nil
local glossary_include = "auto"
local glossary_sort = "yaml"
local glossary_loaded = false
local function is_list(value)
  local t = pandoc.utils.type(value)
  return t == "MetaList" or t == "List"
end

local function is_map(value)
  local t = pandoc.utils.type(value)
  return t == "MetaMap" or t == "Map" or t == "table"
end

local function file_exists(path)
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    return true
  end
  return false
end

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end
  local content = fh:read("*a")
  fh:close()
  if content == "" then
    return nil
  end
  return content
end

local function find_project_file(name)
  local candidates = {}
  local input = PANDOC_STATE and PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]

  if input and pandoc.path and pandoc.path.directory then
    local dir = pandoc.path.directory(input)
    if dir and dir ~= "" then
      local current = dir
      for _ = 1, 5 do
        table.insert(candidates, pandoc.path.join({ current, name }))
        local parent = pandoc.path.directory(current)
        if not parent or parent == "" or parent == current then
          break
        end
        current = parent
      end
    end
  end

  table.insert(candidates, name)

  for _, path in ipairs(candidates) do
    if file_exists(path) then
      return path
    end
  end

  return nil
end

local function parse_yaml_metadata(path)
  local content = read_file(path)
  if not content then
    return nil
  end
  local doc = pandoc.read("---\n" .. content .. "\n---", "markdown")
  return doc.meta
end

local function parse_markdown_metadata(path)
  local content = read_file(path)
  if not content then
    return nil
  end
  local doc = pandoc.read(content, "markdown")
  return doc.meta
end

local function project_metadata()
  local quarto_path = find_project_file("_quarto.yml")
  local meta = quarto_path and parse_yaml_metadata(quarto_path) or nil
  if meta then
    return meta
  end
  local metadata_path = find_project_file("_metadata.yml")
  return metadata_path and parse_yaml_metadata(metadata_path) or nil
end

local function meta_value(meta, key)
  if meta and meta[key] ~= nil then
    return meta[key]
  end
  local nested = meta and meta["metadata"]
  if nested and is_map(nested) then
    return nested[key]
  end
  return nil
end

local function has_class(el, class)
  for _, c in ipairs(el.classes or {}) do
    if c == class then
      return true
    end
  end
  return false
end

local function normalize_key(text)
  local s = text:gsub("^%s+", ""):gsub("%s+$", "")
  return s:lower()
end

local function slugify(text)
  local s = text:lower()
  s = s:gsub("[^%w%s-]", "")
  s = s:gsub("%s+", "-")
  s = s:gsub("%-+", "-")
  s = s:gsub("^%-", ""):gsub("%-$", "")
  if s == "" then
    s = "term"
  end
  return s
end

local function unique_anchor(base, used)
  local anchor = base
  local i = 2
  while used[anchor] do
    anchor = base .. "-" .. i
    i = i + 1
  end
  used[anchor] = true
  return anchor
end

local function meta_string(value)
  if value == nil then
    return nil
  end
  local text = pandoc.utils.stringify(value)
  if text == "" then
    return nil
  end
  return text
end

local function definition_blocks(value)
  local text = pandoc.utils.stringify(value)
  if text == "" then
    return {}
  end
  local doc = pandoc.read(text, "markdown")
  return doc.blocks
end

local function definition_text(blocks)
  if not blocks or #blocks == 0 then
    return ""
  end
  local doc = pandoc.Pandoc(blocks)
  local text = pandoc.utils.stringify(doc)
  text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function parse_glossary(meta)
  glossary_entries = {}
  glossary_map = {}
  used_entries = {}
  used_count = 0

  local anchor_used = {}
  if not meta or not is_list(meta) then
    return
  end

  for _, item in ipairs(meta) do
    if is_map(item) then
      local term = meta_string(item.term or item.name)
      local definition = item.definition or item.def
      if term and definition then
        local raw_id = meta_string(item.id)
        local anchor_base = "glossary-" .. (raw_id or slugify(term))
        local anchor = unique_anchor(anchor_base, anchor_used)
        local blocks = definition_blocks(definition)
        local entry = {
          term = term,
          anchor = anchor,
          definition = blocks,
          definition_text = definition_text(blocks),
        }
        table.insert(glossary_entries, entry)

        local key = normalize_key(term)
        if glossary_map[key] == nil then
          glossary_map[key] = entry
        end

        if item.aliases and is_list(item.aliases) then
          for _, alias in ipairs(item.aliases) do
            local alias_text = meta_string(alias)
            if alias_text then
              local alias_key = normalize_key(alias_text)
              if glossary_map[alias_key] == nil then
                glossary_map[alias_key] = entry
              end
            end
          end
        end
      end
    end
  end
end

local function ensure_glossary_loaded(meta)
  if glossary_loaded then
    return
  end

  local glossary_meta = meta_value(meta, "glossary")
  local project_meta = project_metadata()
  if not glossary_meta or not is_list(glossary_meta) then
    glossary_meta = project_meta and meta_value(project_meta, "glossary") or nil
  end

  local function pick_meta(key)
    local value = meta_value(meta, key)
    if value == nil or meta_string(value) == nil then
      value = project_meta and meta_value(project_meta, key) or nil
    end
    return meta_string(value)
  end

  glossary_page = pick_meta("glossary-page")
  glossary_include = pick_meta("glossary-include")
  glossary_sort = pick_meta("glossary-sort")

  local glossary_path = nil
  if glossary_page then
    glossary_path = find_project_file(glossary_page)
  else
    local fallback = find_project_file("glossary.qmd")
    if fallback then
      glossary_page = "glossary.qmd"
      glossary_path = fallback
    end
  end

  if glossary_path then
    local glossary_meta_doc = parse_markdown_metadata(glossary_path)
    if glossary_meta_doc then
      if not glossary_meta or not is_list(glossary_meta) then
        glossary_meta = meta_value(glossary_meta_doc, "glossary")
      end
      if not glossary_page or glossary_page == "" then
        glossary_page = meta_string(meta_value(glossary_meta_doc, "glossary-page"))
      end
      if not glossary_include or glossary_include == "" then
        glossary_include = meta_string(meta_value(glossary_meta_doc, "glossary-include"))
      end
      if not glossary_sort or glossary_sort == "" then
        glossary_sort = meta_string(meta_value(glossary_meta_doc, "glossary-sort"))
      end
    end
  end

  parse_glossary(glossary_meta)

  glossary_include = (glossary_include or "auto"):lower()
  glossary_sort = (glossary_sort or "yaml"):lower()

  glossary_loaded = true
end

local function glossary_href(entry)
  if glossary_page and FORMAT:match("html") then
    local page = glossary_page
    if page:match("%.qmd$") then
      page = page:gsub("%.qmd$", ".html")
    end
    return page .. "#" .. entry.anchor
  end
  return "#" .. entry.anchor
end

local function should_include(entry)
  if glossary_include == "all" then
    return true
  end
  if glossary_include == "used" then
    return used_entries[entry.anchor] ~= nil
  end
  if used_count == 0 then
    return true
  end
  return used_entries[entry.anchor] ~= nil
end

local function sorted_entries(entries)
  if glossary_sort ~= "alpha" then
    return entries
  end
  local sorted = {}
  for _, entry in ipairs(entries) do
    table.insert(sorted, entry)
  end
  table.sort(sorted, function(a, b)
    return a.term:lower() < b.term:lower()
  end)
  return sorted
end

local function build_glossary_blocks()
  local blocks = {}
  local included = {}

  for _, entry in ipairs(glossary_entries) do
    if should_include(entry) then
      table.insert(included, entry)
    end
  end

  for _, entry in ipairs(sorted_entries(included)) do
    local content = {
      pandoc.Para({ pandoc.Strong({ pandoc.Str(entry.term) }) }),
    }
    for _, def_block in ipairs(entry.definition) do
      table.insert(content, def_block)
    end
    table.insert(blocks, pandoc.Div(content, pandoc.Attr(entry.anchor, { "glossary-entry" })))
  end

  if #blocks == 0 then
    blocks = { pandoc.Para({ pandoc.Emph({ pandoc.Str("No glossary terms found.") }) }) }
  end

  return blocks
end

function Pandoc(doc)
  ensure_glossary_loaded(doc.meta or {})

  local function link_glossary_span(el)
    if not has_class(el, "glossary") then
      return nil
    end

    local lookup = meta_string(el.attributes["term"] or el.attributes["key"])
      or pandoc.utils.stringify(el.content)
    local entry = glossary_map[normalize_key(lookup)]
    if not entry then
      return el
    end

    if used_entries[entry.anchor] == nil then
      used_entries[entry.anchor] = true
      used_count = used_count + 1
    end

    local target = glossary_href(entry)
    local title = entry.definition_text or ""
    return pandoc.Link(el.content, target, title, el.attr)
  end

  local function replace_glossary_div(el)
    if el.identifier == "glossary" or has_class(el, "glossary") then
      return pandoc.Div(build_glossary_blocks(), el.attr)
    end
    return nil
  end

  return doc:walk({ Span = link_glossary_span, Div = replace_glossary_div })
end
