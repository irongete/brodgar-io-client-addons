-- =============================================================================
-- Multi-Session - Configuration
-- Defines the global namespace and shared configuration constants.
-- =============================================================================

MultiSession = {}
SessionManager = MultiSession

MultiSession.Config = {
  -- UI Layout Dimensions
  PADDING = 6,
  GAP_SIZE = 2,
  NAME_BUTTON_WIDTH = 150,
  CLOSE_BUTTON_WIDTH = 24,
  ROW_WIDTH = 150 + 2 + 24,
  SEPARATOR_HEIGHT = 6,

  -- Options Panel Dimensions
  REORDER_BUTTON_WIDTH = 50,
  REORDER_ROW_GAP = 4,

  DEFAULT_WINDOW_X = 60,
  DEFAULT_WINDOW_Y = 60,
  SAVE_INTERVAL_SECONDS = 2,

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
