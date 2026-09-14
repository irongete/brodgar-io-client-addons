-- Gob Cache Map -- the trees and boulders you have walked past, kept, and findable again.
--
-- WHAT IT IS FOR. You want a fir, or a gneiss boulder, and you know you have walked past a dozen of each.
-- This addon writes down every tree and boulder any of your characters loads, so the answer is already on
-- disk by the time you go looking: type a name, pick a row, and the map inside the window goes there.
--
-- WHAT IS NEVER WRITTEN DOWN TWICE. A tree does not move, so a tree IS its place: the SERVER's grid id plus
-- the offset inside that grid -- exactly what Position:info() hands back, and the one anchor no segment
-- merge ever rewrites. The cache is keyed on it, one row of `objects` per (grid, x, y), so seeing the same
-- oak on Monday, on Tuesday, and out of a second character's eyes writes ONE row, with no scan to find that
-- out. A DIFFERENT resource at a place we already hold overwrites it, which is what a mined-out boulder
-- looks like.
--
-- WHERE IT IS KEPT. Two tables of the addon's own file, `savedata/gob-cache-map/gob-cache-map.sqlite`:
-- `kinds` holds each resource name once, and `objects` one row per thing seen, keyed by its place. A row is
-- in the file the moment it is written, nothing is ever serialised whole, and what the window needs is read
-- out of the file by the query that needs it -- so a cache of a few hundred thousand objects costs the frame
-- what one of a hundred does.
--
-- HOW IT LOOKS. The map panel is the client's own minimap art -- `grid:image(level)` is what the corner map
-- draws -- with the search hits marked on top, each as the game's own minimap icon for the thing. So "where
-- are the firs" is answered as a picture before you have read a single row.
--
--   +- Gob Cache Map --------------------------------------------------+
--   | [fir............] [x] Trees [x] Boulders                 [ Here ] |
--   | +--------------+ +-------------------------------------------+   |
--   | | 1. Fir   12t | |        recorded ground (grid:image)       |   |
--   | | 2. Fir   40t | |        + hit marks                        |   |
--   | | 3. Fir   77t | |        + you, and the crosshair           |   |
--   | +--------------+ +-------------------------------------------+   |
--   | 8412 cached (7190 trees, 1222 boulders)  34 shown  zoom 0         |
--   +------------------------------------------------------------------+
--
-- TWO WORDS, USED ONE WAY EACH. A KIND is a row of KINDS below -- Trees, Boulders -- the thing a checkbox
-- switches. A SPECIES is one resource name inside a kind -- gfx/terobjs/trees/fir -- the thing a list row
-- names. On disk a species is a row of the `kinds` table, and an object's `kind` column is its species id.
--
-- WHY THERE IS NO `GobAdded` HANDLER. Subscribing to it makes the client hold EVERY arriving object out of
-- the scene until the handler has run -- a cost paid by the whole client, for immediacy a cache has no use
-- for. A sweep every few seconds writes down the same objects and costs nothing anybody can see.

local NAME = "Gob Cache Map"

local GRID_SIZE = 1100                -- world units across one map grid (100 tiles of 11)
local TILE_SIZE = 11                  -- world units across one tile
local SWEEP_SECONDS = 3               -- seconds between two sweeps of the world
local PRUNE_RADIUS = 60               -- only forget what the character is standing right next to
local PRUNE_MISSES = 3                -- ...and only after this many sweeps in a row have missed it
local CELLS_KEEP_SECONDS = 120        -- seconds a grid's cells stay in memory after a character was last near it
local MAX_ROWS = 200                  -- hits the list shows at once
local PLACE_TRUST_SECONDS = 60        -- seconds a grid's place in its segment is trusted (a merge moves them)
local ICONS_REFRESH_SECONDS = 60      -- seconds between two reads of the client's icon registry
local SETTLE_SECONDS = 2              -- seconds between two re-rankings of the list; also how long a miss in the map database is trusted
local WALKED_FAR = 55                 -- world units the character walks before the list is worth re-ranking

-- The panel, in design pixels.
local MAP_WIDTH, MAP_HEIGHT = 430, 372
local LIST_WIDTH = 232
local TOOLBAR_HEIGHT = 26             -- the search field, the checkboxes and the button
local GAP = 6                         -- between the list and the map
local STATUS_HEIGHT = 20              -- the line under them
local CHECK_WIDTH = 76
local BUTTON_WIDTH = 84
local ICON_SIZE = 14                  -- the box a hit's minimap icon is drawn in
local ICON_HALF = math.floor(ICON_SIZE / 2)
local DRAWING_SIZE = 100              -- design pixels across one of the client's minimap drawings, at every zoom
local PICK_RADIUS = 8                 -- design pixels around a mark that a click on it may land in
local DRAG_THRESHOLD = 4              -- design pixels the pointer moves before a press is a drag and not a click

-- The zoom levels, 0 to 2: how many grids one drawing covers at each.
local GRIDS_PER_DRAWING = { 1, 2, 4 }

-- A kind is a substring of the resource name, because that is the only thing the client can be asked. Add a
-- row here and the cache, the filter and the list all pick it up; nothing else knows the set.
local KINDS = {
    { key = "tree",    label = "Trees",    match = "terobjs/trees/",    color = {  96, 200, 112 } },
    { key = "boulder", label = "Boulders", match = "terobjs/bumlings/", color = { 210, 192, 150 } },
}

-- ---------------------------------------------------------------- the cache on disk

local store = hafen.store()
local settings = store:var("ui")      -- the window's own settings: a var is the shape for those

-- The cache is two tables of the addon's own file. A species is one resource name held once, so an object
-- costs one small integer; an object is its place -- the server's grid id and the offset inside it -- and
-- the species standing there. The key IS the identity: the same oak seen twice is one row, and :put says so.
local speciesTable = store:table("kinds")
    :column("id", "integer"):column("res", "text"):column("icon", "text")
    :key("id"):create()
