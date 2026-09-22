-- WASD Movement: walks the character in the direction the camera is looking.
--
-- While a key is held, a poll reads which keys are down, turns them into a screen direction, rotates it by
-- the camera bearing and sends one move order along it. A new order goes out only when the bearing changes;
-- releasing the last key sends a stop.

local TILE = 11                      -- world units per tile (client constant)
local MOVE_DISTANCE = 100 * TILE     -- how far ahead each move order aims; longer than any key hold
local PROBE_DISTANCE = TILE          -- length of the probes used to read the camera off the projection
local POLL_INTERVAL = 0.05           -- seconds between polls while a key is held
local MIN_TURN = math.pi / 45        -- 4 degrees; a smaller bearing change sends no new order
local ESCAPE_KEY = 27                -- key code that "gk" carries for an Escape keypress

local keybindings = hafen.client():options():keybindings()

-- One keybinding row (Options > Game > Keybindings > WASD Movement) per key, as a screen direction: up is
-- towards the top of the screen. Held keys are summed, so W+D is (1, 1) and W+S cancels to nothing.
local DIRECTIONS = {
  {name = "Forward (W)", up =  1, right =  0},
  {name = "Left (A)",    up =  0, right = -1},
  {name = "Back (S)",    up = -1, right =  0},
  {name = "Right (D)",   up =  0, right =  1},
}

local bindings = {}       -- Binding object per row, for :down()
local lastOrder = nil     -- the order still being walked: {session = , bearing = }; nil while stopped
local pollTimer = nil     -- nil while no key is held

-- World bearing (radians) that points straight up the screen: the camera's forward, flat on the ground.
-- Read off the projection: project the character, a probe east and a probe south, invert the resulting
-- 2x2 world-to-screen matrix and ask which world step maps to screen (0, -1).
local function screenUpBearing(session, origin)
  local world = session:world()
  local originPoint = world:worldToScreen(origin)
  local eastPoint = world:worldToScreen(origin:offset(PROBE_DISTANCE, 0))
  local southPoint = world:worldToScreen(origin:offset(0, PROBE_DISTANCE))
  if not (originPoint and eastPoint and southPoint) then return nil end

  local eastX, eastY = eastPoint.x - originPoint.x, eastPoint.y - originPoint.y
  local southX, southY = southPoint.x - originPoint.x, southPoint.y - originPoint.y
  local determinant = eastX * southY - southX * eastY
  if math.abs(determinant) < 1e-6 then return nil end   -- ground seen edge-on, not invertible

  -- Inverse matrix applied to (0, -1); screen y grows downwards.
  return math.atan2(-eastX / determinant, southX / determinant)
end

-- Signed angle from `reference` to `bearing`, normalised to (-pi, pi].
local function angleBetween(bearing, reference)
  local delta = (bearing - reference) % (2 * math.pi)
  if delta > math.pi then delta = delta - 2 * math.pi end
  return delta
end

-- Direction of the held keys as an angle off screen-up (radians, clockwise), or nil when no key is held or
-- the held keys cancel out.
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

-- Stop the character where it stands with the "gk" message an Escape keypress produces; the server reads it
-- as "cancel the current action".
local function halt(session)
  local root = session and session:exists() and session:ui():root()
  if root then root:send("gk", ESCAPE_KEY, 0) end
end

local function stopPolling()
  if pollTimer then pollTimer:cancel() end
  pollTimer = nil
end

-- No key held: stop polling and halt whatever was sent.
local function stopWalking()
  stopPolling()
  if lastOrder then
    local session = lastOrder.session
    lastOrder = nil
    halt(session)
  end
end

-- Send one move order from the character's current position along `bearing`.
local function walk(session, playerGob, bearing)
  local origin = playerGob:position()
  local target = origin and origin:offset(math.cos(bearing) * MOVE_DISTANCE,
                                          math.sin(bearing) * MOVE_DISTANCE)
  if not target then return false end
  session:player():move(target)
  return true
end

-- One poll: read the keys and the camera, send a new order only if the bearing changed. Runs on the step
-- (timer), so it may reach any session's tree.
local function poll()
  local direction = heldDirection()
  if not direction then stopWalking(); return end      -- last key released

  local session = hafen.session():current()
  local playerGob = session and session:player():gob()
  local origin = playerGob and playerGob:position()
  if not origin then return end                        -- no character on screen

  local cameraBearing = screenUpBearing(session, origin)
  if not cameraBearing then return end
  local bearing = cameraBearing + direction

  if lastOrder and lastOrder.session ~= session then
    halt(lastOrder.session)                            -- the screen moved to another session
    lastOrder = nil
  end
  if lastOrder and math.abs(angleBetween(bearing, lastOrder.bearing)) < MIN_TURN then
    return                                             -- same order as the last one sent
  end
  if walk(session, playerGob, bearing) then
    lastOrder = {session = session, bearing = bearing}
  end
end

-- The hotkey declares the keybinding row and starts the poll; the poll stops itself once nothing is held. A
-- hotkey handler runs inside the drawn character's tree, so the first poll is deferred to the step.
for _, direction in ipairs(DIRECTIONS) do
  keybindings:on(direction.name, function()
    if pollTimer then return end
    pollTimer = hafen.timer():every(POLL_INTERVAL, poll)
    hafen.timer():after(0, poll)
  end)
  bindings[direction.name] = keybindings:binding():get(direction.name)
end

hafen.event():on("Disable", stopWalking)

hafen.event():on("SessionRemoved", function(session)
  if lastOrder and lastOrder.session == session then lastOrder = nil end   -- nothing to halt: it is gone
end)
