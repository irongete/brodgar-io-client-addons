-- What is on the ground: every patch this addon laid, and every piece still down, kept as a mark the eraser
-- can find. A stroke is one patch of many pieces, and a patch holds at most EDGE_BUDGET edges across all of
-- them, so a long stroke runs on into a second patch.

local Geometry = Paint.Geometry

local Sheet = {}
Paint.Sheet = Sheet

local EDGE_BUDGET = 128 -- the client's limit per patch, counted across every piece of it

Sheet.patches = {} -- {patch =, edges =, alive =}, in the order they were laid
Sheet.marks = {}   -- one per piece still down: {record =, piece =, center =, halfX =, halfY =, radius =}

local function log(message)
  hafen.log():write(Paint.NAME .. ": " .. tostring(message))
end

-- Lay one convex ring as a piece of `record`'s patch, or of a new patch when the record is nil, its patch is
-- gone or the ring would overrun the edge budget. `mark` is the capsule the piece covers: `center` is a
-- Position, `halfX`/`halfY` reach along it and `radius` across; the new patch is anchored at that centre.
-- Returns the record the piece went into, or nil when the client refused a new patch.
function Sheet.lay(record, color, ring, edgeCount, mark)
  local piece
  if (record == nil) or (not record.patch:exists()) or ((record.edges + edgeCount) > EDGE_BUDGET) then
    local ok, patch = pcall(function()
      return hafen.virtual():patch():add(ring, mark.center):tint(color)
    end)
    if not ok then
      log(patch)
      return nil
    end
    record = {patch = patch, edges = edgeCount, alive = 1}
    Sheet.patches[#Sheet.patches + 1] = record
    piece = patch:piece():list()[1] -- the ring :add was given is the patch's first piece
  else
    local ok, added = pcall(function() return record.patch:piece():add(ring) end)
    if not ok then
      log(added)
      return record
    end
    record.edges = record.edges + edgeCount
    record.alive = record.alive + 1
    piece = added
  end
  mark.record, mark.piece = record, piece
  Sheet.marks[#Sheet.marks + 1] = mark
  return record
end

-- Take one mark's piece up, and its patch once that holds nothing. The marks are unordered: the last one
-- fills the hole.
local function takeUp(index)
  local mark = Sheet.marks[index]
  Sheet.marks[index] = Sheet.marks[#Sheet.marks]
  Sheet.marks[#Sheet.marks] = nil
  local record = mark.record
  if record.patch:exists() then
    pcall(function() record.patch:piece():remove(mark.piece) end)
    record.alive = record.alive - 1
    if record.alive <= 0 then
      pcall(function() hafen.virtual():patch():remove(record.patch) end)
    end
  end
end

-- Take up every piece within `reach` of (x, y). Whole pieces only: a piece is a convex ring, and there is
-- nothing to subtract from it. Each mark is asked where its centre is now, since the server re-bases world
-- coordinates when the character changes area; a mark this character cannot locate is skipped.
function Sheet.rub(x, y, reach)
  local index = 1
  while index <= #Sheet.marks do
    local mark = Sheet.marks[index]
    local markX, markY = mark.center:x(), mark.center:y()
    if (markX == nil) or (markY == nil) then
      index = index + 1
    elseif Geometry.axisDistance(x, y, markX, markY, mark.halfX, mark.halfY) <= (reach + mark.radius) then
      takeUp(index)
    else
      index = index + 1
    end
  end
end

function Sheet.clear()
  for _, record in ipairs(Sheet.patches) do
    if record.patch:exists() then
      pcall(function() hafen.virtual():patch():remove(record.patch) end)
    end
  end
  Sheet.patches, Sheet.marks = {}, {}
end
