-- =============================================================================
-- Multi-Session - User Interface Module
-- Manages the switcher window, account rows, and viewport switching.
-- =============================================================================

MultiSession.UI = {}
SessionManager.UI = MultiSession.UI

local configuration = MultiSession.Config

-- Window and widget handles
local session_window = nil
local session_rows = {}
local saved_session_buttons = {}
local separator_widget = nil
local new_session_button = nil
local stored_window_position = hafen.store():var("window")

-- Pending account name awaiting connection and viewport switch
local pending_switch_account_name = nil

-- Returns the account name of the pending session switch, if any.
function MultiSession.UI.get_pending_switch_account()
  return pending_switch_account_name
end

-- Sets the account name of the pending session switch.
function MultiSession.UI.set_pending_switch_account(account_name)
  pending_switch_account_name = account_name
end

-- Clears the pending session switch.
function MultiSession.UI.clear_pending_switch_account()
  pending_switch_account_name = nil
end

-- Resolves the character name if available, falling back to the account name.
function MultiSession.UI.get_session_label(session)
  return session:character() or session:user()
end

-- Switches the active client viewport to the specified account session.
function MultiSession.UI.switch_to_session(account_name)
  pending_switch_account_name = nil

  local target_session = hafen.session():get(account_name)
  if not (target_session and target_session:exists()) then
    return false
  end

  -- Sessions still connecting may not possess an active viewport yet.
  local success, error_message = pcall(function()
    hafen.session():current(target_session)
  end)

  if not success and error_message then
    hafen.log():write(error_message)
    return false
  end

  return success
end

-- Logs out and terminates a session by account name.
function MultiSession.UI.close_session(account_name)
  local target_session = hafen.session():get(account_name)
  if target_session and target_session:exists() then
    target_session:close()
  end
end

-- Returns to the client login screen while keeping all current sessions connected.
function MultiSession.UI.switch_to_login_screen()
  pending_switch_account_name = nil
  hafen.session():current(nil)
  MultiSession.UI.refresh_session_window()
end

-- Creates the switch and close buttons for a single session row.
function MultiSession.UI.create_session_row(account_name)
  local select_button = hafen.ui():button()
    :parent(session_window)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.NAME_BUTTON_WIDTH)
    :text(account_name)

  select_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.UI.switch_to_session(account_name)
    end)
  end)

  local close_button = hafen.ui():button()
    :parent(session_window)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.CLOSE_BUTTON_WIDTH)
    :text("X")
    :tooltip("Log this character out")

  close_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.UI.close_session(account_name)
    end)
  end)

  return {
    select_button = select_button,
    close_button = close_button,
  }
end

-- Connects an inactive saved session and transitions the client viewport once connected.
function MultiSession.UI.connect_saved_session(account_name)
  local target_session = hafen.session():get(account_name)
  if target_session and target_session:exists() then
    MultiSession.UI.switch_to_session(account_name)
    return
  end

  pending_switch_account_name = account_name
  MultiSession.UI.refresh_session_window()

  local success, error_message = pcall(function()
    hafen.session():add(account_name)
  end)

  if not success then
    pending_switch_account_name = nil
    MultiSession.UI.refresh_session_window()
    if error_message then
      hafen.log():write(error_message)
    end
    return
  end

  -- Periodically polls to switch as soon as the session and its screen are ready
  local retry_count = 0
  local function attempt_pending_switch()
    if pending_switch_account_name ~= account_name then
      return
    end

    local candidate_session = hafen.session():get(account_name)
    if candidate_session and candidate_session:exists() then
      local switch_success = MultiSession.UI.switch_to_session(account_name)
      if switch_success then
        pending_switch_account_name = nil
        MultiSession.UI.refresh_session_window()
        return
      end
    end

    retry_count = retry_count + 1
    if retry_count < 30 and pending_switch_account_name == account_name then
      hafen.timer():after(0.2, attempt_pending_switch)
    else
      if pending_switch_account_name == account_name then
        pending_switch_account_name = nil
        MultiSession.UI.refresh_session_window()
      end
    end
  end

  hafen.timer():after(0.2, attempt_pending_switch)
end

