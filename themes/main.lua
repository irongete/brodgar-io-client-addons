-- Themes: reads the JSON themes under themes/, offers them as one client option and installs the chosen
-- one as this addon's stylesheet. Disabling the addon drops the sheet and restores the client's own look.

-- hafen.asset() loads a file by path and cannot list a folder, so themes/index.json names the theme files.
local FOLDER = "themes/"
local INDEX  = FOLDER .. "index.json"

-- The option's default: default.json, the client's own look.
local DEFAULT = "default"

local themes = {}    -- name -> { name, file, title, rules }
local order  = {}    -- theme names, in index.json's order

local options     = hafen.client():options():addon()
local themeOption = nil  -- the choice option, declared once the folder has been read

-- Parses a JSON file of this addon into a table. Returns nil and a reason on failure.
local function readDocument(path)
  local parsed, result = pcall(function() return hafen.json():parse(hafen.asset():get(path):text()) end)
  if not parsed then return nil, tostring(result) end
  if type(result) ~= "table" then return nil, "the document is not an object" end
  return result
end

-- A theme is named by its file, lower-cased and without the .json extension.
local function nameOf(file)
  return (string.gsub(string.lower(file), "%.json$", ""))
end

-- Reads index.json and every theme it names into `themes` and `order`.
local function loadThemes()
  themes, order = {}, {}
  local index, indexError = readDocument(INDEX)
  if index == nil then
    hafen.log():write("themes: cannot read " .. INDEX .. " -- " .. indexError)
    return
  end
  local files = index.themes
  if type(files) ~= "table" then
    hafen.log():write("themes: " .. INDEX .. " names no themes -- it is"
      .. ' { "themes": ["default.json"] }, an array of the files in this folder')
    return
  end
  for position = 1, #files do
    local file = files[position]
    local name = (type(file) == "string") and nameOf(file) or nil
    if name == nil then
      hafen.log():write("themes: " .. INDEX .. "[" .. position .. "] is not a file name")
    elseif themes[name] ~= nil then
      hafen.log():write('themes: "' .. file .. '" is skipped -- "' .. name .. '" is already loaded')
    else
      local document, documentError = readDocument(FOLDER .. file)
      if document == nil then
        hafen.log():write('themes: "' .. file .. '" did not load -- ' .. documentError)
      elseif type(document.rules) ~= "table" then
        hafen.log():write('themes: "' .. file .. '" carries no "rules" object -- a theme is'
          .. ' { "name": …, "rules": { "<selector>": { <property>: <value> } } }')
      else
        themes[name] = {
          name  = name,
          file  = file,
          title = (type(document.name) == "string") and document.name or name,
          rules = document.rules,
        }
        order[#order + 1] = name
      end
    end
  end
end

-- Loads a theme's rules into this addon's sheet and installs it. A theme the sheet refuses is released
-- again, so the client never wears a partially loaded theme.
local function installTheme(name)
  local theme = themes[name]
  if theme == nil then return false, 'no theme called "' .. name .. '"' end
  local installed, failure = pcall(function() hafen.ui():sheet():load(theme.rules):install() end)
  if not installed then
    pcall(function() hafen.ui():sheet():release() end)
    return false, tostring(failure)
  end
  return true
end

-- Installing a sheet touches every character's widget tree, and a pick on the Options page arrives inside
-- another tree's handler; the work is deferred to the next tick, where no tree is held (api/threading.md).
local function deferred(action)
  hafen.timer():after(0, action)
end

-- Installs the theme an option value names and reports the outcome.
local function wear(name)
  local installed, failure = installTheme(name)
  if installed then
    hafen.log():write('themes: "' .. themes[name].title .. '" installed')
  else
    hafen.log():write('themes: "' .. name .. '" did not install -- ' .. failure)
  end
end

-- Declares the "theme" choice option over every loaded theme, in index order. The option is the only place
-- the chosen theme is kept; every change goes through its Changed event. With no theme loaded there is no
-- option, and the panel says so.
local function declareOption()
  if #order == 0 then return end
  local default = (themes[DEFAULT] ~= nil) and DEFAULT or order[1]
  themeOption = options:choice("theme"):choices(order):default(default):add()

  themeOption:on("Changed", function(name) deferred(function() wear(name) end) end)
end

-- Options > AddOns > Themes: a dropdown bound to the option. The panel is rebuilt on every visit.
options:panel(function(root)
  root:gap(4)
  if themeOption == nil then
    hafen.ui():label():parent(root):text("no theme loaded -- see " .. INDEX)
    return
  end
  hafen.ui():label():parent(root):text("Theme")
  hafen.ui():dropdown():parent(root):size(160)
    :tooltip('the look the client wears -- "' .. DEFAULT .. '" is the client\'s own')
    :bind(themeOption)
end)

-- Runs on every load, :reload included: the sheet does not outlive the addon, so the chosen theme is
-- installed again from the option's value.
hafen.event():on("Load", function()
  loadThemes()
  declareOption()
  if themeOption ~= nil then wear(themeOption:value()) end
end)

-- ---------------------------------------------------------------- presets

-- What a bundle -- an addon that lists this one in its dependencies -- may hand preset(): the theme the client
-- starts in. A bundle's file runs after this addon's Load, when the option is declared and a theme worn, so a
-- preset cannot be the option's default. It acts once instead, the first time it is called: a player who has
-- picked no theme gets it written as their pick, which the dropdown shows and Changed wears. A theme picked
-- before it, or after, is the player's and stays. The store remembers that a preset has acted.
local presetState = hafen.store():var("preset")   -- theme: the theme the first preset named

local function presetTheme(name)
  if type(name) ~= "string" then
    error('theme is the name of a theme this addon ships, such as "simple"', 0)
  end
  if themes[name] == nil then
    error('no theme called "' .. name .. '"', 0)
  end
  if presetState.theme ~= nil then
    return
  end
  presetState.theme = name
  hafen.store():flush()
  if themeOption:value() == themeOption:default() then
    themeOption:value(name)
  end
end

local PRESETS = {
  theme = presetTheme,
}

-- A key this version does not know is skipped with a log line, so a bundle written for a later version still
-- loads.
local function preset(values)
  if type(values) ~= "table" then
    error("preset takes a table: {theme = ...}", 0)
  end
  for key, value in pairs(values) do
    local apply = PRESETS[key]
    if apply then
      apply(value)
    else
      hafen.log():write("preset: '" .. tostring(key) .. "' is not one this version knows; skipped")
    end
  end
end

-- A client without the addons collection offers no exports: the client then starts in the theme picked.
pcall(function()
  hafen.client():addons():export({preset = preset})
end)
