-- Entry point: what is wired to each character in the world, the map view subscriptions that start and end a
-- stroke and the Paint button in the action menu.

local Brush = Paint.Brush
local Stroke = Paint.Stroke
local Window = Paint.Window

local MENU_ID = "paint"                               -- the entry's identity is addon/paint/paint
local MENU_RES = "addon/" .. ADDON.id .. "/" .. MENU_ID

local mapSubscriptions = {} -- [account] = the MouseDown and MouseUp subscriptions on that session's map view
local menuIcon = nil        -- icon.png, loaded on first use

-- While a tool is picked, a press on the map of the session on screen is the addon's and is cancelled: a
-- left press starts a stroke, so the client neither walks the character nor pans the camera; a right press
-- puts the tool down. The release ends the stroke and is left to the client.
local function watchMap(session)
  local previous = mapSubscriptions[session:user()]
  if previous then
    for _, subscription in ipairs(previous) do pcall(function() subscription:off() end) end
  end
  local mapView = session:ui():match("@MapView")
  if mapView == nil then return end

  local function isOnScreen()
    local current = hafen.session():current()
    return (current ~= nil) and (current:user() == session:user())
  end

  mapSubscriptions[session:user()] = {
    mapView:on("MouseDown", function(event)
      if (Brush.tool == nil) or (not isOnScreen()) then return end
      if event:button() == 1 then
        event:preventDefault()
        Stroke.begin()
      elseif event:button() == 3 then
        event:preventDefault()
        hafen.timer():after(0, Window.disarm) -- deferred: the press runs under the map view's tree
      end
    end),
    mapView:on("MouseUp", function(event)
      if (not Stroke.isLive()) or (event:button() ~= 1) then return end
      Stroke.finish()
    end),
  }
end

-- The Paint button in the character's action menu, opening and closing the window. A character gets a new
-- menu at every entry into the world, so the button is added again each time; one already there (a :reload
-- with the character in the world) is kept.
local function addMenuButton(session)
  if session:world() == nil then return end
  local ok, err = pcall(function()
    local menugrid = session:menugrid()
    if menugrid:get(MENU_RES) ~= nil then return end
    if menuIcon == nil then menuIcon = hafen.asset():get("icon.png") end
    local entry = menugrid:add(MENU_ID):name(Paint.NAME):tooltip("Draw on the ground with the mouse")
    entry:icon(menuIcon)
    entry:on("Pressed", function() -- deferred: the press runs under the menu's tree
      hafen.timer():after(0, function() Window.show(not Window.isOpen) end)
    end)
  end)
  if not ok then hafen.log():write(Paint.NAME .. ": " .. tostring(err)) end
end

local function wire(session)
  watchMap(session)
  addMenuButton(session)
end

hafen.event():on("SessionEnteredWorld", wire)
for _, session in ipairs(hafen.session():list()) do wire(session) end
