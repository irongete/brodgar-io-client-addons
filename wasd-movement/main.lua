-- WASD Movement: walks the character in the direction the camera is looking.
--
-- While a key is held, a poll reads which keys are down, turns them into a screen direction, rotates it
-- by the camera bearing and sends one long move order along it. The server walks the rest, so a held
-- key costs one order rather than one per frame. A new order goes out only when the bearing changes;
-- releasing the last key sends a stop.
--
-- Keys are polled with binding:down() instead of counting hotkey fires: a hotkey only reports the key
-- going down, and the OS auto-repeat only repeats the last key pressed, so diagonals would be missed.

local TILE = 11                     -- world units per tile (client constant)
local REACH = 100 * TILE            -- how far ahead each move order aims; longer than any key hold
local PROBE = TILE                  -- length of the probes used to read the camera off the projection
local TICK = 0.05                   -- seconds between polls while a key is held
local TURN_EPS = math.pi / 45       -- 4 degrees; a smaller bearing change is not worth a new order
local ESCAPE = 27                   -- key code that "gk" carries for an Escape keypress

local keybindings = hafen.client():options():keybindings()

-- One hotkey row (Options > Keybindings) per key, as a screen direction: up is towards the top of the
-- screen. Held keys are summed, so W+D is (1, 1) and W+S cancels to nothing.
local DIRECTIONS = {
  {name = "Forward (W)", up =  1, right =  0},
  {name = "Left (A)",    up =  0, right = -1},
  {name = "Back (S)",    up = -1, right =  0},
  {name = "Right (D)",   up =  0, right =  1},
}

local bindings = {}                 -- Binding object per row, for :down()
local moving = nil                  -- last order sent: {session=, bearing=}; nil while stopped
local poll = nil                    -- the poll timer; nil while no key is held

-- World bearing (radians) that points straight up the screen: the camera's forward, flat on the ground.
-- The camera angle is not exposed to addons, so it is read off the projection: project the origin, a
-- probe east and a probe south, invert the resulting 2x2 world-to-screen matrix and ask which world step
-- maps to screen (0, -1). Works for every camera mode at any rotation, elevation and zoom.
local function screenUpBearing(session, origin)
  local world = session:world()
  local originPoint = world:worldToScreen(origin)
  local eastPoint = world:worldToScreen(origin:offset(PROBE, 0))
  local southPoint = world:worldToScreen(origin:offset(0, PROBE))
  if not (originPoint and eastPoint and southPoint) then return nil end

  local eastX, eastY = eastPoint.x - originPoint.x, eastPoint.y - originPoint.y
  local southX, southY = southPoint.x - originPoint.x, southPoint.y - originPoint.y
  local det = eastX * southY - southX * eastY
  if math.abs(det) < 1e-6 then return nil end   -- ground seen edge-on, not invertible

  -- Inverse matrix applied to (0, -1); screen y grows downwards.
  return math.atan2(-eastX / det, southX / det)
end

-- Signed angle from `reference` to `bearing`, normalised to (-pi, pi].
local function angleBetween(bearing, reference)
  local delta = (bearing - reference) % (2 * math.pi)
  if delta > math.pi then delta = delta - 2 * math.pi end
  return delta
end

-- Direction of the held keys as an angle off screen-up (radians, clockwise), or nil when no key is held
-- or the held keys cancel out.
local function heldDirection()
  local up, right = 0, 0
  for _, direction in ipairs(DIRECTIONS) do
    if bindings[direction.name]:down() then
      up = up + direction.up
      right = right + direction.right
    end
  end
  if up == 0 and right == 0 then return nil end
  return math.atan2(right, up)
end

-- Stop the character where it stands by sending the "gk" message an Escape keypress produces; the server
-- reads it as "cancel the current action". A move to the character's own position is not a stop: the
-- character keeps walking while the order is in flight and then steps back to the old point.
local function halt(session)
  local root = session and session:exists() and session:ui():root()
  if root then root:send("gk", ESCAPE, 0) end
end

local function stopPolling()
  if poll then poll:cancel() end
  poll = nil
end

-- No key held: stop polling and halt whatever was sent.
local function release()
  stopPolling()
  if moving then
    local session = moving.session
    moving = nil
    halt(session)
  end
end

-- Send one move order from the character's current position along `bearing`.
local function walk(session, gob, bearing)
  local origin = gob:position()
  local target = origin and origin:offset(math.cos(bearing) * REACH, math.sin(bearing) * REACH)
  if not target then return false end
  session:player():move(target)
  return true
end

-- One poll: read the keys and the camera, send a new order only if the bearing changed. Runs on the
-- step (timer), so it may reach any session's tree.
local function tick()
  local direction = heldDirection()
  if not direction then release(); return end          -- last key released

  local session = hafen.session():current()
  local gob = session and session:player():gob()
  local origin = gob and gob:position()
  if not origin then return end                        -- no character on screen

  local cameraBearing = screenUpBearing(session, origin)
  if not cameraBearing then return end
  local bearing = cameraBearing + direction

  if moving and moving.session ~= session then
    halt(moving.session)                               -- the screen moved to another session
    moving = nil
  end
  if moving and math.abs(angleBetween(bearing, moving.bearing)) < TURN_EPS then
    return                                             -- same order as the last one sent
  end
  if walk(session, gob, bearing) then
    moving = {session = session, bearing = bearing}
  end
end

-- The hotkey declares the keybinding row and starts the poll; the poll stops itself once nothing is
-- held. A hotkey handler runs inside the drawn character's tree, so the first tick is deferred to the
-- step with after(0). Later presses while polling are picked up by the next tick.
for _, direction in ipairs(DIRECTIONS) do
  keybindings:on(direction.name, function()
    if poll then return end
    poll = hafen.timer():every(TICK, tick)
    hafen.timer():after(0, tick)
  end)
  bindings[direction.name] = keybindings:binding():get(direction.name)
end

-- A reload or disable must not leave the character walking with nothing left to stop it.
hafen.event():on("Disable", release)

hafen.event():on("SessionRemoved", function(session)
  if moving and moving.session == session then moving = nil end   -- nothing to halt: it is gone
end)
