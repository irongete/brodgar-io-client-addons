-- HUD: the character's health, stamina and energy drawn as three bars of the addon's own, in place of
-- the client's meters.
--
-- The manifest runs the files in order into one environment; each adds its module under `HUD`:
--   config.lua   constants, the three bar definitions, their options and where each bar stands (this file)
--   meters.lua   the client's meters: finding one, hiding it, and the amount the server states for it
--   bars.lua     the widgets: what a bar draws and the ALT drag that moves it
--   options.lua  the Options > AddOns > HUD page
--   main.lua     events and startup

HUD = {}

local Config = {}
HUD.Config = Config

-- What a bar can write across itself. Only health offers the choice: it is the only meter the server
-- states an amount for, in a tip that reads "Health: 87% (35/40)".
Config.READING_PERCENTAGE = "Percentage"
Config.READING_BOTH       = "Percentage and amount"
Config.READING_AMOUNT     = "Amount"
Config.READING_NOTHING    = "Nothing"

local READING_CHOICES = {
  Config.READING_PERCENTAGE,
  Config.READING_BOTH,
  Config.READING_AMOUNT,
  Config.READING_NOTHING,
}

Config.DEFAULT_X = 20                        -- where a bar stands until it is dragged

local DEFAULT_WIDTH     = 180
local DEFAULT_HEIGHT    = 16
local DEFAULT_BORDER    = 1
local DEFAULT_FONT_SIZE = 10                 -- the size the client's own stock text is set in
local WIDTH_RANGE       = {40, 600}
local HEIGHT_RANGE      = {4, 48}
local BORDER_RANGE      = {0, 8}
local FONT_SIZE_RANGE   = {6, 32}

Config.TROUGH_COLOUR      = {0, 0, 0, 178}   -- the empty part of a bar
Config.BORDER_COLOUR      = {0, 0, 0, 255}   -- solid, so the line reads as a line and not a tint
Config.HANDLE_COLOUR      = {255, 236, 140}  -- that line while ALT is held
Config.TEXT_COLOUR        = {255, 255, 255}
Config.TEXT_SHADOW_COLOUR = {0, 0, 0, 255}
Config.TEXT_FONT_FAMILY   = "sans"           -- the client's own face, so a bar matches the text beside it
Config.TEXT_ROOM          = 3                -- design pixels a bar needs over the font size to fit the line

-- The bars, in the order they are drawn and listed on the options page. `resource` is the name the server
-- gives the meter; `defaultColour` is where the R/G/B sliders start.
Config.BARS = {
  {
    key           = "health",
    caption       = "Health",
    resource      = "gfx/hud/meter/hp",
    defaultColour = {202, 44, 44},
    defaultY      = 90,
    offersReading = true,
  },
  {
    key           = "stamina",
    caption       = "Stamina",
    resource      = "gfx/hud/meter/stam",
    defaultColour = {224, 200, 48},
    defaultY      = 112,
  },
  {
    key           = "energy",
    caption       = "Energy",
    resource      = "gfx/hud/meter/nrj",
    defaultColour = {96, 150, 232},
    defaultY      = 134,
  },
}

Config.options = hafen.client():options():addon()
Config.enabledOption = Config.options:boolean("enabled"):default(false):add()

-- One set of options per bar, named by the bar's key so the client keeps them apart.
for _, bar in ipairs(Config.BARS) do
  bar.widthOption = Config.options:number(bar.key .. "-width")
    :range(WIDTH_RANGE[1], WIDTH_RANGE[2]):default(DEFAULT_WIDTH):add()
  bar.heightOption = Config.options:number(bar.key .. "-height")
    :range(HEIGHT_RANGE[1], HEIGHT_RANGE[2]):default(DEFAULT_HEIGHT):add()
  bar.borderOption = Config.options:number(bar.key .. "-border")
    :range(BORDER_RANGE[1], BORDER_RANGE[2]):default(DEFAULT_BORDER):add()
  bar.fontSizeOption = Config.options:number(bar.key .. "-font-size")
    :range(FONT_SIZE_RANGE[1], FONT_SIZE_RANGE[2]):default(DEFAULT_FONT_SIZE):add()
  if bar.offersReading then
    bar.readingOption = Config.options:choice(bar.key .. "-reading")
      :choices(READING_CHOICES):default(Config.READING_PERCENTAGE):add()
  end
  bar.gameColourOption = Config.options:boolean(bar.key .. "-game-colour")
    :default(true):add()
  bar.redOption = Config.options:number(bar.key .. "-red")
    :range(0, 255):default(bar.defaultColour[1]):add()
  bar.greenOption = Config.options:number(bar.key .. "-green")
    :range(0, 255):default(bar.defaultColour[2]):add()
  bar.blueOption = Config.options:number(bar.key .. "-blue")
    :range(0, 255):default(bar.defaultColour[3]):add()
end

-- Where each bar was dropped: one place per bar for the account, like every other setting here.
local savedPlacements = hafen.store():var("placement")

-- nil when nothing usable is saved, so the caller falls back to the bar's default place.
function Config.placementOf(bar)
  local placement = savedPlacements[bar.key]
  if type(placement) ~= "table" then return nil end
  if (type(placement.x) ~= "number") or (type(placement.y) ~= "number") then return nil end
  return placement
end

function Config.rememberPlacement(bar, x, y)
  savedPlacements[bar.key] = {x = x, y = y}
  hafen.store():flush()
end
