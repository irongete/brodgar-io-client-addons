-- Hider: takes the kinds of object the user ticked out of the scene with gob:visible(false) and lays a
-- patch on the ground each of them stands on. Toggled per session with the key assigned in
-- Options > Game > Keybindings > Hider.
--
-- The manifest runs the files in order into one environment; each adds its module under `Hider`:
--   kinds.lua     what can be hidden, and which kind a resource name belongs to (this file)
--   options.lua   the options and the Options > AddOns page: the ticks and the patch's colours
--   main.lua      hiding, the patches, the hotkey and the world events

Hider = {}

local function startsWith(resourceName, prefix)
  return resourceName:sub(1, #prefix) == prefix
end

local function endsWith(resourceName, suffix)
  return resourceName:sub(-#suffix) == suffix
end

local function under(prefix)
  return function(resourceName) return startsWith(resourceName, prefix) end
end

local function exactly(name)
  return function(resourceName) return resourceName == name end
end

local TREES = "gfx/terobjs/trees/"

-- A felled tree stays in the trees folder, so the three tree kinds are told apart by the ending.
local function isStanding(resourceName)
  return startsWith(resourceName, TREES)
     and not (endsWith(resourceName, "stump") or endsWith(resourceName, "log")
              or endsWith(resourceName, "oldtrunk"))
end

-- A felled tree is either a log of its own or one of the trees folder's own log and trunk resources.
local function isFelled(resourceName)
  if resourceName == "gfx/terobjs/log" then return true end
  return startsWith(resourceName, TREES)
     and (endsWith(resourceName, "log") or endsWith(resourceName, "oldtrunk"))
end

local function isStump(resourceName)
  return startsWith(resourceName, TREES) and endsWith(resourceName, "stump")
end

-- `option` is the name the tick is stored under and `matches` reads gob:name(), the resource name the
-- server sent. The order is the order of the checkboxes on the page.
Hider.KINDS = {
  {option = "trees", label = "Trees", default = true,
   tooltip = "every tree still standing", matches = isStanding},
  {option = "logs", label = "Logs and trunks", default = false,
   tooltip = "felled trees lying on the ground", matches = isFelled},
  {option = "stumps", label = "Stumps", default = false,
   tooltip = "what a felled tree leaves in the ground", matches = isStump},
  {option = "bushes", label = "Bushes", default = true,
   tooltip = "bushes and the berries on them", matches = under("gfx/terobjs/bushes/")},
  {option = "boulders", label = "Boulders", default = false,
   tooltip = "the rocks and boulders lying about", matches = under("gfx/terobjs/bumlings")},
  {option = "stockpiles", label = "Stockpiles", default = false,
   tooltip = "the piles of board, stone, branch and the rest", matches = under("gfx/terobjs/stockpile-")},
  {option = "palisades", label = "Palisade walls", default = false,
   tooltip = "the wall between two palisade corners", matches = exactly("gfx/terobjs/arch/palisadeseg")},
  {option = "palisade-posts", label = "Palisade corners", default = false,
   tooltip = "the corner posts a palisade runs between", matches = exactly("gfx/terobjs/arch/palisadecp")},
  {option = "brick-walls", label = "Brick walls", default = false,
   tooltip = "the wall between two brick corners", matches = exactly("gfx/terobjs/arch/brickwallseg")},
  {option = "brick-wall-posts", label = "Brick wall corners", default = false,
   tooltip = "the corner posts a brick wall runs between", matches = exactly("gfx/terobjs/arch/brickwallcp")},
  {option = "dry-stone-walls", label = "Dry stone fences", default = false,
   tooltip = "the fence between two dry stone corners", matches = exactly("gfx/terobjs/arch/drystonewallseg")},
  {option = "dry-stone-posts", label = "Dry stone corners", default = false,
   tooltip = "the corner posts a dry stone fence runs between",
   matches = exactly("gfx/terobjs/arch/drystonewallcp")},
  {option = "pole-fences", label = "Pole fences", default = false,
   tooltip = "the fence between two pole corners", matches = exactly("gfx/terobjs/arch/poleseg")},
  {option = "pole-fence-posts", label = "Pole fence corners", default = false,
   tooltip = "the corner posts a pole fence runs between", matches = exactly("gfx/terobjs/arch/polecp")},
}

-- The kind a resource name belongs to, or nil for one no kind names.
function Hider.kindOf(resourceName)
  for _, kind in ipairs(Hider.KINDS) do
    if kind.matches(resourceName) then return kind end
  end
  return nil
end
