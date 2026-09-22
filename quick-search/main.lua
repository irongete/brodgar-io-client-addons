-- Entry point: the hotkey that opens the field, the characters whose menus are read, and startup. The two
-- that walk the results are declared with the field, in window.lua.

local Catalogue = QuickSearch.Catalogue
local Window = QuickSearch.Window

local DEFAULT_KEY = "Ctrl+Space"

-- A hotkey fires in the character's tree; the field stands in the addon layer, so the toggle goes on the
-- next step. It fires while the field has the keyboard too: a text field leaves this key unhandled, and an
-- unhandled key falls through to the game's global keys.
local keybindings = hafen.client():options():keybindings()
keybindings:on("toggle", function()
  hafen.timer():after(0, function()
    if Window.isOpen() then
      Window.close()
    else
      Window.open()
    end
  end)
end)

-- An addon hotkey starts unbound. The key is written once, while the user has never touched the binding,
-- and is written as the user's own, so a later change or an unbinding in Options > Game > Keybindings >
-- Quick Search stands.
local toggleBinding = keybindings:binding():get("toggle")
if not toggleBinding:assigned() then
  toggleBinding:key(DEFAULT_KEY)
end

hafen.event():on("SessionEnteredWorld", Catalogue.build)
hafen.event():on("SessionRemoved", function(session)
  Catalogue.forget(session)
  Window.close()
end)
hafen.timer():every(Catalogue.REFRESH_SECONDS, Catalogue.refresh)

-- An addon enabled while characters are already in the world receives no event for them.
for _, session in ipairs(hafen.session():list()) do
  if session:ui():match("@GameUI") then
    Catalogue.build(session)
  end
end
