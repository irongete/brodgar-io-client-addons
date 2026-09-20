-- =============================================================================
-- Multi-Session - Configuration
-- Defines the global namespace and shared configuration constants.
-- =============================================================================

MultiSession = {}
SessionManager = MultiSession

MultiSession.Config = {
  -- Dock Layout Dimensions (design pixels)
  -- The dock's frame is the client's own window box; its edge run is 7 px, the padding adds 2 px inside it.
  FRAME_BOX = "gfx/hud/wnd",
  PADDING = 9,
  GAP_SIZE = 2,
  PORTRAIT_SIZE = 48,
  NAME_BUTTON_WIDTH = 110,
  CLOSE_BUTTON_WIDTH = 24,
  DIVIDER_THICKNESS = 2,

  -- The dock's plate, and the portrait slot's look: the inventory square's own colours, and the initial
  -- drawn until a session has a HUD to mirror
  DOCK_BACKGROUND = {43, 51, 44, 127},
  PORTRAIT_FILL = {36, 52, 38, 125},
  PORTRAIT_EDGE = {20, 28, 21, 167},
  INITIAL_COLOR = {156, 180, 158, 255},
  INITIAL_PENDING_COLOR = {156, 180, 158, 110},
  INITIAL_FONT_SIZE = 22,

  -- Options Panel Dimensions
  REORDER_BUTTON_WIDTH = 50,
  REORDER_ROW_GAP = 4,
  PANELS_GAP = 24,

  -- The account visibility list: its scrolling box takes the page's width left beside the order panel, never
  -- less than the minimum; the room its scrollbar needs is kept clear of the buttons
  VISIBILITY_LIST_HEIGHT = 160,
  VISIBILITY_LIST_MIN_WIDTH = 140,
  VISIBILITY_BAR_ROOM = 20,
  VISIBILITY_BUTTON_WIDTH = 70,
  OFFSET_SLIDER_WIDTH = 200,
  OFFSET_RANGE = 600,
  INSET_RANGE = 400,
  PLACEMENT_DROPDOWN_WIDTH = 160,

  -- Where a free dock stands until it is dragged
  DOCK_DEFAULT_X = 60,
  DOCK_DEFAULT_Y = 60,

  -- Ground Selection Circle Settings (in world units and RGBA values)
  ACTIVE_CIRCLE_COLOR = {64, 255, 64},
  INACTIVE_CIRCLE_COLOR = {255, 255, 255},
  ACTIVE_FILL_ALPHA = 115,
  INACTIVE_FILL_ALPHA = 56,
  BORDER_WIDTH = 0.3,
  ACTIVE_RADIUS = 5,
  INACTIVE_RADIUS = 4,
  CIRCLE_SEGMENTS = 20,
  RETRY_INTERVAL_SECONDS = 0.25,
}

-- A row is the portrait, the name button and the log-out button, side by side
MultiSession.Config.ROW_WIDTH = MultiSession.Config.PORTRAIT_SIZE
  + MultiSession.Config.GAP_SIZE
  + MultiSession.Config.NAME_BUTTON_WIDTH
  + MultiSession.Config.GAP_SIZE
  + MultiSession.Config.CLOSE_BUTTON_WIDTH
