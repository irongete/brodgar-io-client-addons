-- The drawings saved in the addon's store, by name. A drawing is the grid its first piece lies on and every
-- piece as offsets from that grid's corner, so it is laid again wherever a character can locate that grid.
-- Three tables: one row per drawing, one per piece, one per point of a piece's ring.

local Sheet = Paint.Sheet

local Drawings = {}
Paint.Drawings = Drawings

local PAGE = 10000 -- rows read per query, well under the store's cap on one read

local drawingTable, pieceTable, pointTable

local function worldSession()
  local session = hafen.session():current()
  return session and session:world() and session or nil
end

-- Declared on first use, so a store that cannot be opened costs the save, not the addon.
local function tables()
  if drawingTable == nil then
    local store = hafen.store()
    local drawings = store:table("drawings")
      :column("name", "text"):column("gridId", "text")
      :key("name"):create()
    local pieces = store:table("drawing_pieces")
      :column("drawing", "text"):column("piece", "integer")
      :column("red", "integer"):column("green", "integer"):column("blue", "integer"):column("alpha", "integer")
      :column("centerX", "real"):column("centerY", "real")
      :column("halfX", "real"):column("halfY", "real"):column("radius", "real")
      :key("drawing", "piece"):create()
    local points = store:table("drawing_points")
      :column("drawing", "text"):column("piece", "integer"):column("point", "integer")
      :column("x", "real"):column("y", "real")
      :key("drawing", "piece", "point"):create()
    drawingTable, pieceTable, pointTable = drawings, pieces, points
  end
  return drawingTable, pieceTable, pointTable
end

-- Every row of one drawing a clause keeps, a page at a time.
local function eachRow(storeTable, clause, name, visit)
  local offset = 0
  while true do
    local rows = storeTable:list(clause .. " LIMIT ? OFFSET ?", name, PAGE, offset)
    for _, row in ipairs(rows) do visit(row) end
    if #rows < PAGE then return end
    offset = offset + PAGE
  end
end

local function removeRows(name)
  local store = hafen.store()
  store:exec("DELETE FROM drawing_points WHERE drawing = ?", name)
  store:exec("DELETE FROM drawing_pieces WHERE drawing = ?", name)
  store:exec("DELETE FROM drawings WHERE name = ?", name)
end

-- One mark as offsets from the grid corner at (cornerX, cornerY), or nil where a point cannot be located.
local function relativePiece(mark, cornerX, cornerY)
  local centerX, centerY = mark.center:x(), mark.center:y()
  if (centerX == nil) or (centerY == nil) then return nil end
  local points = {}
  for index, position in ipairs(mark.ring) do
    local x, y = position:x(), position:y()
    if (x == nil) or (y == nil) then return nil end
    points[index] = {x = x - cornerX, y = y - cornerY}
  end
  return {
    color = mark.color,
    centerX = centerX - cornerX,
    centerY = centerY - cornerY,
    halfX = mark.halfX,
    halfY = mark.halfY,
    radius = mark.radius,
    points = points,
  }
end

local function sameColor(first, second)
  if (first == nil) or (second == nil) then return false end
  for component = 1, 4 do
    if first[component] ~= second[component] then return false end
  end
  return true
end

-- The saved names, sorted.
function Drawings.names()
  tables()
  local names = {}
  for _, row in ipairs(hafen.store():query("SELECT name FROM drawings ORDER BY name COLLATE NOCASE")) do
    names[#names + 1] = row.name
  end
  return names
end

-- Save what is on the ground under `name`, replacing a drawing of that name. Returns true and the number of
-- pieces saved, or false and why nothing was.
function Drawings.save(name)
  local session = worldSession()
  if session == nil then return false, "No character in the world" end
  if #Sheet.marks == 0 then return false, "Nothing to save" end
  local anchor = Sheet.marks[1].center:info()
  if anchor == nil then return false, "The ground is not loaded" end
  local corner = session:world():position({gridId = anchor.gridId, x = 0, y = 0})
  local cornerX, cornerY = corner:x(), corner:y()
  if (cornerX == nil) or (cornerY == nil) then return false, "The ground is not loaded" end

  local pieces = {}
  for _, mark in ipairs(Sheet.marks) do
    local piece = relativePiece(mark, cornerX, cornerY)
    if piece then pieces[#pieces + 1] = piece end
  end
  if #pieces == 0 then return false, "The ground is not loaded" end

  local drawings, pieceRows, pointRows = tables()
  hafen.store():transaction(function()
    removeRows(name)
    drawings:put{name = name, gridId = anchor.gridId}
    for pieceIndex, piece in ipairs(pieces) do
      pieceRows:put{
        drawing = name, piece = pieceIndex,
        red = piece.color[1], green = piece.color[2], blue = piece.color[3], alpha = piece.color[4],
        centerX = piece.centerX, centerY = piece.centerY,
        halfX = piece.halfX, halfY = piece.halfY, radius = piece.radius,
      }
      for pointIndex, point in ipairs(piece.points) do
        pointRows:put{drawing = name, piece = pieceIndex, point = pointIndex, x = point.x, y = point.y}
      end
    end
  end)
  return true, #pieces
end

-- Lay the drawing saved under `name` on the ground again, over what is there. Returns true and the number
-- of pieces laid, or false and why nothing was.
function Drawings.lay(name)
  local session = worldSession()
  if session == nil then return false, "No character in the world" end
  local drawings, pieceRows, pointRows = tables()
  local drawing = drawings:get(name)
  if drawing == nil then return false, "No drawing named " .. name end
  local corner = session:world():position({gridId = drawing.gridId, x = 0, y = 0})
  if corner:x() == nil then return false, "Not in this area" end

  local rings = {} -- [piece] = its ring of Positions
  eachRow(pointRows, "WHERE drawing = ? ORDER BY piece, point", name, function(row)
    local ring = rings[row.piece]
    if ring == nil then
      ring = {}
      rings[row.piece] = ring
    end
    ring[#ring + 1] = corner:offset(row.x, row.y)
  end)

  -- A patch holds one colour, so a piece of another colour than the one before starts a new patch.
  local record, previousColor, laid = nil, nil, 0
  eachRow(pieceRows, "WHERE drawing = ? ORDER BY piece", name, function(row)
    local ring = rings[row.piece]
    if (ring == nil) or (#ring < 3) then return end
    local color = {row.red, row.green, row.blue, row.alpha}
    if not sameColor(color, previousColor) then record = nil end
    previousColor = color
    record = Sheet.lay(record, color, ring, #ring, {
      center = corner:offset(row.centerX, row.centerY),
      halfX = row.halfX,
      halfY = row.halfY,
      radius = row.radius,
    })
    laid = laid + 1
  end)
  return true, laid
end

function Drawings.remove(name)
  tables()
  hafen.store():transaction(removeRows, name)
end
