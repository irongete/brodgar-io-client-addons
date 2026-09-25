-- Brodgar UI: a pack of Simple Minimap, Simple Chat, Quick Search, Actionbars, Themes, Hider, Hitboxes and
-- Stockpile Take, set up to work together.
--
-- The manifest lists the eight as dependencies, so each has run by now. This file only says where two of them
-- start and which theme the client starts in, through the preset each exports; what the user changes
-- afterwards stays each addon's own to remember. A preset's numbers are screen pixels, the same on every
-- interface scale.

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

-- The look: the Simple theme, the client's own without the blackletter. Themes acts on it once, for a player
-- who has picked no theme; a theme picked before or after is the player's.
local themes = addons:get("themes"):api()
themes.preset{
  theme = "simple",
}

-- The rest take nothing: Quick Search opens its field in the middle of the screen, Actionbars starts its
-- first bar centred on the bottom edge, and Hider, Hitboxes and Stockpile Take are as their addons ship them.
