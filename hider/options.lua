-- The options and the page in Options > AddOns > Hider: one checkbox per kind, and the four rows that
-- dress the patch laid on the ground.

local Options = {}
Hider.Options = Options

-- The client draws no colour well, so a colour is picked by name here and looked up when a patch is dressed.
local COLOURS = {
  {"yellow", {255, 225,  60}},
  {"orange", {255, 150,  40}},
  {"red",    {255,  70,  70}},
  {"pink",   {255, 120, 200}},
  {"purple", {170, 110, 255}},
  {"blue",   { 60, 140, 255}},
  {"sky",    {120, 190, 255}},
  {"teal",   { 40, 210, 200}},
  {"green",  { 70, 220, 110}},
  {"white",  {255, 255, 255}},
  {"grey",   {150, 150, 150}},
  {"black",  {  0,   0,   0}},
}

local COLOUR_NAMES, COLOUR_RGB = {}, {}
for index, entry in ipairs(COLOURS) do
  COLOUR_NAMES[index] = entry[1]
  COLOUR_RGB[entry[1]] = entry[2]
end

local addonOptions = hafen.client():options():addon()

local kindToggles = {}      -- [kind] = the boolean option carrying its tick
for _, kind in ipairs(Hider.KINDS) do
  kindToggles[kind] = addonOptions:boolean(kind.option):default(kind.default):add()
end

local fillOption = addonOptions:choice("fill"):choices(COLOUR_NAMES):default("yellow"):add()
local opacityOption = addonOptions:number("opacity"):range(0, 100):default(50):add()
local borderOption = addonOptions:choice("border"):choices(COLOUR_NAMES):default("yellow"):add()
local borderWidthOption = addonOptions:number("border-width"):range(0, 200):default(60):add()

local lookOptions = {fillOption, opacityOption, borderOption, borderWidthOption}

-- A colour name the palette no longer carries falls back to the option's default.
local function colourOf(option)
  return COLOUR_RGB[option:value()] or COLOUR_RGB[option:default()]
end

function Options.hides(kind)
  return kindToggles[kind]:value()
end

-- On a patch the tint is the fill, so its fourth component is the fill's own opacity.
function Options.fillColour()
  local colour = colourOf(fillOption)
  local alpha = math.floor(((opacityOption:value() * 255) / 100) + 0.5)
  return {colour[1], colour[2], colour[3], alpha}
end

function Options.borderColour()
  return colourOf(borderOption)
end

-- The rows carry hundredths of a world unit; patch:border() takes world units.
function Options.borderWidth()
  return borderWidthOption:value() / 100
end

function Options.onKindsChanged(callback)
  for _, option in pairs(kindToggles) do option:on("Changed", callback) end
end

function Options.onLookChanged(callback)
  for _, option in ipairs(lookOptions) do option:on("Changed", callback) end
end

-- A slider shows no number, so its label carries the value.
local function addSlider(root, caption, option, tooltip)
  local label = hafen.ui():label():parent(root):text(caption .. ": " .. option:value())
  local slider = hafen.ui():slider():parent(root):size(160):tooltip(tooltip):bind(option)
  slider:on("Changed", function(event) label:text(caption .. ": " .. event:value()) end)
end

local function addDropdown(root, caption, option, tooltip)
  hafen.ui():label():parent(root):text(caption)
  hafen.ui():dropdown():parent(root):size(120):tooltip(tooltip):bind(option)
end

addonOptions:panel(function(root)
  root:gap(4)
  hafen.ui():label():parent(root):text("What the key hides")
  for _, kind in ipairs(Hider.KINDS) do
    hafen.ui():check():parent(root):text(kind.label):tooltip(kind.tooltip):bind(kindToggles[kind])
  end
  hafen.ui():label():parent(root):text("The patch on the ground")
  addDropdown(root, "Fill colour", fillOption, "the colour laid over the ground a hidden object stands on")
  addSlider(root, "Fill opacity", opacityOption,
            "per cent: how much of the ground shows through the fill. 0 leaves only the border")
  addDropdown(root, "Border colour", borderOption, "the line round the patch, always solid")
  addSlider(root, "Border thickness", borderWidthOption,
            "hundredths of a world unit, a tile is 11 units. 0 is the thinnest line the screen can draw; " ..
            "to hide the border, give it the fill's colour")
end)
