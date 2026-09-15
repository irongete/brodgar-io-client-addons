-- =============================================================================
-- Multi-Session - Entry Point
-- Coordinates modules, registers keybindings, and timers.
-- =============================================================================

local configuration = MultiSession.Config

-- Centers the camera on the active player character in RTS camera mode.
hafen.client():options():keybindings():on("Focus selection", function()
  if hafen.client():options():camera():mode() ~= "rts" then
    return
  end
  local current_session = hafen.session():current()
  local player_subsystem = current_session and current_session:player()
  local player_gob = player_subsystem and player_subsystem:gob()
  local character_position = player_gob and player_gob:position()
  if not character_position then
    return
  end
  current_session:world():focus(character_position)
end)

-- Cycles through available connected sessions sequentially.
local function cycle_next_session()
  local session_list = hafen.session():list()
  if #session_list == 0 then
    return
  end

  local current_session = hafen.session():current()
  local current_session_index = 0
  for session_index, session in ipairs(session_list) do
    if session == current_session then
      current_session_index = session_index
      break
    end
  end

  for step_offset = 1, #session_list do
    local candidate_index = ((current_session_index + step_offset - 1) % #session_list) + 1
    local candidate_session = session_list[candidate_index]
    local success = pcall(function()
      hafen.session():current(candidate_session)
    end)
    if success then
      return
    end
  end
end

hafen.client():options():keybindings():on("Select next session", cycle_next_session)
hafen.client():options():keybindings():on("Select character", MultiSession.SelectionCircles.toggle_character_pick)

-- Periodically saves the window coordinates to persistent storage
hafen.timer():every(configuration.SAVE_INTERVAL_SECONDS, MultiSession.UI.save_window_position)

-- Periodically retries creating selection circles that were not yet loaded
hafen.timer():every(configuration.RETRY_INTERVAL_SECONDS, MultiSession.SelectionCircles.retry_pending_circles)

-- Subscribes to session lifecycle events to keep UI and selection circles synchronized
for _, event_name in ipairs({"SessionAdded", "SessionEnteredWorld", "SessionSelected", "SessionRemoved"}) do
  hafen.event():on(event_name, function(session)
    hafen.timer():after(0, function()
      local pending_account = MultiSession.UI.get_pending_switch_account()
      if pending_account and session and (event_name == "SessionAdded" or event_name == "SessionEnteredWorld") then
        local session_account = session:user()
        if session_account == pending_account then
          local switch_success = MultiSession.UI.switch_to_session(session_account)
          if switch_success then
            MultiSession.UI.clear_pending_switch_account()
          end
        end
      end

      MultiSession.UI.refresh_session_window()
      MultiSession.SelectionCircles.synchronize_selection_circles()
    end)
  end)
end

-- Initial startup setup
MultiSession.UI.create_session_window()
MultiSession.SelectionCircles.synchronize_selection_circles()
