-- =============================================================================
-- Multi-Session - Selection Circles & Character Picker Module
-- Handles terrain patch selection circles and character picking via mouse clicks.
-- =============================================================================

MultiSession.SelectionCircles = {}
SessionManager.SelectionCircles = MultiSession.SelectionCircles

local configuration = MultiSession.Config

-- Selection circle state: [session] = { game_object_id = number, ground_patch = Patch }
local tracked_selection_circles = {}
local pending_circle_retry = false

-- Character picker interaction state
local is_character_pick_active = false
local mouse_controller = hafen.ui():mouse()

-- Generates a ring of polygon coordinates centered around a world position.
function MultiSession.SelectionCircles.create_circle_polygon(center_position)
  local polygon_positions = {}
  for segment_index = 1, configuration.CIRCLE_SEGMENTS do
    local angle_radians = ((segment_index - 1) / configuration.CIRCLE_SEGMENTS) * math.pi * 2
    local offset_position = center_position:offset(
      configuration.ACTIVE_RADIUS * math.cos(angle_radians),
      configuration.ACTIVE_RADIUS * math.sin(angle_radians)
    )
    if not offset_position then
      return nil
    end
    polygon_positions[segment_index] = offset_position
  end
  return polygon_positions
end

-- Checks whether a game object is visible within the active session view.
function MultiSession.SelectionCircles.is_gob_visible_to_session(game_object, current_session)
  if not current_session then
    return false
  end
  return game_object:sessions():find(function(session_handle)
    return session_handle == current_session
  end) ~= nil
end

-- Updates the visual appearance and scale of a selection circle.
function MultiSession.SelectionCircles.update_circle_style(circle_data, is_current_session)
  local circle_color = is_current_session and configuration.ACTIVE_CIRCLE_COLOR or configuration.INACTIVE_CIRCLE_COLOR
  local fill_alpha = is_current_session and configuration.ACTIVE_FILL_ALPHA or configuration.INACTIVE_FILL_ALPHA
  local circle_scale = is_current_session and 1.0 or (configuration.INACTIVE_RADIUS / configuration.ACTIVE_RADIUS)

  circle_data.ground_patch:tint({circle_color[1], circle_color[2], circle_color[3], fill_alpha})
    :border(circle_color, configuration.BORDER_WIDTH)
    :scale(circle_scale)
end

-- Destroys and unregisters the selection circle for a session.
function MultiSession.SelectionCircles.remove_selection_circle(session)
  local circle_data = tracked_selection_circles[session]
  if not circle_data then
    return
  end
  tracked_selection_circles[session] = nil
  if circle_data.ground_patch:exists() then
    hafen.virtual():patch():remove(circle_data.ground_patch)
  end
end

-- Creates a virtual terrain patch selection circle anchored to a character game object.
function MultiSession.SelectionCircles.create_selection_circle(session, game_object)
  local gob_position = game_object:position()
  local polygon_positions = gob_position and MultiSession.SelectionCircles.create_circle_polygon(gob_position)
  if not polygon_positions then
    return nil
  end

  local success, ground_patch = pcall(function()
    return hafen.virtual():patch():add(polygon_positions, game_object)
  end)
  if not (success and ground_patch) then
    return nil
  end

  ground_patch:clickable(is_character_pick_active)
  ground_patch:onClick(function()
    if not is_character_pick_active then
      return
    end
    MultiSession.SelectionCircles.disarm_character_pick()

    -- Defers session switch to the next frame to avoid switching active session during click dispatch.
    local account_name = session:user()
    hafen.timer():after(0, function()
      MultiSession.UI.switch_to_session(account_name)
    end)
  end)

  return {
    game_object_id = game_object:id(),
    ground_patch = ground_patch,
  }
end

