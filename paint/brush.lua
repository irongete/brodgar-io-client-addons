-- Paint -- draw on the ground with the mouse, in colour, and rub it out again.
--
-- The manifest runs the files in order into one environment; each adds its module under `Paint`:
--   brush.lua     the tools, the picked tool and the width, and the sizes derived from them (this file)
--   geometry.lua  the convex rings a stroke is built from, and the distance test the eraser uses
--   sheet.lua     what is on the ground: the patches laid and the pieces still down
--   stroke.lua    one stroke, from the press on the map to the release
--   drawings.lua  the drawings saved in the store by name, and laying one again
--   window.lua    the tool window
--   main.lua      the map view subscriptions and the action-menu button, per character in the world

Paint = {}
Paint.NAME = "Paint"

local Brush = {}
Paint.Brush = Brush

-- Fully opaque: a long stroke spans several patches, and a translucent fill shows a brighter seam where two
-- of them overlap.
Brush.PENCILS = {
  {key = "red",    color = {222,  62,  52, 255}},
  {key = "orange", color = {235, 140,  40, 255}},
  {key = "yellow", color = {242, 212,  64, 255}},
  {key = "green",  color = { 64, 202,  96, 255}},
  {key = "blue",   color = { 62, 142, 236, 255}},
  {key = "white",  color = {244, 244, 244, 255}},
}
Brush.ERASER = #Brush.PENCILS + 1 -- the tool after the last pencil
Brush.TOOL_COUNT = Brush.ERASER

-- The slider's range, in tenths of a world unit (a tile is 11 units).
Brush.MIN_WIDTH_TENTHS = 2
Brush.MAX_WIDTH_TENTHS = 40

local MIN_SAMPLE_STEP = 0.3       -- world units the pointer travels between two segments, at the least
local SAMPLE_STEP_OF_WIDTH = 0.25 -- above that floor, the share of the stroke's width one segment spans
local MIN_RUB_RADIUS = 0.15       -- the smallest the eraser gets, however low the slider goes

Brush.tool = nil       -- 1..#PENCILS, ERASER, or nil while no tool is picked
Brush.widthTenths = 8  -- the slider's value

function Brush.isEraser()
  return Brush.tool == Brush.ERASER
end

function Brush.halfWidth()
  return (Brush.widthTenths / 10) / 2
end

-- The eraser's reach is half the slider, so it matches the stroke a pencil at that setting lays.
function Brush.rubRadius()
  return math.max(MIN_RUB_RADIUS, Brush.halfWidth())
end

-- How far the eraser travels between two sweeps of the marks. A small eraser sweeps finely, or it steps over
-- pieces it was dragged across.
function Brush.rubStep()
  return math.max(MIN_RUB_RADIUS, Brush.rubRadius() * 0.5)
end

-- How far the pointer travels before another segment is laid: a fraction of the width, so a curve is made of
-- segments short enough not to show their corners.
function Brush.sampleStep()
  return math.max(MIN_SAMPLE_STEP, (Brush.widthTenths / 10) * SAMPLE_STEP_OF_WIDTH)
end

-- LuaJ's string.format ignores a precision, so the tenth is written by hand.
function Brush.formatTenths(tenths)
  return math.floor(tenths / 10) .. "." .. (tenths % 10)
end
