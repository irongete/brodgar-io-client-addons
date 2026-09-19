-- One stroke, from the press on the map to the release. While a stroke is live the pointer is read on every
-- Update and raycast to the ground, one raycast in flight at a time; a sample far enough from the last lays a
-- segment (and a round join where the stroke turned) or, under the eraser, sweeps the marks.

local Brush = Paint.Brush
local Geometry = Paint.Geometry
local Sheet = Paint.Sheet

local Stroke = {}
Paint.Stroke = Stroke

local STRAIGHT_COS = 0.985 -- two segments turning by less than about ten degrees open no wedge: no join
local PARENT_HOPS = 16     -- how far up the widget tree the map view is looked for

local current = nil -- the stroke being drawn, while one is

-- The session on screen, once its character is in the world.
local function worldSession()
  local session = hafen.session():current()
  return session and session:world() and session or nil
end

function Stroke.isLive()
  return current ~= nil
end

local function layJoint(stroke, center)
  local ring, radius = Geometry.jointRing(center, Brush.halfWidth())
  stroke.record = Sheet.lay(stroke.record, stroke.color, ring, Geometry.JOIN_EDGES,
                            {center = center, halfX = 0, halfY = 0, radius = radius})
end

-- One landed raycast: the ground point under the pointer, or nil where there is none.
local function sample(stroke, position)
  if position == nil then return end
  local x, y = position:x(), position:y()
  if (x == nil) or (y == nil) then return end
  if stroke.lastPosition == nil then
    stroke.lastPosition, stroke.lastX, stroke.lastY = position, x, y
    if stroke.eraser then Sheet.rub(x, y, Brush.rubRadius()) end
    return
  end
  local deltaX, deltaY = x - stroke.lastX, y - stroke.lastY
  local travelled = math.sqrt((deltaX * deltaX) + (deltaY * deltaY))
  if stroke.eraser then
    if travelled < Brush.rubStep() then return end
    Sheet.rub(x, y, Brush.rubRadius())
    stroke.lastPosition, stroke.lastX, stroke.lastY = position, x, y
    return
  end
  if travelled < Brush.sampleStep() then return end
  local ring, _, directionX, directionY = Geometry.segmentRing(
    stroke.lastPosition, stroke.lastX, stroke.lastY, position, x, y, Brush.halfWidth())
  if ring == nil then return end

  -- The first segment starts with the stroke's round cap; a later one gets a join where the stroke turned.
  if stroke.directionX == nil then
    layJoint(stroke, stroke.lastPosition)
  elseif ((stroke.directionX * directionX) + (stroke.directionY * directionY)) < STRAIGHT_COS then
    layJoint(stroke, stroke.lastPosition)
  end
  stroke.record = Sheet.lay(stroke.record, stroke.color, ring, Geometry.SEGMENT_EDGES, {
    center = stroke.lastPosition:offset(deltaX / 2, deltaY / 2),
    halfX = deltaX / 2,
    halfY = deltaY / 2,
    radius = Brush.halfWidth(),
  })

  stroke.lastPosition, stroke.lastX, stroke.lastY = position, x, y
  stroke.directionX, stroke.directionY = directionX, directionY
end

function Stroke.finish()
  local stroke = current
  if stroke == nil then return end
  -- The far end's round cap. A press that never moved has no direction and lays nothing.
  if (not stroke.eraser) and (stroke.directionX ~= nil) and (stroke.lastPosition ~= nil) then
    pcall(function() layJoint(stroke, stroke.lastPosition) end)
  end
  current = nil
  if stroke.updateSub then pcall(function() stroke.updateSub:off() end) end
end

-- Start a stroke with the picked tool, on the session on screen. The client offers the button's release to
-- the map view's tree only (a mouse grab on the addon layer never sees it), so the pointer is read on every
-- Update and the release is the map view's own MouseUp (main.lua). The pointer leaving the map ends the
-- stroke too.
function Stroke.begin()
  local session = worldSession()
  if (session == nil) or (Brush.tool == nil) then return end
  Stroke.finish()
  local mouse = hafen.ui():mouse()
  local eraser = Brush.isEraser()
  local stroke = {
    eraser = eraser,
    color = (not eraser) and Brush.PENCILS[Brush.tool].color or nil,
    raycastPending = false,
    mapView = session:ui():match("@MapView"),
  }
  current = stroke

  -- screenToWorld answers a frame later; the answer is sampled only into the stroke that asked.
  local function raycast(screenX, screenY)
    if stroke.raycastPending then return end
    stroke.raycastPending = true
    session:world():screenToWorld({x = screenX, y = screenY}, function(position)
      stroke.raycastPending = false
      if current == stroke then sample(stroke, position) end
    end)
  end

  -- The widget under the pointer can be a child of the map view, so the tree is walked upwards.
  local function isOnMap(widget)
    local node, hops = widget, 0
    while (node ~= nil) and (hops < PARENT_HOPS) do
      if node == stroke.mapView then return true end
      node = node:parent()
      hops = hops + 1
    end
    return false
  end

  stroke.updateSub = hafen.event():on("Update", function()
    if current ~= stroke then return end
    local over = mouse:over()
    if (over ~= nil) and not isOnMap(over) then
      Stroke.finish()
      return
    end
    raycast(mouse:x(), mouse:y())
  end)
  raycast(mouse:x(), mouse:y())
end
