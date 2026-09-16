-- resourcestack -- the client's loaded resources, browsed. The sibling of widgetstack (widgets) and eventstack
-- (events) for the third thing a client holds: its .res pool, read through hafen.resource() (client 151).
--
-- THE LEFT COLUMN is every resource the client HOLDS -- the ones something already fetched: what the HUD drew,
-- the gobs on screen, the items in a bag -- as a list, with a search box above it. The box is a substring of the
-- name ("gfx/hud", "terobjs/trees", "sfx"); the pool grows as the game runs, so the list re-reads itself on a beat
-- whenever the client's count moves. widget:rows() refuses more than 4096 rows, so a wide match is cut at
-- LIST_ROW_CAP and the status line says to narrow the search.
--
-- THE RIGHT PANEL is the resource you picked: name, version, load state, a preview of its default image layer
-- (g:resource draws it), and every layer with everything layer:info() decodes for its type -- image geometry,
-- tooltip and pagina text, audio volume, neg hotspot/box/rings, obst rings, anim frames, props and meta tables.
-- A type the codec does not decode (mesh, skel, mat2, tileset2, ...) shows as its key alone. The wheel scrolls it.
--
-- THE FETCH BUTTON takes what is typed in the search box AS A NAME and asks the client for it: :get(name) mints
-- the handle and the first content read makes the client fetch it. The panel follows the fetch -- "fetching",
-- then the layers, or the client's own error for a name the server has no resource for -- and once it lands the
-- resource is held like any other and appears in the list.
--
-- THE WINDOW RESIZES from the client's own corner grip (window:resizable(true)): the list column keeps its
-- width and takes the height, the detail panel takes the rest, re-laid from Update whenever window:size()
-- moved, so it follows the drag live. widget:remember keeps the place and the size.
--
-- THE X HIDES, IT DOES NOT DESTROY: the Close handler cancels the client's destroy and hides the window, so the
-- list, the pick and the scroll survive a close, and :resourcestack shows it again. Nothing runs while it is
-- hidden: the beat and the fetch poll are the window's own Update and step over a hidden window.

hafen.log():write("resourcestack loaded")

local NAME = "resourcestack"

local LIST_WIDTH = 360
local GAP = 6
local WINDOW_WIDTH = LIST_WIDTH + GAP + 620   -- the stock size; the grip changes it and remember() keeps it
local WINDOW_HEIGHT = 620
local MIN_WINDOW_WIDTH = LIST_WIDTH + GAP + 240
local MIN_WINDOW_HEIGHT = 240
local TOOLBAR_HEIGHT = 26
local STATUS_HEIGHT = 20
local FETCH_BUTTON_WIDTH = 64
local ROW_HEIGHT = 16
local LINE = 14                      -- a text line of the detail panel
local DETAIL_HEADER_HEIGHT = 44      -- name and state, above the layer lines
local PREVIEW_BOX = 72               -- the default image is scaled to fit this square, as a row of its layer
local CHARACTER_WIDTH = 6.7          -- what a character of the default font is budgeted at, as in widgetstack
local WHEEL_LINES = 3
local LIST_ROW_CAP = 4000            -- widget:rows() refuses more than 4096
local REFRESH_SECONDS = 1.0          -- how often the list asks the client whether its pool moved
local POINT_LIMIT = 12               -- points of a ring printed before "..."
local ARRAY_LIMIT = 16               -- elements of a plain array printed before "..."

local COLOR_HEADING = { 230, 230, 160 }
local COLOR_LAYER = { 150, 190, 255 }
local COLOR_FIELD = { 200, 200, 200 }
local COLOR_MUTED = { 130, 130, 130 }
local COLOR_ERROR = { 230, 120, 120 }
local COLOR_OK = { 150, 230, 150 }

local window, searchEntry, fetchButton, resourceList, statusLabel, detailPanel
local detailWidth, detailHeight = 620, WINDOW_HEIGHT   -- the panel's box, written by layout()
local laidOutWidth, laidOutHeight = 0, 0              -- the content box the children were last placed for
local detailMaxCharacters = 90
local searchText = ""
local shownNames = {}
local shownSet = {}
local heldCount = 0
local matchedCount = 0
local lastStatus = nil
local listClock = 0
local listDirty = true
local lastHeldCount = -1

