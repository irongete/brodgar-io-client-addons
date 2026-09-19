-- The convex rings a stroke is built from, and the distance test the eraser uses. Pure geometry: nothing here
-- touches the ground. A ring is an array of Positions; a piece of a patch is one convex ring.

local Geometry = {}
Paint.Geometry = Geometry

Geometry.SEGMENT_EDGES = 4
Geometry.JOIN_EDGES = 8 -- sides of a round join

-- The join's radius over the half-width. A polygon's flats sit nearer the centre than its corners, so a ring
-- of the bare half-width would notch the segments it joins.
local JOIN_RADIUS_FACTOR = 1.09

-- How far a segment overruns each endpoint, so two pieces never share a boundary.
local WELD = 0.05

-- The rectangle from `from` to `to`, `halfWidth` to each side and WELD past each end, with no cap: the round
-- join covers the corners and the ends of a stroke. Returns the ring, the length and the unit direction, or
-- nil for a segment with no length.
function Geometry.segmentRing(from, fromX, fromY, to, toX, toY, halfWidth)
  local deltaX, deltaY = toX - fromX, toY - fromY
  local length = math.sqrt((deltaX * deltaX) + (deltaY * deltaY))
  if length < 1e-6 then return nil end
  local directionX, directionY = deltaX / length, deltaY / length
  local alongX, alongY = directionX * WELD, directionY * WELD
  local acrossX, acrossY = -directionY * halfWidth, directionX * halfWidth
  local ring = {
    from:offset(-alongX + acrossX, -alongY + acrossY),
    to:offset(alongX + acrossX, alongY + acrossY),
    to:offset(alongX - acrossX, alongY - acrossY),
    from:offset(-alongX - acrossX, -alongY - acrossY),
  }
  return ring, length, directionX, directionY
end

-- A regular polygon round `center`. It fills the wedge two segments leave open on the outside of a turn, and
-- caps the two ends of a stroke. Returns the ring and its radius.
function Geometry.jointRing(center, halfWidth)
  local radius = halfWidth * JOIN_RADIUS_FACTOR
  local ring = {}
  for side = 1, Geometry.JOIN_EDGES do
    local angle = (2 * math.pi * (side - 1)) / Geometry.JOIN_EDGES
    ring[side] = center:offset(math.cos(angle) * radius, math.sin(angle) * radius)
  end
  return ring, radius
end

-- The distance from (pointX, pointY) to the segment centred at (centerX, centerY) that reaches (halfX, halfY)
-- each way. With a zero half-vector it is the plain distance to the centre.
function Geometry.axisDistance(pointX, pointY, centerX, centerY, halfX, halfY)
  local lengthSquared = (halfX * halfX) + (halfY * halfY)
  local nearestX, nearestY = centerX, centerY
  if lengthSquared > 1e-12 then
    local along = (((pointX - centerX) * halfX) + ((pointY - centerY) * halfY)) / lengthSquared
    if along > 1 then along = 1 elseif along < -1 then along = -1 end
    nearestX, nearestY = centerX + (halfX * along), centerY + (halfY * along)
  end
  local deltaX, deltaY = pointX - nearestX, pointY - nearestY
  return math.sqrt((deltaX * deltaX) + (deltaY * deltaY))
end