-- Creates a button for an inactive saved session.
function MultiSession.UI.create_saved_session_button(account_name)
  local connect_button = hafen.ui():button()
    :parent(session_window)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.ROW_WIDTH)
    :text(account_name)
    :tooltip("Connect saved session: " .. account_name)

  connect_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.UI.connect_saved_session(account_name)
    end)
  end)

  return connect_button
end

-- Synchronizes UI rows with the list of currently active and saved sessions.
function MultiSession.UI.refresh_session_window()
  if not (session_window and session_window:exists()) then
    return
  end

  local session_list = hafen.session():list()
  local current_session = hafen.session():current()
  local seen_active_accounts = {}
  local vertical_offset = configuration.PADDING

  -- Sort active sessions based on user preference
  if MultiSession.Options.is_sort_by_name_enabled() then
    table.sort(session_list, function(first_session, second_session)
      local first_label = MultiSession.UI.get_session_label(first_session)
      local second_label = MultiSession.UI.get_session_label(second_session)
      return string.lower(first_label) < string.lower(second_label)
    end)
  else
    local ordered_saved_accounts = MultiSession.Options.get_ordered_saved_accounts()
    local account_rank = {}
    for rank_index, account_name in ipairs(ordered_saved_accounts) do
      account_rank[account_name] = rank_index
    end

    table.sort(session_list, function(first_session, second_session)
      local first_rank = account_rank[first_session:user()] or 999999
      local second_rank = account_rank[second_session:user()] or 999999
      if first_rank ~= second_rank then
        return first_rank < second_rank
      end
      return string.lower(first_session:user()) < string.lower(second_session:user())
    end)
  end

  -- Layout active session rows
  for _, session in ipairs(session_list) do
    local account_name = session:user()
    seen_active_accounts[account_name] = true

    local row = session_rows[account_name]
    if not row then
      row = MultiSession.UI.create_session_row(account_name)
      session_rows[account_name] = row
    end

    local display_label = MultiSession.UI.get_session_label(session)
    local button_label = (session == current_session) and ("* " .. display_label) or display_label

    -- Only update properties if changed to prevent widget repaint flicker
    if row.select_button:text() ~= button_label then
      row.select_button:text(button_label)
    end

    local select_position = row.select_button:position()
    if select_position.x ~= configuration.PADDING or select_position.y ~= vertical_offset then
      row.select_button:position(configuration.PADDING, vertical_offset)
    end

    local close_target_x = configuration.PADDING + configuration.NAME_BUTTON_WIDTH + configuration.GAP_SIZE
    local close_position = row.close_button:position()
    if close_position.x ~= close_target_x or close_position.y ~= vertical_offset then
      row.close_button:position(close_target_x, vertical_offset)
    end

    vertical_offset = vertical_offset + row.select_button:size().h + configuration.GAP_SIZE
  end

  -- Clean up rows for disconnected sessions
  for account_name, row in pairs(session_rows) do
    if not seen_active_accounts[account_name] then
      row.select_button:destroy()
      row.close_button:destroy()
      session_rows[account_name] = nil
    end
  end

  -- Filter remembered accounts that are not currently active, respecting current sort order
  local saved_accounts = MultiSession.Options.get_ordered_saved_accounts()
  local inactive_saved_accounts = {}
  for _, account_name in ipairs(saved_accounts) do
    if not seen_active_accounts[account_name] then
      table.insert(inactive_saved_accounts, account_name)
    end
  end

  -- Separator bar directly below active session buttons
  local should_show_separator = (#session_list > 0 and #inactive_saved_accounts > 0)
  if should_show_separator then
    if not (separator_widget and separator_widget:exists()) then
      separator_widget = hafen.ui():separator()
        :parent(session_window)
        :size(configuration.ROW_WIDTH, configuration.SEPARATOR_HEIGHT)
    end

    local separator_position = separator_widget:position()
    if separator_position.x ~= configuration.PADDING or separator_position.y ~= vertical_offset then
      separator_widget:position(configuration.PADDING, vertical_offset)
    end

    if separator_widget:visible() ~= true then
      separator_widget:visible(true)
    end

    vertical_offset = vertical_offset + configuration.SEPARATOR_HEIGHT + configuration.GAP_SIZE
  elseif separator_widget and separator_widget:exists() then
    if separator_widget:visible() ~= false then
      separator_widget:visible(false)
    end
  end

  -- Layout buttons for saved inactive accounts
  local seen_saved_accounts = {}
  for _, account_name in ipairs(inactive_saved_accounts) do
    seen_saved_accounts[account_name] = true

    local connect_button = saved_session_buttons[account_name]
    if not connect_button then
      connect_button = MultiSession.UI.create_saved_session_button(account_name)
      saved_session_buttons[account_name] = connect_button
    end

    local button_label = account_name
    if pending_switch_account_name == account_name then
      button_label = account_name .. " ..."
    end

    if connect_button:text() ~= button_label then
      connect_button:text(button_label)
    end

    local button_position = connect_button:position()
    if button_position.x ~= configuration.PADDING or button_position.y ~= vertical_offset then
      connect_button:position(configuration.PADDING, vertical_offset)
    end

    vertical_offset = vertical_offset + connect_button:size().h + configuration.GAP_SIZE
  end

  -- Clean up buttons for saved accounts that connected or were forgotten
  for account_name, connect_button in pairs(saved_session_buttons) do
    if not seen_saved_accounts[account_name] then
      connect_button:destroy()
      saved_session_buttons[account_name] = nil
    end
  end

  -- Position the "New session" button below all account rows
  if new_session_button and new_session_button:exists() then
    local new_button_position = new_session_button:position()
    if new_button_position.x ~= configuration.PADDING or new_button_position.y ~= vertical_offset then
      new_session_button:position(configuration.PADDING, vertical_offset)
    end
    vertical_offset = vertical_offset + new_session_button:size().h + configuration.GAP_SIZE
  end

  local target_width = configuration.PADDING + configuration.ROW_WIDTH + configuration.PADDING
  local target_height = vertical_offset - configuration.GAP_SIZE + configuration.PADDING
  local current_size = session_window:size()

  -- Only resize if the dimensions changed to avoid repainting window chrome
  if current_size.w ~= target_width or current_size.h ~= target_height then
    session_window:size(target_width, target_height)
  end

  local should_be_visible = (#session_list > 0 or #inactive_saved_accounts > 0)
  if session_window:visible() ~= should_be_visible then
    session_window:visible(should_be_visible)
  end
end

-- Constructs the main session switcher window.
function MultiSession.UI.create_session_window()
  if session_window and session_window:exists() then
    return
  end

  session_rows = {}
  saved_session_buttons = {}
  separator_widget = nil

  session_window = hafen.ui():window()
    :title("Sessions")
    :position(
      stored_window_position.x or configuration.DEFAULT_WINDOW_X,
      stored_window_position.y or configuration.DEFAULT_WINDOW_Y
    )
    :size(configuration.PADDING + configuration.ROW_WIDTH + configuration.PADDING, configuration.PADDING * 2)

  new_session_button = hafen.ui():button()
    :parent(session_window)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.ROW_WIDTH)
    :text("New session")
    :tooltip("Go to the login screen -- your characters stay logged in")

  new_session_button:on("Pressed", function()
    hafen.timer():after(0, MultiSession.UI.switch_to_login_screen)
  end)

  session_window:on("Close", function()
    session_window = nil
    session_rows = {}
    saved_session_buttons = {}
    separator_widget = nil
    new_session_button = nil
    pending_switch_account_name = nil
  end)

  MultiSession.UI.refresh_session_window()
end

-- Toggles window visibility, destroying or recreating it as needed.
function MultiSession.UI.toggle_session_window()
  if session_window and session_window:exists() then
    session_window:destroy()
    session_window = nil
    session_rows = {}
    saved_session_buttons = {}
    separator_widget = nil
    new_session_button = nil
  else
    MultiSession.UI.create_session_window()
  end
end

-- Saves the current window coordinates to persistent storage.
function MultiSession.UI.save_window_position()
  if session_window and session_window:exists() then
    local window_position = session_window:position()
    if window_position then
      stored_window_position.x = window_position.x
      stored_window_position.y = window_position.y
    end
  end
end