local selected          -- the picked resource: { name, resource, done, loaded, error, version, layerCount,
                        --   lines = { {text=, color=} | {preview=true, width=, height=, imageWidth=, imageHeight=} ... } }
local detailScroll = 0

-- ================================================================================ small string helpers

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ellipsis(text, maxCharacters)
  if #text <= maxCharacters then return text end
  return text:sub(1, maxCharacters - 2) .. ".."
end

local function sortedKeys(tableValue)
  local keys = {}
  for key in pairs(tableValue) do keys[#keys + 1] = key end
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  return keys
end

local function isArray(tableValue)
  local length = #tableValue
  if length == 0 then return next(tableValue) == nil end
  local count = 0
  for _ in pairs(tableValue) do count = count + 1 end
  return count == length
end

-- The client's {x,y} and {w,h} tables REFUSE a field they do not carry (reading .x on a size raises), so a
-- probe goes through rawget, which asks the table and never its metatable.
local function field(tableValue, key)
  if type(tableValue) ~= "table" then return nil end
  return rawget(tableValue, key)
end

local function isPoint(tableValue)
  return type(field(tableValue, "x")) == "number" and type(field(tableValue, "y")) == "number"
end

local function isSize(tableValue)
  return type(field(tableValue, "w")) == "number" and type(field(tableValue, "h")) == "number"
end

local function formatNumber(number)
  if number == math.floor(number) then return tostring(math.floor(number)) end
  return ("%.3f"):format(number)
end

local function formatPoint(point)
  return "(" .. formatNumber(field(point, "x")) .. "," .. formatNumber(field(point, "y")) .. ")"
end

local describeValue

local function describeArray(array, depth)
  local length = #array
  if length == 0 then return "[]" end
  if isPoint(array[1]) then
    local parts = {}
    for index = 1, math.min(length, POINT_LIMIT) do parts[#parts + 1] = formatPoint(array[index]) end
    if length > POINT_LIMIT then parts[#parts + 1] = ("... (+%d)"):format(length - POINT_LIMIT) end
    return ("%d points: %s"):format(length, table.concat(parts, " "))
  end
  local parts = {}
  for index = 1, math.min(length, ARRAY_LIMIT) do parts[#parts + 1] = describeValue(array[index], depth + 1) end
  if length > ARRAY_LIMIT then parts[#parts + 1] = ("... (+%d)"):format(length - ARRAY_LIMIT) end
  return "[" .. table.concat(parts, ", ") .. "]"
end

describeValue = function(value, depth)
  local valueType = type(value)
  if valueType == "nil" then return "nil" end
  if valueType == "number" then return formatNumber(value) end
  if valueType == "boolean" then return tostring(value) end
  if valueType == "string" then return "'" .. value:gsub("\n", "\\n") .. "'" end
  if valueType ~= "table" then return tostring(value) end
  if isPoint(value) then
    if isSize(value) then
      return formatPoint(value) .. " " .. formatNumber(field(value, "w")) .. "x" .. formatNumber(field(value, "h"))
    end
    return formatPoint(value)
  end
  if isSize(value) then
    return formatNumber(field(value, "w")) .. "x" .. formatNumber(field(value, "h"))
  end
  if depth >= 3 then return "{...}" end
  if isArray(value) then return describeArray(value, depth) end
  local parts = {}
  for _, key in ipairs(sortedKeys(value)) do
    parts[#parts + 1] = tostring(key) .. "=" .. describeValue(value[key], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- Break a long text into lines of at most maxCharacters, on spaces where there are any.
local function wrapText(text, maxCharacters)
  local lines = {}
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    local current = ""
    for word in paragraph:gmatch("%S+") do
      if current == "" then
        current = word
      elseif #current + 1 + #word <= maxCharacters then
        current = current .. " " .. word
      else
        lines[#lines + 1] = current
        current = word
      end
      while #current > maxCharacters do
        lines[#lines + 1] = current:sub(1, maxCharacters)
        current = current:sub(maxCharacters + 1)
      end
    end
    lines[#lines + 1] = current
  end
  return lines
end

-- ================================================================================ the detail lines

local function addLine(lines, text, color)
  lines[#lines + 1] = { text = text, color = color }
end

-- One field of a layer's info(), as one or more lines. Rings and long texts get a line each so nothing of
-- them is lost behind an ellipsis; everything else is one "field: value" line.
local function addFieldLines(lines, fieldName, value)
  local indent = "      "
  if type(value) == "string" and (fieldName == "text") then
    local wrapped = wrapText(value, detailMaxCharacters - #indent - 2)
    addLine(lines, ("    %s:"):format(fieldName), COLOR_FIELD)
    for _, textLine in ipairs(wrapped) do addLine(lines, indent .. textLine) end
    return
  end
  if type(value) == "table" and (fieldName == "ep" or fieldName == "rings") and isArray(value) then
    addLine(lines, ("    %s: %d rings"):format(fieldName, #value), COLOR_FIELD)
    for ringIndex, ring in ipairs(value) do
      if type(ring) == "table" and #ring > 0 then
        addLine(lines, ("%sring %d: %s"):format(indent, ringIndex, describeArray(ring, 1)))
      else
        addLine(lines, ("%sring %d: empty"):format(indent, ringIndex), COLOR_MUTED)
      end
    end
    return
  end
  if type(value) == "table" and (fieldName == "meta" or fieldName == "props") and not isArray(value) then
    local keys = sortedKeys(value)
    addLine(lines, ("    %s: %d entries"):format(fieldName, #keys), COLOR_FIELD)
    for _, key in ipairs(keys) do
      addLine(lines, ("%s%s = %s"):format(indent, tostring(key), describeValue(value[key], 1)))
    end
    return
  end
  if type(value) == "table" and fieldName == "frames" and isArray(value) then
    addLine(lines, ("    frames: %d %s"):format(#value, describeArray(value, 1)), COLOR_FIELD)
    return
  end
  addLine(lines, ("    %s: %s"):format(fieldName, describeValue(value, 0)), COLOR_FIELD)
end

local function layerKey(layer)
  local identifier = layer:id()
  if identifier == nil then return layer:type() end
  return layer:type() .. ":" .. tostring(identifier)
end

-- Read everything the loaded resource answers, once, into selected.lines. Called on the step (Update),
-- never from Draw: Draw only formats what was read.
local function describeSelected()
  local resource = selected.resource
  local lines = {}
  local info = resource:info()
  selected.version = info and info.version or resource:version()
  local layers = resource:layers():list()
  selected.layerCount = #layers

  addLine(lines, ("layers (%d), in wire order:"):format(#layers), COLOR_HEADING)
  local previewShown = false
  for index, layer in ipairs(layers) do
    local key = layerKey(layer)
    addLine(lines, ("[%d] %s"):format(index, key), COLOR_LAYER)
    local okInfo, layerInfo = pcall(function() return layer:info() end)
    if not okInfo then
      addLine(lines, "    info(): " .. tostring(layerInfo), COLOR_ERROR)
    else
      -- g:resource draws the resource's DEFAULT image, which is its first image layer: that one gets a row
      -- with the picture, scaled to fit PREVIEW_BOX.
      local size = field(layerInfo, "size")
      if layer:type() == "image" and not previewShown and isSize(size) then
        previewShown = true
        local imageWidth = math.max(1, field(size, "w"))
        local imageHeight = math.max(1, field(size, "h"))
        local scale = math.min(PREVIEW_BOX / imageWidth, PREVIEW_BOX / imageHeight)
        lines[#lines + 1] = {
          preview = true,
          width = math.max(1, math.floor(imageWidth * scale)),
          height = math.max(1, math.floor(imageHeight * scale)),
          imageWidth = imageWidth,
          imageHeight = imageHeight,
        }
      end
      local fieldNames = {}
      for _, fieldName in ipairs(sortedKeys(layerInfo)) do
        if fieldName ~= "type" and fieldName ~= "id" then fieldNames[#fieldNames + 1] = fieldName end
      end
      if #fieldNames == 0 then
        addLine(lines, "    (nothing decoded for this type)", COLOR_MUTED)
      else
        for _, fieldName in ipairs(fieldNames) do addFieldLines(lines, fieldName, layerInfo[fieldName]) end
      end
    end
  end
  selected.lines = lines
end

-- Follow the picked resource until it is loaded or failed: a content read makes the client fetch it, and
-- :loaded()/:error() say where that stands. Cheap while pending, and nothing once done.
local function pollSelected()
  if not selected or selected.done or not selected.resource then return end
  local resource = selected.resource
  if resource:loaded() then
    selected.loaded = true
    selected.done = true
    local okDescribe, describeError = pcall(describeSelected)
    if not okDescribe then
      selected.lines = { { text = "read failed: " .. tostring(describeError), color = COLOR_ERROR } }
    end
    listDirty = true               -- a fetch that landed is one more held resource
    return
  end
  local why = resource:error()
  if why then
    selected.error = why
    selected.done = true
    selected.lines = {}
    for _, textLine in ipairs(wrapText(why, detailMaxCharacters)) do
      selected.lines[#selected.lines + 1] = { text = textLine, color = COLOR_ERROR }
    end
  end
end

local function selectResource(name)
  detailScroll = 0
  local okGet, resourceOrError = pcall(function() return hafen.resource():get(name) end)
  if not okGet then
    local message = tostring(resourceOrError):gsub("\nstack traceback:.*$", "")
    selected = { name = name, done = true, error = message, lines = {} }
    for _, textLine in ipairs(wrapText(message, detailMaxCharacters)) do
      selected.lines[#selected.lines + 1] = { text = textLine, color = COLOR_ERROR }
    end
    return
  end
  selected = { name = name, resource = resourceOrError, done = false, loaded = false, lines = {} }
  pollSelected()
end

-- ================================================================================ the list column

local function refreshList()
  local resources = hafen.resource()
  heldCount = resources:count()
  lastHeldCount = heldCount
  local query = trim(searchText)
  local matched = (query == "") and resources:list() or resources:list(query)
  matchedCount = #matched

  local names = {}
  for index = 1, matchedCount do names[index] = matched[index]:name() end
  table.sort(names)
  if #names > LIST_ROW_CAP then
    for index = #names, LIST_ROW_CAP + 1, -1 do names[index] = nil end
  end
  shownNames = names
  shownSet = {}
  for _, name in ipairs(names) do shownSet[name] = true end

  resourceList:rows(names)             -- this clears the selection; the pick outlives it
  if selected and shownSet[selected.name] then
    pcall(function() resourceList:value(selected.name) end)
  end

  local status
  if matchedCount > LIST_ROW_CAP then
    status = ("%d held, %d match, first %d shown -- narrow the search"):format(heldCount, matchedCount, LIST_ROW_CAP)
  elseif query == "" then
    status = ("%d held"):format(heldCount)
  else
    status = ("%d held, %d match"):format(heldCount, matchedCount)
  end
  if status ~= lastStatus then          -- a write resizes the label, so only a change is written
    lastStatus = status
    statusLabel:text(status)
  end
end

local function listTick(deltaTime)
  listClock = listClock + deltaTime
  if listClock >= REFRESH_SECONDS then
    listClock = 0
    if hafen.resource():count() ~= lastHeldCount then listDirty = true end
  end
  if listDirty then
    listDirty = false
    refreshList()
  end
end

local function fetchTyped()
  local name = trim(searchText)
  if name == "" then
    hafen.log():write(NAME .. ": type a resource name in the search box, then Fetch")
    return
  end
  selectResource(name)
  hafen.log():write((NAME .. ": fetching %s"):format(name))
end

-- ================================================================================ the detail panel

local function setColor(graphics, color)
  if color then graphics:color(color[1], color[2], color[3]) else graphics:color() end
end

local function drawDetail(event)
  local graphics, width, height = event:g(), event:w(), event:h()
  graphics:color(0, 0, 0, 160); graphics:frect(0, 0, width, height); graphics:color()

  if not selected then
    setColor(graphics, COLOR_MUTED)
    graphics:text("pick a resource on the left, or type a name and Fetch", 8, 8)
    graphics:color()
    graphics:color(120, 120, 120); graphics:rect(0, 0, width, height); graphics:color()
    return
  end

  local headerCharacters = math.floor((width - 16) / CHARACTER_WIDTH)

  setColor(graphics, COLOR_HEADING)
  graphics:text(ellipsis(selected.name, headerCharacters), 8, 8)
  graphics:color()

  local stateText, stateColor
  if selected.error then
    stateText, stateColor = "FAILED", COLOR_ERROR
  elseif selected.loaded then
    stateText = ("loaded    version %s    %d layers"):format(tostring(selected.version or "?"), selected.layerCount or 0)
    stateColor = COLOR_OK
  else
    stateText, stateColor = "fetching...", COLOR_MUTED
  end
  setColor(graphics, stateColor)
  graphics:text(stateText, 8, 8 + LINE)
  graphics:color()

  graphics:color(90, 90, 90); graphics:frect(6, DETAIL_HEADER_HEIGHT - 6, width - 12, 1); graphics:color()

  -- Rows are text lines of LINE, except a preview row, which is as tall as its picture: walk them from the
  -- scroll position and stop at the footer.
  local lines = selected.lines
  local totalLines = #lines
  local bottom = height - 18
  local y = DETAIL_HEADER_HEIGHT
  local index = detailScroll + 1
  while index <= totalLines do
    local line = lines[index]
    local rowHeight = line.preview and (line.height + 6) or LINE
    if y + rowHeight > bottom then break end
    if line.preview then
      local boxX = 8 + 24
      graphics:color(40, 40, 40, 200); graphics:frect(boxX, y, line.width, line.height); graphics:color()
      graphics:resource(selected.name, boxX, y, line.width, line.height)
      graphics:color(90, 90, 90); graphics:rect(boxX, y, line.width, line.height); graphics:color()
      setColor(graphics, COLOR_MUTED)
      graphics:text(("%dx%d, shown %dx%d"):format(line.imageWidth, line.imageHeight, line.width, line.height),
        boxX + line.width + 8, y)
      graphics:color()
    else
      setColor(graphics, line.color)
      graphics:text(ellipsis(line.text, detailMaxCharacters), 8, y)
      graphics:color()
    end
    y = y + rowHeight
    index = index + 1
  end
  local lastShown = index - 1
  if detailScroll > 0 or lastShown < totalLines then
    setColor(graphics, COLOR_MUTED)
    graphics:text(("lines %d-%d of %d (wheel scrolls)"):format(detailScroll + 1, lastShown, totalLines), 8, height - 16)
    graphics:color()
  end
  graphics:color(120, 120, 120); graphics:rect(0, 0, width, height); graphics:color()
end

-- The furthest the panel scrolls: the first row from which the rest fits above the footer, rows being LINE
-- tall except a preview row.
local function maxDetailScroll()
  local lines = selected.lines
  local room = (detailHeight - 18) - DETAIL_HEADER_HEIGHT
  local used = 0
  for index = #lines, 1, -1 do
    local line = lines[index]
    used = used + (line.preview and (line.height + 6) or LINE)
    if used > room then return index end
  end
  return 0
end

local function scrollDetail(amountLines)
  if not selected then return end
  detailScroll = math.max(0, math.min(detailScroll + amountLines, maxDetailScroll()))
end

-- ================================================================================ the window

-- The content box: what window:size(w, h) wrote, what window:size() reads, and the box the grip drives.
local function contentBox()
  local box = window:size()
  if not box then return WINDOW_WIDTH, WINDOW_HEIGHT end
  return math.max(1, box.w), math.max(1, box.h)
end

-- Place every child from the content box. The grip writes the size on every pointer move, so this is
-- called from Update whenever the box moved, which is what makes the resize live.
local function layout()
  local width, height = contentBox()
  laidOutWidth, laidOutHeight = width, height
  local listHeight = math.max(1, height - TOOLBAR_HEIGHT - STATUS_HEIGHT)
  detailWidth = math.max(1, width - LIST_WIDTH - GAP)
  detailHeight = height
  detailMaxCharacters = math.max(8, math.floor((detailWidth - 16) / CHARACTER_WIDTH))
  resourceList:size(LIST_WIDTH, listHeight)
  statusLabel:position(0, TOOLBAR_HEIGHT + listHeight + 4)
  detailPanel:size(detailWidth, detailHeight)
  if selected then scrollDetail(0) end          -- a shorter panel may leave the scroll past its end
end

local function open()
  if window then return end
  listDirty = true
  window = hafen.ui():window():title("Resource Stack"):size(WINDOW_WIDTH, WINDOW_HEIGHT):position(80, 60)
  window:resizable(true)                        -- the client's own corner grip
  window:remember("window")                     -- the place and the size

  searchEntry = hafen.ui():entry():parent(window):position(0, 0):size(LIST_WIDTH - FETCH_BUTTON_WIDTH - 4):value(searchText)
  searchEntry:tooltip("part of a resource name: gfx/hud, terobjs/trees, sfx -- or a full name for Fetch")
  fetchButton = hafen.ui():button():parent(window):position(LIST_WIDTH - FETCH_BUTTON_WIDTH, 0):size(FETCH_BUTTON_WIDTH):text("Fetch")
  fetchButton:tooltip("ask the client for the name typed in the box")
  resourceList = hafen.ui():listbox():parent(window):position(0, TOOLBAR_HEIGHT):size(LIST_WIDTH, 1):rowHeight(ROW_HEIGHT)
  statusLabel = hafen.ui():label():parent(window):position(0, TOOLBAR_HEIGHT):text("")
  detailPanel = hafen.ui():widget():parent(window):position(LIST_WIDTH + GAP, 0):size(1, 1):name("detail")
  layout()

  searchEntry:on("Changed", function(text)
    searchText = text
    listDirty = true
  end)
  searchEntry:on("Submitted", function() fetchTyped() end)
  fetchButton:on("Pressed", function() fetchTyped() end)
  resourceList:on("Changed", function(rowName)
    if type(rowName) == "string" then selectResource(rowName) end
  end)
  detailPanel:on("Draw", drawDetail)
  detailPanel:on("Wheel", function(event)
    scrollDetail(((event:amount() > 0) and 1 or -1) * WHEEL_LINES)
    event:preventDefault()
  end)
  window:on("Update", function(deltaTime)
    if not window:visible() then return end     -- hidden by the X: nothing to lay out, list or poll
    local width, height = contentBox()
    if width ~= laidOutWidth or height ~= laidOutHeight then layout() end
    listTick(deltaTime)
    pollSelected()
  end)
  -- Once, on release: the floor is written here and not during the drag, where the grip and this
  -- handler would take turns writing the size.
  window:on("Resized", function(event)
    local clampedWidth = math.max(MIN_WINDOW_WIDTH, event:w())
    local clampedHeight = math.max(MIN_WINDOW_HEIGHT, event:h())
    if clampedWidth ~= event:w() or clampedHeight ~= event:h() then window:size(clampedWidth, clampedHeight) end
  end)
  window:on("Close", function(event)
    event:preventDefault()                      -- the X hides; the window and what it shows stay
    window:visible(false)
  end)
  hafen.log():write(NAME .. ": window up -- pick a resource, or type a name and Fetch; :resourcestack toggles it")
end

hafen.console():on("resourcestack", function()
  hafen.timer():after(0, function()
    if window and window:exists() then
      window:visible(not window:visible())
    else
      window = nil
      open()
    end
  end)
end)
