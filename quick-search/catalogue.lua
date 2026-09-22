-- Quick Search -- type part of an action's name and run it, without opening the action menu.
--
-- The manifest runs the files in order into one environment; each adds its module under `QuickSearch`:
--   catalogue.lua  a character's menu read into searchable entries, and the search over them (this file)
--   window.lua     the search field, the list under it and what a row does
--   main.lua       the hotkey, the character events and startup

QuickSearch = {}

local Catalogue = {}
QuickSearch.Catalogue = Catalogue

Catalogue.REFRESH_SECONDS = 2  -- how often a catalogue is checked against the menu it was read from

local catalogues = {}          -- session -> {entries, paginaCount, complete}; sessions are interned, so they key

-- The categories above an action, outermost first, as the menu shows them. `complete` is false when one of
-- them has no display name yet: its resource name stands in until the resource resolves.
local function categoriesOf(pagina)
  local names = {}
  local complete = true
  local parent = pagina:parent()
  while parent do
    local name = parent:name()
    if name == nil then
      complete = false
      name = parent:res()
    end
    table.insert(names, 1, name)
    parent = parent:parent()
  end
  return names, complete
end

-- One entry per action; an entry with children is a category and cannot be used. Sorted by category path
-- and then by name, so what sits under one category stands together in the results.
function Catalogue.build(session)
  local paginae = session:menugrid():list()
  local entries = {}
  local complete = true
  for _, pagina in ipairs(paginae) do
    local name = pagina:name()
    local children = pagina:children()
    if name == nil then
      complete = false
    elseif children == nil or children:count() == 0 then
      local categories, categoriesComplete = categoriesOf(pagina)
      complete = complete and categoriesComplete
      entries[#entries + 1] = {
        pagina = pagina,
        name = name,
        nameLower = name:lower(),
        categories = categories,
        categoryPathLower = table.concat(categories, " > "):lower(),
        resource = pagina:res(),
      }
    end
  end
  table.sort(entries, function(firstEntry, secondEntry)
    if firstEntry.categoryPathLower ~= secondEntry.categoryPathLower then
      return firstEntry.categoryPathLower < secondEntry.categoryPathLower
    end
    return firstEntry.nameLower < secondEntry.nameLower
  end)
  catalogues[session] = {entries = entries, paginaCount = #paginae, complete = complete}
end

-- Read the menu unless this character's catalogue is already in hand.
function Catalogue.ensure(session)
  if catalogues[session] == nil then
    Catalogue.build(session)
  end
end

function Catalogue.forget(session)
  catalogues[session] = nil
end

-- No event reports a change in the menu, so its length is polled, one read per character. A catalogue with
-- names still missing is built again until every resource has resolved.
function Catalogue.refresh()
  for session, catalogue in pairs(catalogues) do
    if not session:exists() then
      catalogues[session] = nil
    elseif not catalogue.complete or session:menugrid():count() ~= catalogue.paginaCount then
      Catalogue.build(session)
    end
  end
end

-- The entries whose name contains `query` first, then those under a category that does, each set in
-- catalogue order: typing a category's name lists what is inside it. `query` is lowercase, matched as plain
-- text. Empty while the character's menu has not been read.
function Catalogue.search(session, query)
  local catalogue = catalogues[session]
  if catalogue == nil then
    return {}
  end
  local byName = {}
  local byCategory = {}
  for _, entry in ipairs(catalogue.entries) do
    if entry.nameLower:find(query, 1, true) then
      byName[#byName + 1] = entry
    elseif entry.categoryPathLower:find(query, 1, true) then
      byCategory[#byCategory + 1] = entry
    end
  end
  for _, entry in ipairs(byCategory) do
    byName[#byName + 1] = entry
  end
  return byName
end