local objectsTable = store:table("objects")
    :column("grid", "text"):column("x", "integer"):column("y", "integer"):column("kind", "integer")
    :key("grid", "x", "y")
    :index("kind", "grid")            -- "which grids hold a wanted species", off the index alone
    :create()

-- What is known about each species, by its id: rebuilt from the table on load, and none of it stored twice.
local speciesResource = {}            -- id -> the resource name
local speciesIconName = {}            -- id -> the display name of its minimap icon, once an object has told us
local speciesKind = {}                -- id -> the row of KINDS it belongs to
local speciesLabel = {}               -- id -> what the list calls it: "Fir"
local speciesIdByResource = {}        -- resource name -> id
local highestSpeciesId = 0
local speciesCount = 0

local function kindOfResource(resource)
    for _, kind in ipairs(KINDS) do
        if resource:find(kind.match, 1, true) then
            return kind
        end
    end
    return nil
end

local function labelOfResource(resource)
    local lastPart = resource:match("([^/]+)$") or resource
    return lastPart:sub(1, 1):upper() .. lastPart:sub(2)
end

local function learnSpecies(id, resource, iconName)
    speciesResource[id] = resource
    speciesIconName[id] = iconName
    speciesKind[id] = kindOfResource(resource)
    speciesLabel[id] = labelOfResource(resource)
    speciesIdByResource[resource] = id
    if id > highestSpeciesId then
        highestSpeciesId = id
    end
    speciesCount = speciesCount + 1
end

for _, row in ipairs(speciesTable:list("ORDER BY id")) do
    learnSpecies(row.id, row.res, row.icon)
end

local function speciesIdOf(resource)
    local id = speciesIdByResource[resource]
    if id then
        return id
    end
    id = highestSpeciesId + 1         -- never a hole's number: a row could still carry it
    speciesTable:put{ id = id, res = resource }   -- the icon is asked of the first object seen, below
    learnSpecies(id, resource, nil)
    return id
end

-- A hit is drawn as the client's OWN minimap icon for that thing. `gob:icon()` answers the icon's DISPLAY
-- name -- its tooltip, and the very string `hafen.map():icon()` names a category by, out of the same call --
-- so the registry is what turns one into the resource `graphics:resource` draws. That registry grows as a
-- character sees new types, so a name that does not resolve yet is asked again rather than written off.
local MAX_ICON_ASKS = 10              -- give up asking a species for its icon after this many sightings

local iconResourceOfSpecies = {}      -- species id -> the icon's resource, or false for none yet
local iconsResolvedAt = 0             -- when the registry was last read; 0 asks for it now
local iconAsksOfSpecies = {}          -- species id -> how many objects were asked this run

local function resolveIcons()
    local resourceByName = {}
    for _, category in ipairs(hafen.map():icon():list()) do
        local name = category:name()
        if name then
            resourceByName[name] = category:res()
        end
    end
    iconResourceOfSpecies = {}
    for id = 1, highestSpeciesId do
        local wanted = speciesIconName[id]
        iconResourceOfSpecies[id] = (wanted and resourceByName[wanted]) or false
    end
    iconsResolvedAt = os.time()
end

local countByKind = {}                -- kind key -> how many objects of that kind are cached
local totalObjects = 0

local function recount()              -- one aggregate off the (kind, grid) index, not a walk
    countByKind, totalObjects = {}, 0
    for _, row in ipairs(store:query("SELECT kind, count(*) AS n FROM objects GROUP BY kind")) do
        local kind = speciesKind[row.kind]
        local key = kind and kind.key or "other"
        countByKind[key] = (countByKind[key] or 0) + row.n
        totalObjects = totalObjects + row.n
    end
end
recount()

local function addToCount(kindKey, delta)
    countByKind[kindKey] = (countByKind[kindKey] or 0) + delta
end

