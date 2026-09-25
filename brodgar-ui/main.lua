-- Brodgar UI: a pack of Simple Minimap, Simple Chat, Quick Search and Actionbars, set up to work together.
--
-- The manifest lists the four as dependencies, so each has run by now. This file only says where two of them
-- start, through the preset each exports; where the user moves or sizes them afterwards stays each addon's own
-- to remember. A preset's numbers are screen pixels, the same on every interface scale.

local addons = hafen.client():addons()

-- The minimap: the screen's top-right corner, with the map 300 px square.
local simpleMinimap = addons:get("simple-minimap"):api()
simpleMinimap.preset{
  place = {at = "topright", offset = {-8, 8}},
  mapSize = {width = 300, height = 300},
}

-- The chat: the screen's bottom-right corner, at Simple Chat's own size.
local simpleChat = addons:get("simple-chat"):api()
simpleChat.preset{
  place = {at = "bottomright", offset = {-8, -8}},
}

-- The search and the action bars take nothing: Quick Search opens its field in the middle of the screen, and
-- Actionbars starts its first bar centred on the bottom edge.
