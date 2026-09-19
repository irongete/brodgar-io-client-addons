-- Alt-click on the map queues waypoints; the character walks them in order, one flag per pending
-- waypoint. One path per session. Every session's path is drawn over the drawn session's MapView:
-- a widget overlay paints before the client's windows, hafen.ui():overlay() would paint over them.

local FLAG_PATH = "flag.png"
local FLAG_SCALE = 1.2             -- world tiles
local ARRIVE_DISTANCE = 6          -- world units
local POLL_INTERVAL = 0.2          -- seconds
local STUCK_POLLS = 5              -- consecutive polls standing still before the path is dropped
local LINE_WIDTH = 2               -- design pixels
local OTHER_SESSION_ALPHA = 0.4    -- paths of sessions not on screen
local ALT_MODIFIER = 4             -- bit in a click's modflags: shift 1, ctrl 2, alt 4

local CURRENT_LEG_COLOR = {60, 230, 90, 220}
local QUEUED_LEG_COLOR = {245, 215, 60, 200}

local DEBUG = false                -- one log line per map click

local flagIcon
local pathsBySession = {}          -- [session] = {current = waypoint, queue = {waypoint...}, stoppedPolls = n}
local watchedSessions = {}         -- [session] = true while its MapView subscription is alive
local sendingOrder = false         -- an own move to the drawn session re-enters the "click" stream

hafen.event():on("Load", function()
  flagIcon = hafen.asset():get(FLAG_PATH)
end)

-- ---------------------------------------------------------------- waypoints

local function newWaypoint(position)
  local waypoint = {position = position}
  if flagIcon and position:durable() then   -- a sprite refuses a Position without a durable form
    waypoint.flag = hafen.virtual():sprite():add(flagIcon, position):facing("fixed"):scale(FLAG_SCALE)
  end
  return waypoint
end

local function removeFlag(waypoint)
  if waypoint and waypoint.flag then hafen.virtual():sprite():remove(waypoint.flag) end
end

local function clearPath(session)
  local path = pathsBySession[session]
  if not path then return end
  removeFlag(path.current)
  for _, waypoint in ipairs(path.queue) do removeFlag(waypoint) end
  pathsBySession[session] = nil
end

-- session:player():move raises for a session that is gone or a place that character cannot locate.
-- The path is dropped rather than left for the timer to hit the same error again.
local function walkTo(session, waypoint)
  sendingOrder = true
  local sent, failure = pcall(function() session:player():move(waypoint.position) end)
  sendingOrder = false
  if not sent then
    hafen.log():write("waypoints: " .. tostring(failure))
    clearPath(session)
  end
end

-- ---------------------------------------------------------------- drawing

-- viewX, viewY: the MapView's root position. worldToScreen answers root design pixels and the painter's
-- graphics is translated to the widget's top-left. It answers nil for a place the drawn session cannot
-- project, which drops that leg only.
local function drawPaths(graphics, viewX, viewY)
  local drawnSession = hafen.session():current()
  local drawnWorld = drawnSession and drawnSession:world()
  if not drawnWorld then return end

  for session, path in pairs(pathsBySession) do
    local playerGob = session:player():gob()
    local start = playerGob and playerGob:position()
    if start then
      local points = {start, path.current.position}
      for _, waypoint in ipairs(path.queue) do points[#points + 1] = waypoint.position end

      local screenPoints = {}
      for index, position in ipairs(points) do
        screenPoints[index] = drawnWorld:worldToScreen(position)
      end

      local alpha = (session == drawnSession) and 1 or OTHER_SESSION_ALPHA
      for index = 1, #points - 1 do
        local legStart, legEnd = screenPoints[index], screenPoints[index + 1]
        if legStart and legEnd then
          local color = (index == 1) and CURRENT_LEG_COLOR or QUEUED_LEG_COLOR
          graphics:color(color[1], color[2], color[3], math.floor(color[4] * alpha))
          graphics:line(legStart.x - viewX, legStart.y - viewY, legEnd.x - viewX, legEnd.y - viewY, LINE_WIDTH)
        end
      end
    end
  end
  graphics:color()
end

-- The overlay dies with its MapView; the subscription re-adds it on every MapView that session puts up
-- (a character switch keeps the session's UI). The subscription is bound to that UI, which a relogin
-- replaces, so SessionRemoved forgets the session and the next SessionEnteredWorld subscribes again.
local function watchMapView(session)
  if watchedSessions[session] then return end
  watchedSessions[session] = true
  session:ui():on("@MapView", "Added", function(mapView)
    mapView:overlay():add("path"):draw(function(graphics, width, height)
      local viewOrigin = mapView:rootPos()
      if viewOrigin then drawPaths(graphics, viewOrigin.x, viewOrigin.y) end
    end)
  end)
end

hafen.event():on("SessionEnteredWorld", watchMapView)

hafen.event():on("SessionRemoved", function(session)
  clearPath(session)
  watchedSessions[session] = nil
end)

-- ---------------------------------------------------------------- clicks

local function altHeld(modifierFlags)
  return math.floor(modifierFlags / ALT_MODIFIER) % 2 == 1
end

hafen.event():action():on("click", function(clickEvent)
  if sendingOrder then return end

  -- Avaview, ISBox and others send "click" too; only the MapView's carries a destination.
  local sender = clickEvent:widget()
  if not sender or sender:type() ~= "MapView" then return end
  local session = sender:session()
  if not session then return end

  -- MapView click args: {screen point, world point, button, modflags}; a click on an object appends
  -- its own arguments from index 5. Right-clicks never replace the walk, so they are left alone.
  local arguments = clickEvent:args()
  if arguments[3] ~= 1 then return end
  local destination = clickEvent:position(2)

  if DEBUG then
    hafen.log():write(string.format("waypoints: %s dest=(%d,%d) durable=%s",
      session:character() or session:user(),
      math.floor(destination:x() or 0), math.floor(destination:y() or 0), tostring(destination:durable())))
  end

  -- The click's own modflags, not hafen.ui():mouse(): the handler runs a frame after the press.
  if not altHeld(arguments[4] or 0) then
    clearPath(session)             -- the client's own walk (or interaction) replaces the queued path
    return
  end
  if arguments[5] ~= nil then return end   -- alt-click on an object stays the game's

  -- The client's click would carry the alt modifier; walkTo sends the same destination without it.
  clickEvent:preventDefault()
  local path = pathsBySession[session]
  if path then
    table.insert(path.queue, newWaypoint(destination))
  else
    path = {current = newWaypoint(destination), queue = {}, stoppedPolls = 0}
    pathsBySession[session] = path
    walkTo(session, path.current)
  end
end)

-- ---------------------------------------------------------------- walking

hafen.timer():every(POLL_INTERVAL, function()
  for session, path in pairs(pathsBySession) do
    local playerGob = session:player():gob()
    if playerGob then
      -- session:world():distance measures from that character; position:distance() measures from the drawn one.
      local distance = session:world():distance(path.current.position)
      if distance and distance < ARRIVE_DISTANCE then
        removeFlag(path.current)
        path.current = table.remove(path.queue, 1)
        path.stoppedPolls = 0
        if path.current then
          walkTo(session, path.current)
        else
          pathsBySession[session] = nil
        end
      elseif playerGob:moving() then
        path.stoppedPolls = 0
      else
        path.stoppedPolls = path.stoppedPolls + 1   -- blocked, or the server refused the walk
        if path.stoppedPolls >= STUCK_POLLS then clearPath(session) end
      end
    end
  end
end)