-- Re-evaluates and synchronizes selection circles for all connected sessions.
function MultiSession.SelectionCircles.synchronize_selection_circles()
  local session_list = hafen.session():list()
  local current_session = hafen.session():current()
  local should_render_circles = (#session_list > 1)
  local active_circle_sessions = {}
  pending_circle_retry = false

  for _, session in ipairs(session_list) do
    local player_subsystem = should_render_circles and session:character() and session:player()
    local player_gob = player_subsystem and player_subsystem:gob()
    local player_gob_id = player_gob and player_gob:id()
    local existing_circle = tracked_selection_circles[session]

    if player_gob_id and existing_circle and (existing_circle.game_object_id == player_gob_id) and existing_circle.ground_patch:exists() then
      active_circle_sessions[session] = true
      MultiSession.SelectionCircles.update_circle_style(existing_circle, session == current_session)
    elseif player_gob_id then
      MultiSession.SelectionCircles.remove_selection_circle(session)
      local is_visible = MultiSession.SelectionCircles.is_gob_visible_to_session(player_gob, current_session)
      local new_circle = is_visible and MultiSession.SelectionCircles.create_selection_circle(session, player_gob) or nil
      if new_circle then
        tracked_selection_circles[session] = new_circle
        active_circle_sessions[session] = true
        MultiSession.SelectionCircles.update_circle_style(new_circle, session == current_session)
      else
        pending_circle_retry = true
      end
    elseif should_render_circles and session:character() then
      pending_circle_retry = true
    end
  end

  for session in pairs(tracked_selection_circles) do
    if not active_circle_sessions[session] then
      MultiSession.SelectionCircles.remove_selection_circle(session)
    end
  end
end

-- Periodically retries circle creation when entities were pending.
function MultiSession.SelectionCircles.retry_pending_circles()
  if pending_circle_retry then
    MultiSession.SelectionCircles.synchronize_selection_circles()
  end
end

-- Toggles clickability on all active selection circles.
function MultiSession.SelectionCircles.set_circles_clickable(is_clickable)
  for _, circle_data in pairs(tracked_selection_circles) do
    if circle_data.ground_patch:exists() then
      circle_data.ground_patch:clickable(is_clickable)
    end
  end
end

-- Disarms character picking mode and restores standard mouse cursor.
function MultiSession.SelectionCircles.disarm_character_pick()
  is_character_pick_active = false
  MultiSession.SelectionCircles.set_circles_clickable(false)
  mouse_controller:cursor(nil)
end

-- Toggles character selection mode when the hotkey is pressed.
function MultiSession.SelectionCircles.toggle_character_pick()
  if is_character_pick_active then
    MultiSession.SelectionCircles.disarm_character_pick()
    return
  end
  if hafen.session():count() < 2 then
    return
  end
  is_character_pick_active = true
  MultiSession.SelectionCircles.set_circles_clickable(true)
  mouse_controller:cursor("hand")
end

-- Finds the session whose player character matches the clicked game object.
function MultiSession.SelectionCircles.find_session_by_clicked_gob(action_event)
  local clicked_gob = action_event:gob()
  if not clicked_gob then
    return nil
  end
  local clicked_gob_id = clicked_gob:id()
  for _, session in ipairs(hafen.session():list()) do
    local player_subsystem = session:player()
    local player_gob = player_subsystem and player_subsystem:gob()
    if player_gob and (player_gob:id() == clicked_gob_id) then
      return session
    end
  end
  return nil
end

-- Intercepts world clicks while picker is armed to switch to the clicked character.
hafen.event():action():on("click", function(action_event)
  if not is_character_pick_active then
    return
  end
  local source_widget = action_event:widget()
  if not source_widget or source_widget:type() ~= "MapView" then
    return
  end

  local target_session = MultiSession.SelectionCircles.find_session_by_clicked_gob(action_event)
  MultiSession.SelectionCircles.disarm_character_pick()
  if not target_session then
    return
  end
  action_event:preventDefault()

  -- Defers session switch to the next frame to avoid switching active session during click dispatch.
  local account_name = target_session:user()
  hafen.timer():after(0, function()
    MultiSession.UI.switch_to_session(account_name)
  end)
end)