local function countsText()           -- "7190 trees, 1222 boulders"
    local parts = {}
    for _, kind in ipairs(KINDS) do
        parts[#parts + 1] = (countByKind[kind.key] or 0) .. " " .. kind.key .. "s"
    end
    return table.concat(parts, ", ")
end

-- A cell is one spot inside a grid, named "x,y" -- the key the sweep and the prune agree on.
local function cellKey(x, y)
    return x .. "," .. y
end

local function cellCoords(key)
    local x, y = key:match("^(-?%d+),(-?%d+)$")
    return tonumber(x), tonumber(y)
end

-- The cells of one grid as the sweep and the prune read and write them, `{ ["x,y"] = species id }`: read
-- out of the file the first time a grid is touched and kept while it goes on being touched. Only this addon
-- writes the file and every write goes through here, so what is held is what the file holds. A grid nobody
-- has stood near for a while is dropped: the memory is the characters' surroundings, never the whole cache.
local cellsByGrid = {}                -- gridId -> { touchedAt = when, cells = { ["x,y"] = species id } }

local function cellsOfGrid(gridId)
    local entry = cellsByGrid[gridId]
    if not entry then
        local cells = {}
        for _, row in ipairs(objectsTable:list("WHERE grid = ?", gridId)) do
            cells[cellKey(row.x, row.y)] = row.kind
        end
        entry = { cells = cells }
        cellsByGrid[gridId] = entry
    end
    entry.touchedAt = os.time()
    return entry.cells
end

local function dropIdleCells()
    local now = os.time()
    for gridId, entry in pairs(cellsByGrid) do
        if (now - entry.touchedAt) > CELLS_KEEP_SECONDS then
            cellsByGrid[gridId] = nil
        end
    end
end

-- ---------------------------------------------------------------- writing one down

-- The grids that hold something the current filter wants -- what the search ranks. Read out of the file
-- when the filter changes (`matchingGrids`, below) and kept current by hand in between: a row written into
-- a grid not on it puts the grid on it.
local gridsWithMatches = nil          -- gridId -> true
local gridsWithMatchesFor = nil       -- the filter signature they were read for
local wantedSpecies = {}              -- species id -> whether the current filter wants it

-- Writes the gob down when it is one of ours and has a place, and answers where it went -- the grid id and
-- the cell key -- whether or not it was new. Nil for anything that is not ours to keep.
local function rememberObject(gob)
    local resource = gob:name()
    if not resource then
        return nil
    end
    local kind = kindOfResource(resource)
    if not kind then
        return nil
    end
    local position = gob:position()
    local place = position and position:info()
    if not place then
        return nil                    -- ground this character cannot anchor: not ours to keep
    end
    local cellX, cellY = math.floor(place.x + 0.5), math.floor(place.y + 0.5)
    local key = cellKey(cellX, cellY)
    local cells = cellsOfGrid(place.gridId)

    local speciesId = speciesIdOf(resource)
    local speciesIdBefore = cells[key]
    -- Asked of the live object, because that is the only thing that knows: a resource name says nothing about
    -- whether the game draws an icon for it. It answers nil while the icon's own resource is still loading, so
    -- a species is asked again on its next sighting -- and only so many times, since most things have none.
    if (speciesIconName[speciesId] == nil) and ((iconAsksOfSpecies[speciesId] or 0) < MAX_ICON_ASKS) then
        iconAsksOfSpecies[speciesId] = (iconAsksOfSpecies[speciesId] or 0) + 1
        local iconName = gob:icon()
        if iconName then
            speciesTable:put{ id = speciesId, res = resource, icon = iconName }
            speciesIconName[speciesId] = iconName
            iconsResolvedAt = 0
        end
    end
    if speciesIdBefore == speciesId then
        return place.gridId, key      -- the same thing, in the same grid, at the same spot
    end
    objectsTable:put{ grid = place.gridId, x = cellX, y = cellY, kind = speciesId }   -- in the file when this returns
    cells[key] = speciesId
    if speciesIdBefore then
        local kindBefore = speciesKind[speciesIdBefore]
        if kindBefore then
            addToCount(kindBefore.key, -1)
        end
    else
        totalObjects = totalObjects + 1
    end
    addToCount(kind.key, 1)
    if gridsWithMatches and wantedSpecies[speciesId] then
        gridsWithMatches[place.gridId] = true
    end
    return place.gridId, key
end

local function forgetObject(gridId, key)
    local cells = cellsOfGrid(gridId)
    local speciesId = cells[key]
    if not speciesId then
        return
    end
    local cellX, cellY = cellCoords(key)
    objectsTable:remove(gridId, cellX, cellY)
    cells[key] = nil
    local kind = speciesKind[speciesId]
    if kind then
        addToCount(kind.key, -1)
    end
    totalObjects = totalObjects - 1
end

-- ---------------------------------------------------------------- where a grid sits, this minute

-- Every read of the map database may answer nil for a moment: the file's lock is held by the client's own
-- saves and renders, and a read never waits on it. So a nil is remembered for a beat only, never for the
-- minute a real answer is -- a busy frame must not read as "the database has not got it".
local gridPlaces = {}                 -- gridId -> { place = { segmentId, gridX, gridY } or false, askedAt = when }
local gridPlacesClearedAt = 0

local function placeOfGrid(gridId)
    local now = os.time()
    if (now - gridPlacesClearedAt) > PLACE_TRUST_SECONDS then
        gridPlaces, gridPlacesClearedAt = {}, now
    end
    local known = gridPlaces[gridId]
    if known and (known.place or ((now - known.askedAt) < SETTLE_SECONDS)) then
        return known.place or nil
    end
    local grid = hafen.map():grid():get(gridId)
    local coord = grid and grid:segmentCoord()
    local segment = grid and grid:segment()
    if not (coord and segment) then
        gridPlaces[gridId] = { place = false, askedAt = now }
        return nil
    end
    local place = { segmentId = segment:id(), gridX = coord.x, gridY = coord.y }
    gridPlaces[gridId] = { place = place, askedAt = now }
    return place
end

-- The grid at a segment coord, remembered for the same reason: a busy answer is the one seen last, and a
-- coord the database has nothing at is asked again next time, which is one lookup. Swept every
-- PLACE_TRUST_SECONDS, since a merge moves grids between coords.
local gridsAtCoord = {}
local gridsAtCoordClearedAt = 0

local function gridAtCoord(frame, gridX, gridY)
    local now = os.time()
    if (now - gridsAtCoordClearedAt) > PLACE_TRUST_SECONDS then
        gridsAtCoord, gridsAtCoordClearedAt = {}, now
    end
    local key = frame.segmentId .. "|" .. gridX .. "," .. gridY
    local grid = frame.segment:grid():get({ x = gridX, y = gridY })
    if grid then
        gridsAtCoord[key] = grid
        return grid
    end
    return gridsAtCoord[key]
end

-- Where a character stands, in the durable form -- the grid id and the offset inside it -- or nil.
local function placeOfPlayer(session)
    session = session or hafen.session():current()
    local playerGob = session and session:player() and session:player():gob()
    local position = playerGob and playerGob:position()
    return position and position:info() or nil
end

local function sessionsInWorld()
    local inWorld = {}
    for _, session in ipairs(hafen.session():list()) do
        if session:exists() and session:character() then
            inWorld[#inWorld + 1] = session
        end
    end
    return inWorld
end

-- ---------------------------------------------------------------- the sweep, and forgetting a felled tree

local missesByCell = {}               -- "gridId|x,y" -> sweeps in a row it was missing

-- One cell the character stands right beside. Seen this sweep, all is well; missed three sweeps running, it
-- was felled, mined or built over, and the row goes. Anything further off is simply not streamed in.
local function judgeCell(gridId, key, seenCells)
    local seenKey = gridId .. "|" .. key
    if seenCells[seenKey] then
        missesByCell[seenKey] = nil
        return
    end
    local misses = (missesByCell[seenKey] or 0) + 1
    if misses < PRUNE_MISSES then
        missesByCell[seenKey] = misses
        return
    end
    missesByCell[seenKey] = nil
    forgetObject(gridId, key)
end

local function pruneAround(session, seenCells)
    local playerPlace = placeOfPlayer(session)
    local home = playerPlace and placeOfGrid(playerPlace.gridId)
    if not home then
        return
    end
    local homeGrid = hafen.map():grid():get(playerPlace.gridId)
    local segment = homeGrid and homeGrid:segment()
    if not segment then
        return
    end
    local playerWorldX = home.gridX * GRID_SIZE + playerPlace.x
    local playerWorldY = home.gridY * GRID_SIZE + playerPlace.y
    -- the character's own grid and the eight around it: as far as PRUNE_RADIUS can reach
    for gridX = home.gridX - 1, home.gridX + 1 do
        for gridY = home.gridY - 1, home.gridY + 1 do
            local grid = segment:grid():get({ x = gridX, y = gridY })
            local gridId = grid and grid:id()
            if gridId then
                for key in pairs(cellsOfGrid(gridId)) do
                    local cellX, cellY = cellCoords(key)
                    local worldX = gridX * GRID_SIZE + cellX
                    local worldY = gridY * GRID_SIZE + cellY
                    local distanceSquared = (worldX - playerWorldX) ^ 2 + (worldY - playerWorldY) ^ 2
                    if distanceSquared <= (PRUNE_RADIUS * PRUNE_RADIUS) then
                        judgeCell(gridId, key, seenCells)
                    end
                end
            end
        end
    end
end

local function sweep()
    local seenCells = {}
    -- One transaction around the whole sweep: every row it writes is one commit rather than one each, and
    -- nothing inside waits on anything but the file.
    store:transaction(function()
        for _, session in ipairs(sessionsInWorld()) do
            local gobs = session:world():gob()
            for _, kind in ipairs(KINDS) do
                for _, gob in ipairs(gobs:list(kind.match)) do
                    local gridId, key = rememberObject(gob)
                    if gridId then
                        seenCells[gridId .. "|" .. key] = true
                    end
                end
            end
        end
        for _, session in ipairs(sessionsInWorld()) do
            pruneAround(session, seenCells)
        end
    end)
    dropIdleCells()
end

-- ---------------------------------------------------------------- the filter and the hits

local enabledKinds = {}               -- kind key -> whether its checkbox is on
for _, kind in ipairs(KINDS) do
    enabledKinds[kind.key] = (settings[kind.key] ~= false)
end
local searchText = settings.query or ""

local hits = {}                       -- what the list shows, nearest first
local hitByRowText = {}               -- the list's row text -> its hit
local pickedHit = nil                 -- the row that was picked, which outlives the list it came from

local function matchesSearch(speciesId, kind, needle)
    if needle == "" then
        return true
    end
    return (speciesLabel[speciesId]:lower():find(needle, 1, true) ~= nil)
        or (speciesResource[speciesId]:lower():find(needle, 1, true) ~= nil)
        or (kind.key:find(needle, 1, true) ~= nil)
end

-- What the filter wants, as the species it matches: the ids in a row, whether that is every species known
-- (the usual case, which needs no clause at all), and a signature that says whether the grids read for an
-- earlier filter still serve.
local function wantedSpeciesIds()
    local needle = searchText:lower()
    local ids = {}
    local allWanted = true
    wantedSpecies = {}
    for speciesId = 1, highestSpeciesId do
        local kind = speciesResource[speciesId] and speciesKind[speciesId]
        local wanted = (kind ~= nil) and enabledKinds[kind.key] and matchesSearch(speciesId, kind, needle)
        wantedSpecies[speciesId] = wanted
        if wanted then
            ids[#ids + 1] = speciesId
        else
            allWanted = false
        end
    end
    return ids, allWanted, table.concat(ids, ",")
end

local function placeholders(count)    -- "?,?,?": one for each value bound after the statement
    local marks = {}
    for index = 1, count do
        marks[index] = "?"
    end
    return table.concat(marks, ",")
end

-- The clause that keeps the wanted species, and the values it binds -- nothing at all when every species is
-- wanted.
local function speciesClause(ids, allWanted)
    if allWanted then
        return "", {}
    end
    return " AND kind IN (" .. placeholders(#ids) .. ")", ids
end

-- The grids holding anything the filter wants -- read once per filter, off the (kind, grid) index, and
-- kept current by `rememberObject` from then on. Answers nil when the filter wants nothing at all.
local function matchingGrids()
    local ids, allWanted, signature = wantedSpeciesIds()
    if #ids == 0 then
        gridsWithMatches, gridsWithMatchesFor = nil, signature
        return nil
    end
    if gridsWithMatches and (gridsWithMatchesFor == signature) then
        return gridsWithMatches, ids, allWanted
    end
    local clause, values = speciesClause(ids, allWanted)
    local grids = {}
    for _, row in ipairs(store:query("SELECT DISTINCT grid FROM objects WHERE 1" .. clause, table.unpack(values))) do
        grids[row.grid] = true
    end
    gridsWithMatches, gridsWithMatchesFor = grids, signature
    return grids, ids, allWanted
end

-- A distance of -1 is "in another segment altogether": those sort last, after every measured one.
local function nearerFirst(firstDistance, secondDistance)
    if (firstDistance < 0) ~= (secondDistance < 0) then
        return secondDistance < 0
    end
    return firstDistance < secondDistance
end

local function searchHits()
    local grids, ids, allWanted = matchingGrids()
    if not grids then
        hits = {}
        return
    end
    local playerPlace = placeOfPlayer()
    local home = playerPlace and placeOfGrid(playerPlace.gridId)
    local playerWorldX = home and (home.gridX * GRID_SIZE + playerPlace.x) or 0
    local playerWorldY = home and (home.gridY * GRID_SIZE + playerPlace.y) or 0

    local function distanceTo(segmentId, worldX, worldY)
        if not (home and (segmentId == home.segmentId)) then
            return -1
        end
        return math.sqrt((worldX - playerWorldX) ^ 2 + (worldY - playerWorldY) ^ 2)
    end

    local placedGrids = {}
    for gridId in pairs(grids) do
        local place = placeOfGrid(gridId)
        if place then
            local centerX = place.gridX * GRID_SIZE + GRID_SIZE * 0.5
            local centerY = place.gridY * GRID_SIZE + GRID_SIZE * 0.5
            placedGrids[#placedGrids + 1] = {
                id = gridId,
                place = place,
                distance = distanceTo(place.segmentId, centerX, centerY),
            }
        end
    end
    -- Grids first, hits second: there are hundreds of the one and tens of thousands of the other, so the near
    -- grids are read out of the file one at a time until the list is full, and the rest are never read.
    table.sort(placedGrids, function(first, second)
        return nearerFirst(first.distance, second.distance)
    end)

    local clause, values = speciesClause(ids, allWanted)
    local found = {}
    for _, grid in ipairs(placedGrids) do
        for _, row in ipairs(objectsTable:list("WHERE grid = ?" .. clause, grid.id, table.unpack(values))) do
            local worldX = grid.place.gridX * GRID_SIZE + row.x
            local worldY = grid.place.gridY * GRID_SIZE + row.y
            found[#found + 1] = {
                gridId = grid.id,
                x = row.x,
                y = row.y,
                speciesId = row.kind,
                segmentId = grid.place.segmentId,
                worldX = worldX,
                worldY = worldY,
                distance = distanceTo(grid.place.segmentId, worldX, worldY),
            }
        end
        if #found >= MAX_ROWS then
            break
        end
    end
    table.sort(found, function(first, second)
        if first.distance ~= second.distance then
            return nearerFirst(first.distance, second.distance)
        end
        if first.gridId ~= second.gridId then
            return first.gridId < second.gridId
        end
        if first.x ~= second.x then
            return first.x < second.x
        end
        return first.y < second.y
    end)
    while #found > MAX_ROWS do
        found[#found] = nil
    end
    hits = found
end

-- ---------------------------------------------------------------- the view

-- Where the panel is pointed: a grid and an offset inside it -- the durable form, the one a merge never
-- rewrites -- and the zoom level.
local view = {
    gridId = settings.gridId,
    x = settings.x or (GRID_SIZE * 0.5),
    y = settings.y or (GRID_SIZE * 0.5),
    level = math.min(#GRIDS_PER_DRAWING - 1, math.max(0, settings.level or 0)),
}

local function lookAt(gridId, x, y)
    view.gridId, view.x, view.y = gridId, x, y
    settings.gridId, settings.x, settings.y = gridId, x, y
end

local function lookAtPlayer()
    local playerPlace = placeOfPlayer()
    if not playerPlace then
        return false
    end
    lookAt(playerPlace.gridId, playerPlace.x, playerPlace.y)
    return true
end

-- Everything the map draws and everything a press on it resolves is this one frame: the segment being
-- drawn, how many design pixels a world unit is worth, and where that segment's origin sits on the panel.
-- The anchor's place is asked of the database every frame and remembered: on a frame the file is busy the
-- last answer serves, so the picture holds still instead of going black for a beat.
local lastAnchor = nil                -- { gridId, coord, segment, segmentId, at }: the last anchor resolved

local function mapFrame(width, height)
    local gridId = view.gridId
    if not gridId then
        return nil
    end
    local grid = hafen.map():grid():get(gridId)
    local coord = grid and grid:segmentCoord()
    local segment = grid and grid:segment()
    local now = os.time()
    if coord and segment then
        lastAnchor = { gridId = gridId, coord = coord, segment = segment, segmentId = segment:id(), at = now }
    elseif lastAnchor and (lastAnchor.gridId == gridId) and ((now - lastAnchor.at) <= PLACE_TRUST_SECONDS) then
        coord, segment = lastAnchor.coord, lastAnchor.segment   -- busy this frame: what it answered last
    else
        return nil
    end
    local gridsPerDrawing = GRIDS_PER_DRAWING[view.level + 1]
    local pixelsPerUnit = DRAWING_SIZE / (gridsPerDrawing * GRID_SIZE)
    local centerX = coord.x * GRID_SIZE + view.x   -- the place under the crosshair, in the segment's world units
    local centerY = coord.y * GRID_SIZE + view.y
    return {
        segment = segment,
        segmentId = lastAnchor.segmentId,
        gridsPerDrawing = gridsPerDrawing,
        pixelsPerUnit = pixelsPerUnit,
        centerX = centerX,
        centerY = centerY,
        originX = width * 0.5 - centerX * pixelsPerUnit,   -- where the segment's origin sits on the panel
        originY = height * 0.5 - centerY * pixelsPerUnit,
        anchorGridId = gridId,
        anchorGridX = coord.x,
        anchorGridY = coord.y,
    }
end

-- A place in the segment's world units, as the whole panel pixel it is drawn at -- and back again.
local function worldToPanel(frame, worldX, worldY)
    return math.floor(frame.originX + worldX * frame.pixelsPerUnit),
           math.floor(frame.originY + worldY * frame.pixelsPerUnit)
end

local function panelToWorld(frame, panelX, panelY)
    return (panelX - frame.originX) / frame.pixelsPerUnit,
           (panelY - frame.originY) / frame.pixelsPerUnit
end

-- Point the panel at a place given in the segment's world units. The view is anchored on the grid standing
-- there when the database has one, and stays on the frame's own anchor otherwise: ground never explored has
-- no grid to anchor on, and an offset past the anchor's edge points the panel just as well.
local function lookAtWorld(frame, worldX, worldY)
    local gridX, gridY = math.floor(worldX / GRID_SIZE), math.floor(worldY / GRID_SIZE)
    local grid = gridAtCoord(frame, gridX, gridY)
    if grid then
        lookAt(grid:id(), worldX - gridX * GRID_SIZE, worldY - gridY * GRID_SIZE)
    else
        lookAt(frame.anchorGridId, worldX - frame.anchorGridX * GRID_SIZE, worldY - frame.anchorGridY * GRID_SIZE)
    end
end

-- Above level 0 one drawing covers a block of grids and every grid in it hands back that same picture, so
-- the block is asked for by its corners: the origin grid alone may be one the database never recorded.
local function gridOfDrawing(frame, drawingX, drawingY)
    local span = frame.gridsPerDrawing
    local gridX, gridY = drawingX * span, drawingY * span
    local grid = gridAtCoord(frame, gridX, gridY)
    if grid or (span == 1) then
        return grid
    end
    local last = span - 1
    return gridAtCoord(frame, gridX + last, gridY)
        or gridAtCoord(frame, gridX, gridY + last)
        or gridAtCoord(frame, gridX + last, gridY + last)
end

-- The drawings, by grid and level, as they were last handed out: a nil is a render still on its way OR a
-- file busy this frame, and in the second case the picture drawn a frame ago is the one to draw again. A
-- handle the client has since disposed draws nothing, and the next ask renders it anew.
local drawings = {}

-- ---------------------------------------------------------------- the window

local window, searchEntry, hitList, statusLabel, mapPanel

local function distanceText(hit)
    if hit.distance < 0 then
        return "far"
    end
    return math.floor(hit.distance / TILE_SIZE + 0.5) .. "t"
end

local function fillList()
    local rows = {}
    hitByRowText = {}
    for index, hit in ipairs(hits) do
        local text = index .. ". " .. speciesLabel[hit.speciesId] .. "   " .. distanceText(hit)
        rows[index] = text            -- the index keeps every row string its own value
        hitByRowText[text] = hit
    end
    hitList:rows(rows)                -- this clears the selection, which `pickedHit` outlives
end

local listFilledAt = 0
local listFilledNear = nil            -- where the character stood when the list was last ranked

local function refreshList()
    searchHits()
    fillList()
    listFilledAt, listFilledNear = os.time(), placeOfPlayer()
end

local function selectHitRow(hit)
    for text, rowHit in pairs(hitByRowText) do
        if rowHit == hit then
            hitList:value(text)
            return
        end
    end
end

local function pickHit(hit)
    pickedHit = hit
    lookAt(hit.gridId, hit.x, hit.y)
end

local function statusText()
    -- a drawing is 100 px across and a grid is 100 tiles, so a pixel is as many tiles as a drawing has grids
    local tilesPerPixel = GRIDS_PER_DRAWING[view.level + 1] * GRID_SIZE / DRAWING_SIZE / TILE_SIZE
    return totalObjects .. " cached (" .. countsText() .. ")   "
        .. #hits .. " shown   zoom " .. view.level
        .. " (1 px = " .. tilesPerPixel .. ((tilesPerPixel == 1) and " tile)" or " tiles)")
end

-- the recorded ground: the client's own minimap art, one blit per drawing
local function drawGround(graphics, frame, width, height)
    local firstX, lastX = math.floor(-frame.originX / DRAWING_SIZE), math.floor((width - frame.originX) / DRAWING_SIZE)
    local firstY, lastY = math.floor(-frame.originY / DRAWING_SIZE), math.floor((height - frame.originY) / DRAWING_SIZE)
    for drawingX = firstX, lastX do
        for drawingY = firstY, lastY do
            local grid = gridOfDrawing(frame, drawingX, drawingY)
            if grid then
                local key = grid:id() .. "@" .. view.level
                local image = grid:image(view.level)   -- nil while it renders, or while the file is busy
                if image then
                    drawings[key] = image
                else
                    image = drawings[key]
                end
                if image then
                    graphics:image(image, math.floor(frame.originX + drawingX * DRAWING_SIZE),
                                          math.floor(frame.originY + drawingY * DRAWING_SIZE))
                end
            end
        end
    end
end

-- the hits the list is showing, each drawn as the client's own minimap icon for the thing
local function drawMarks(graphics, frame, width, height)
    for _, hit in ipairs(hits) do
        if hit.segmentId == frame.segmentId then
            local panelX, panelY = worldToPanel(frame, hit.worldX, hit.worldY)
            local onPanel = (panelX > -ICON_SIZE) and (panelX < width + ICON_SIZE)
                and (panelY > -ICON_SIZE) and (panelY < height + ICON_SIZE)
            if onPanel then
                local iconResource = iconResourceOfSpecies[hit.speciesId]
                if iconResource then
                    graphics:color()  -- untinted: the icon is the client's art, not ours to dye
                    graphics:resource(iconResource, panelX - ICON_HALF, panelY - ICON_HALF, ICON_SIZE, ICON_SIZE)
                else
                    -- nothing the game draws an icon for: a pip in its kind's colour
                    local color = speciesKind[hit.speciesId].color
                    graphics:color(0, 0, 0, 210)
                    graphics:poly(panelX, panelY - 4, panelX + 4, panelY, panelX, panelY + 4, panelX - 4, panelY)
                    graphics:color(color[1], color[2], color[3])
                    graphics:poly(panelX, panelY - 2, panelX + 2, panelY, panelX, panelY + 2, panelX - 2, panelY)
                end
            end
        end
    end
end

-- the one that was picked, named where it stands
local function drawPickedHit(graphics, frame)
    if not (pickedHit and (pickedHit.segmentId == frame.segmentId)) then
        return
    end
    local panelX, panelY = worldToPanel(frame, pickedHit.worldX, pickedHit.worldY)
    graphics:color(255, 240, 120)
    graphics:rect(panelX - ICON_HALF - 2, panelY - ICON_HALF - 2, ICON_SIZE + 4, ICON_SIZE + 4)
    graphics:text(speciesLabel[pickedHit.speciesId], panelX + ICON_HALF + 3, panelY - 7, { color = { 255, 240, 120 } })
end

-- the character on screen
local function drawPlayer(graphics, frame)
    local playerPlace = placeOfPlayer()
    local home = playerPlace and placeOfGrid(playerPlace.gridId)
    if not (home and (home.segmentId == frame.segmentId)) then
        return
    end
    local panelX, panelY = worldToPanel(frame, home.gridX * GRID_SIZE + playerPlace.x,
                                               home.gridY * GRID_SIZE + playerPlace.y)
    graphics:color(0, 0, 0, 220)
    graphics:frect(panelX - 3, panelY - 3, 7, 7)
    graphics:color(255, 255, 255)
    graphics:frect(panelX - 2, panelY - 2, 5, 5)
end

local function drawMap(event)
    local graphics, width, height = event:g(), event:w(), event:h()
    graphics:color(16, 18, 20)
    graphics:frect(0, 0, width, height)

    local frame = mapFrame(width, height)
    if not frame then
        graphics:color(170, 175, 180)
        graphics:text(view.gridId and "this ground has not been written down yet"
                                   or "nothing to look at yet -- press Here", 8, 8)
        graphics:color()
        return
    end

    -- WHITE FIRST. An image is drawn THROUGH the draw colour -- Tex.crender multiplies by it -- so the plate
    -- colour above would tint the whole map down to near-black. The map's own colours are the point of it.
    graphics:color()
    drawGround(graphics, frame, width, height)
    drawMarks(graphics, frame, width, height)
    drawPickedHit(graphics, frame)
    drawPlayer(graphics, frame)

    -- where the panel is pointed, and the edge of it
    graphics:color(255, 255, 255, 70)
    graphics:line(width * 0.5 - 7, height * 0.5, width * 0.5 + 7, height * 0.5, 1)
    graphics:line(width * 0.5, height * 0.5 - 7, width * 0.5, height * 0.5 + 7, 1)
    graphics:color(74, 84, 74)
    graphics:rect(0, 0, width, height)
    graphics:color()
end

-- ---------------------------------------------------------------- pressing the map, and dragging it
--
-- A press on the map is one of two gestures, and which one is only known when the button comes up: a
-- pointer that stayed put was a CLICK -- the mark under it is picked, or empty ground is looked at -- and
-- one that moved was a DRAG, and the ground followed it the whole way. The pointer is taken with a grab for
-- the length of the press, since a release outside the panel would never reach the panel on its own.

-- The nearest mark within reach of a panel pixel, or nil.
local function hitUnder(frame, panelX, panelY)
    local nearest, nearestDistance = nil, nil
    for _, hit in ipairs(hits) do
        if hit.segmentId == frame.segmentId then
            local markX, markY = worldToPanel(frame, hit.worldX, hit.worldY)
            local distance = (markX - panelX) ^ 2 + (markY - panelY) ^ 2
            if (distance <= PICK_RADIUS * PICK_RADIUS) and ((nearestDistance == nil) or (distance < nearestDistance)) then
                nearest, nearestDistance = hit, distance
            end
        end
    end
    return nearest
end

local function clickMap(frame, panelX, panelY)
    local hit = hitUnder(frame, panelX, panelY)
    if hit then
        pickHit(hit)
        selectHitRow(hit)
        return
    end
    -- empty ground: look there, and let the pick go, which is also how the list starts re-ranking again
    lookAtWorld(frame, panelToWorld(frame, panelX, panelY))
    pickedHit = nil
end

local function dragMap(press, pointerX, pointerY)
    local movedX, movedY = pointerX - press.pointerX, pointerY - press.pointerY
    if not press.dragging then
        if (movedX * movedX + movedY * movedY) < (DRAG_THRESHOLD * DRAG_THRESHOLD) then
            return
        end
        press.dragging = true
    end
    -- the ground follows the pointer: what was under the crosshair when the button went down moves with it
    local frame = press.frame
    lookAtWorld(frame, frame.centerX - movedX / frame.pixelsPerUnit, frame.centerY - movedY / frame.pixelsPerUnit)
end

local function mapPressed(event)
    event:preventDefault()            -- ours: a press that falls through would drag the window instead
    local frame = mapFrame(MAP_WIDTH, MAP_HEIGHT)
    if not frame then
        return
    end
    local pointer = hafen.ui():mouse()
    local press = {
        frame = frame,                                    -- the map as it stood when the button went down
        panelX = event:x(), panelY = event:y(),           -- on the panel: where a click lands
        pointerX = pointer:x(), pointerY = pointer:y(),   -- on the screen: the space the grab reports in
        dragging = false,
    }
    local grab = pointer:grab()
    grab:on("Move", function(move)
        dragMap(press, move:x(), move:y())
    end)
    grab:on("Up", function()
        if not press.dragging then
            clickMap(press.frame, press.panelX, press.panelY)
        end
    end)
end

local function build()
    if window then
        return
    end
    local windowWidth = LIST_WIDTH + GAP + MAP_WIDTH
    local windowHeight = TOOLBAR_HEIGHT + MAP_HEIGHT + STATUS_HEIGHT

    window = hafen.ui():window():title(NAME):size(windowWidth, windowHeight):position(120, 80)
    window:remember("window")

    searchEntry = hafen.ui():entry():parent(window):position(0, 0):size(LIST_WIDTH):value(searchText)
    searchEntry:tooltip("part of a species or a kind: fir, boulder, gneiss")

    local checkX = LIST_WIDTH + 8
    for _, kind in ipairs(KINDS) do
        local check = hafen.ui():check():parent(window):position(checkX, 2):size(CHECK_WIDTH)
            :text(kind.label):value(enabledKinds[kind.key])
        check:on("Changed", function(on)
            enabledKinds[kind.key] = on
            settings[kind.key] = on
            pickedHit = nil           -- another set of hits: the old pick is not in it
            refreshList()
        end)
        checkX = checkX + CHECK_WIDTH + 4
    end

    local hereButton = hafen.ui():button():parent(window):position(windowWidth - BUTTON_WIDTH, 0):size(BUTTON_WIDTH):text("Here")
    hereButton:tooltip("look at the character on screen")
    hereButton:on("Pressed", function()
        if not lookAtPlayer() then
            hafen.log():write(NAME .. ": no character on screen")
        end
    end)

    hitList = hafen.ui():listbox():parent(window):position(0, TOOLBAR_HEIGHT):size(LIST_WIDTH, MAP_HEIGHT):rowHeight(16)
    mapPanel = hafen.ui():widget():parent(window):position(LIST_WIDTH + GAP, TOOLBAR_HEIGHT):size(MAP_WIDTH, MAP_HEIGHT):name("map")
    statusLabel = hafen.ui():label():parent(window):position(0, TOOLBAR_HEIGHT + MAP_HEIGHT + 4):text("")

    searchEntry:on("Changed", function(text)
        searchText = text
        settings.query = text
        pickedHit = nil               -- a new search: the map keeps its place, the pick does not
        refreshList()
    end)
    searchEntry:on("Submitted", function()
        if hits[1] then
            pickHit(hits[1])
            selectHitRow(hits[1])
        end
    end)
    hitList:on("Changed", function(rowText)
        local hit = hitByRowText[rowText]
        if hit then
            pickHit(hit)
        end
    end)
    mapPanel:on("Draw", drawMap)
    mapPanel:on("MouseDown", mapPressed)
    mapPanel:on("Wheel", function(event)
        local step = (event:amount() > 0) and 1 or -1
        view.level = math.max(0, math.min(#GRIDS_PER_DRAWING - 1, view.level + step))
        settings.level = view.level
        event:preventDefault()
    end)
    window:on("Close", function()
        window:visible(false)
        settings.open = false
    end)
end

local function showWindow(on)
    build()
    window:visible(on)
    settings.open = on
    if on then
        if not view.gridId then
            lookAtPlayer()
        end
        refreshList()
    end
end

local function toggleWindow()
    showWindow(not (window and window:visible()))
end

-- ---------------------------------------------------------------- the beat

local statusShown = nil

local function walkedFar(place, since)
    if not since then
        return true
    end
    if place.gridId ~= since.gridId then
        return true
    end
    return ((place.x - since.x) ^ 2 + (place.y - since.y) ^ 2) > (WALKED_FAR * WALKED_FAR)
end

local function tick()
    if not (window and window:visible()) then
        return
    end
    if not view.gridId then
        lookAtPlayer()                -- left open across a relog: find the character again
    end

    local now = os.time()
    if (now - iconsResolvedAt) > ICONS_REFRESH_SECONDS then
        resolveIcons()                -- the registry grows; a species with no icon yet re-asks
    end

    -- Distances go stale as you walk. Re-ranking under a selection would take the row out from under the
    -- pointer, and rewriting the rows while nobody has moved would fight the scrollbar -- so the list is
    -- re-read only when nothing is picked and the character has walked far enough for the order to matter.
    if (not pickedHit) and ((now - listFilledAt) >= SETTLE_SECONDS) then
        local playerPlace = placeOfPlayer()
        if playerPlace and walkedFar(playerPlace, listFilledNear) then
            refreshList()
        end
    end

    local text = statusText()
    if text ~= statusShown then
        statusLabel:text(text)        -- a write resizes the label, so only a change is written
        statusShown = text
    end
end

hafen.event():on("Load", function()
    build()
    window:visible(settings.open == true)
    if settings.open then
        refreshList()
    end
    hafen.log():write(NAME .. ": " .. totalObjects .. " object(s) cached -- ':gobcache' opens it")
end)

hafen.timer():every(SWEEP_SECONDS, sweep)
hafen.timer():every(0.5, tick)

hafen.client():options():keybindings():on("toggle", function()
    hafen.timer():after(0, toggleWindow)
end)

-- ---------------------------------------------------------------- the console

local function writeStats()
    local gridCount = store:query("SELECT count(DISTINCT grid) AS n FROM objects")[1].n
    hafen.log():write(NAME .. ": " .. totalObjects .. " object(s) (" .. countsText() .. ") over "
        .. gridCount .. " grid(s), " .. speciesCount .. " resource(s) known")
end

local function clearCache()
    store:transaction(function()
        store:exec("DELETE FROM objects")
        store:exec("DELETE FROM kinds")
    end)
    speciesResource, speciesIconName, speciesKind, speciesLabel, speciesIdByResource = {}, {}, {}, {}, {}
    highestSpeciesId, speciesCount = 0, 0
    cellsByGrid, missesByCell = {}, {}
    gridsWithMatches, gridsWithMatchesFor = nil, nil
    iconResourceOfSpecies, iconsResolvedAt, iconAsksOfSpecies = {}, 0, {}
    recount()
    pickedHit = nil
    build()
    refreshList()
end

hafen.console():on("gobcache", function(args)
    local what = args[1]
    local confirmed = (args[2] == "yes")
    -- A console line holds the character's own tree, and everything below touches ours.
    hafen.timer():after(0, function()
        if what == "stats" then
            writeStats()
        elseif what == "scan" then
            sweep()
            hafen.log():write(NAME .. ": swept -- " .. totalObjects .. " object(s) cached")
        elseif what == "clear" then
            if not confirmed then
                hafen.log():write(NAME .. ": ':gobcache clear yes' throws away all " .. totalObjects .. " of them")
                return
            end
            clearCache()
            hafen.log():write(NAME .. ": cache emptied")
        else
            toggleWindow()
        end
    end)
end)
