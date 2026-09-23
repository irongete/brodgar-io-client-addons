-- =============================================================================
-- Multi-Session - User Interface Module
-- Manages the session dock on the left edge of the screen, its rows, the
-- portraits, and viewport switching.
--
-- The dock is a bare surface in the addon layer, above every session and the
-- login screen, held to the screen's left edge by a stylesheet anchor. Each
-- logged-in character has a row: its portrait, the name button and a log-out
-- button. Below them a divider, one button per saved account that is not
-- logged in, and "+" for the login screen. With "Show names" off the dock is
-- a column of squares: the portraits, a square with its initial per saved
-- account, and a square "+". Horizontal, the same items run across the screen.
--
-- A portrait is a mirror (hafen.ui():mirror()) of the client's own HUD
-- portrait: the Avaview stays in its HUD and the mirror shows its picture,
-- drawn again every frame, whether or not that session is on screen. Until a
-- session has a HUD the row paints the character's initial instead.
-- =============================================================================

MultiSession.UI = {}
SessionManager.UI = MultiSession.UI

local configuration = MultiSession.Config

-- Dock and widget handles
local dock = nil
local session_rows = {}
local saved_session_buttons = {}
local saved_session_squares = {}
local divider = nil
local new_session_button = nil
local new_session_square = nil

local initial_font = hafen.font():get("serif"):derive():size(configuration.INITIAL_FONT_SIZE):bold(true)

-- Pending account name awaiting connection and viewport switch
local pending_switch_account_name = nil

-- Anchored, the dock is placed by this rule alone: the middle of the chosen edge, moved along that edge by the
-- "Position along the edge" option. Free, the rule is released and the dock is dragged by its grip, its place
-- kept in the store. The sheet is installed by create_dock, once the dock exists and is named.
local sheet = hafen.ui():sheet()
local DOCK_RULE = "[name=multi-session/dock]"

-- The grip: an invisible child under everything else in the dock, so a press that no button or portrait takes
-- drags the dock while it is free
local grip = nil

-- Where a free dock was last dropped (x, y in design pixels)
local stored_dock_place = hafen.store():var("dock")

-- Places the dock as the options say: anchors it to an edge, or frees it. On an installed sheet a rule written or
-- released applies at once, and widget:position(nil) hands a freed dock's place back to the rule.
function MultiSession.UI.apply_dock_placement()
  local placement = MultiSession.Options.get_placement()
  local dock_up = dock and dock:exists()

  if placement == "free" then
    sheet:rule(DOCK_RULE):release()
    if dock_up then
      local place = stored_dock_place
      if not (place.x and place.y) then
        local current_place = dock:position()
        place = {x = current_place.x, y = current_place.y}
      end
      dock:position(place.x, place.y)
      dock:draggable(grip)
    end
    return
  end

  -- The offset runs along the edge (down a side edge, across the top or the bottom one) and the inset runs in
  -- from it, towards the middle of the screen. The anchor meets the dock's middle to the edge's middle, so half
  -- the dock's length along the edge is added: its top (or its left end) stands at the middle plus the offset,
  -- and a dock that grows with another account grows down or right, never up or left
  local edge_offset = MultiSession.Options.get_edge_offset()
  local edge_inset = MultiSession.Options.get_edge_inset()
  local sideways = (placement == "left" or placement == "right")
  local half_length = 0
  if dock_up then
    local dock_size = dock:size()
    half_length = math.floor((sideways and dock_size.h or dock_size.w) / 2)
  end
  local inwards = {left = {edge_inset, 0}, right = {-edge_inset, 0}, top = {0, edge_inset}, bottom = {0, -edge_inset}}
  local along = sideways and {0, edge_offset + half_length} or {edge_offset + half_length, 0}
  sheet:rule(DOCK_RULE):anchor{
    to = "screen",
    at = placement,
    offset = {along[1] + inwards[placement][1], along[2] + inwards[placement][2]},
  }
  if dock_up then
    dock:draggable(nil)
    dock:position(nil)
  end
end

MultiSession.UI.apply_dock_placement()

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
  MultiSession.UI.refresh_dock()
end

-- =============================================================================
-- Portraits
-- =============================================================================

-- Finds the HUD's own portrait: the Avaview framed directly under the top-left panel. The fight view's
-- avatars are framed too, but deeper, under the fight view itself. nil until the session has a HUD.
local function find_hud_portrait(session)
  if not (session and session:exists()) then
    return nil
  end
  for _, candidate in ipairs(session:ui():matchAll("@Hidepanel @Frame @Avaview")) do
    local frame = candidate:parent()
    local panel = frame and frame:parent()
    if frame and frame:type() == "Frame" and panel and panel:type() == "Hidepanel" then
      return candidate
    end
  end
  return nil
end

-- Points a row's mirror at its session's HUD portrait once there is one, and shows the mirror over the initial.
local function update_row_portrait(row, session)
  if row.mirror:source() == nil then
    local portrait = find_hud_portrait(session)
    if portrait then
      row.mirror:source(portrait):size(configuration.PORTRAIT_SIZE, configuration.PORTRAIT_SIZE)
    end
  end

  local has_portrait = row.mirror:source() ~= nil
  if row.mirror:visible() ~= has_portrait then
    row.mirror:visible(has_portrait)
  end
  if row.placeholder:visible() ~= (not has_portrait) then
    row.placeholder:visible(not has_portrait)
  end
end

-- =============================================================================
-- Rows
-- =============================================================================

-- Paints one glyph in the middle of a square: an initial, or the "+".
local function draw_centered_glyph(draw_event, glyph, color)
  draw_event:g():atext(glyph, draw_event:w() / 2, draw_event:h() / 2, 0.5, 0.5, {
    font = initial_font,
    color = color,
  })
end

-- Creates a portrait-sized square in the dock, dressed like the portraits.
local function create_square(name)
  local square = hafen.ui():widget()
    :parent(dock)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.PORTRAIT_SIZE, configuration.PORTRAIT_SIZE)
    :name(name)
  square:stock{
    bg = {color = configuration.PORTRAIT_FILL},
    border = {color = configuration.PORTRAIT_EDGE, width = 1},
  }
  return square
end

-- Creates the initial a row paints in place of its portrait until the session has a HUD.
local function create_portrait_placeholder(row)
  local placeholder = create_square("placeholder")

  placeholder:on("Draw", function(draw_event)
    if row.initial ~= "" then
      draw_centered_glyph(draw_event, row.initial, configuration.INITIAL_COLOR)
    end
  end)

  return placeholder
end

-- A left click on a widget hands the screen to the account, as the row's name button does. The press runs
-- inside the dock's tree, so the switch is deferred to the step like every other press here.
local function switch_on_click(widget, account_name)
  widget:on("MouseDown", function(press_event)
    if press_event:button() ~= 1 then
      return
    end
    press_event:preventDefault()
    hafen.timer():after(0, function()
      MultiSession.UI.switch_to_session(account_name)
    end)
  end)
end

-- Creates the portrait slot, the switch button and the log-out button for a single session row.
function MultiSession.UI.create_session_row(account_name)
  local row = {
    initial = "",
  }

  row.placeholder = create_portrait_placeholder(row)

  -- The portrait: a mirror of the HUD's Avaview, pointed at it once the session has a HUD
  row.mirror = hafen.ui():mirror()
    :parent(dock)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.PORTRAIT_SIZE, configuration.PORTRAIT_SIZE)
    :name("portrait")
    :visible(false)
  row.mirror:stock{
    bg = {color = configuration.PORTRAIT_FILL},
    border = {color = configuration.PORTRAIT_EDGE, width = 1},
  }

  -- The portrait, and the initial standing in for it, switch like the name button
  switch_on_click(row.mirror, account_name)
  switch_on_click(row.placeholder, account_name)

  row.select_button = hafen.ui():button()
    :parent(dock)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.NAME_BUTTON_WIDTH)
    :text(account_name)

  row.select_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.UI.switch_to_session(account_name)
    end)
  end)

  row.close_button = hafen.ui():button()
    :parent(dock)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.CLOSE_BUTTON_WIDTH)
    :text("X")
    :tooltip("Log this character out")

  row.close_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.UI.close_session(account_name)
    end)
  end)

  return row
end

-- Removes the widgets of a session row.
local function destroy_session_row(row)
  row.placeholder:destroy()
  row.mirror:destroy()
  row.select_button:destroy()
  row.close_button:destroy()
end

-- Connects an inactive saved session and transitions the client viewport once connected.
function MultiSession.UI.connect_saved_session(account_name)
  local target_session = hafen.session():get(account_name)
  if target_session and target_session:exists() then
    MultiSession.UI.switch_to_session(account_name)
    return
  end

  pending_switch_account_name = account_name
  MultiSession.UI.refresh_dock()

  local success, error_message = pcall(function()
    hafen.session():add(account_name)
  end)

  if not success then
    pending_switch_account_name = nil
    MultiSession.UI.refresh_dock()
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
        MultiSession.UI.refresh_dock()
        return
      end
    end

    retry_count = retry_count + 1
    if retry_count < 30 and pending_switch_account_name == account_name then
      hafen.timer():after(0.2, attempt_pending_switch)
    else
      if pending_switch_account_name == account_name then
        pending_switch_account_name = nil
        MultiSession.UI.refresh_dock()
      end
    end
  end

  hafen.timer():after(0.2, attempt_pending_switch)
end

-- Creates a button for an inactive saved session.
function MultiSession.UI.create_saved_session_button(account_name)
  local connect_button = hafen.ui():button()
    :parent(dock)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.ROW_WIDTH)
    :text(account_name)
    :tooltip(account_name)

  connect_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.UI.connect_saved_session(account_name)
    end)
  end)

  return connect_button
end

-- Creates the square for an inactive saved session, shown when names are off: its initial, and a click connects.
function MultiSession.UI.create_saved_session_square(account_name)
  local square_state = {
    initial = string.upper(string.sub(account_name, 1, 1)),
    pending = false,
  }

  local square = create_square("saved"):tooltip(account_name)

  square:on("Draw", function(draw_event)
    local color = square_state.pending and configuration.INITIAL_PENDING_COLOR or configuration.INITIAL_COLOR
    draw_centered_glyph(draw_event, square_state.initial, color)
  end)

  square:on("MouseDown", function(press_event)
    if press_event:button() ~= 1 then
      return
    end
    press_event:preventDefault()
    hafen.timer():after(0, function()
      MultiSession.UI.connect_saved_session(account_name)
    end)
  end)

  return {
    widget = square,
    state = square_state,
  }
end

-- Moves a widget only when its place changed, to prevent widget repaint flicker.
local function place(widget, x, y)
  local current_position = widget:position()
  if current_position.x ~= x or current_position.y ~= y then
    widget:position(x, y)
  end
end

-- Shows or hides a widget only when its state changed.
local function show(widget, shown)
  if widget:visible() ~= shown then
    widget:visible(shown)
  end
end

-- =============================================================================
-- The dock
-- =============================================================================

-- Synchronizes the dock's rows with the list of currently active and saved sessions, laying them out along
-- the dock's axis: down the dock when it is vertical, across it when it is horizontal.
function MultiSession.UI.refresh_dock()
  if not (dock and dock:exists()) then
    return
  end

  local session_list = hafen.session():list()
  local current_session = hafen.session():current()
  local seen_active_accounts = {}

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

  local show_names = MultiSession.Options.is_show_names_enabled()
  local show_current = MultiSession.Options.is_show_current_enabled()
  local horizontal = MultiSession.Options.is_horizontal()

  -- A row is [portrait][name][X] left to right, or the portrait's square alone with names off
  local row_length = show_names and configuration.ROW_WIDTH or configuration.PORTRAIT_SIZE

  -- The dock's axis: items follow one another along it from PADDING on, and the dock is one item wide across
  -- it. Vertical, along is y and the breadth is a row's width; horizontal, along is x and the breadth is a row's
  -- height, the portrait's. An item narrower than the breadth is centred across it.
  local along = configuration.PADDING
  local breadth = horizontal and configuration.PORTRAIT_SIZE or row_length

  local function item_origin(size_across)
    local across = configuration.PADDING + math.floor((breadth - size_across) / 2)
    if horizontal then
      return along, across
    end
    return across, along
  end

  local function advance(length)
    along = along + length + configuration.GAP_SIZE
  end

  -- A wide button (a saved account's, the "+") lies along the axis with its width and across it with its height.
  -- The width is ROW_WIDTH, the one every wide button is built with: a button just built still reads the
  -- control's default width from :size(), which would centre it off to the right on the first layout.
  local function place_wide_button(button)
    local button_height = button:size().h
    local x, y = item_origin(horizontal and button_height or configuration.ROW_WIDTH)
    place(button, x, y)
    advance(horizontal and configuration.ROW_WIDTH or button_height)
  end

  local function place_square(square)
    local x, y = item_origin(configuration.PORTRAIT_SIZE)
    place(square, x, y)
    advance(configuration.PORTRAIT_SIZE)
  end

  -- Layout active session rows
  local shown_rows = 0
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
    row.initial = string.upper(string.sub(display_label, 1, 1))

    -- Only update properties if changed to prevent widget repaint flicker
    if row.select_button:text() ~= button_label then
      row.select_button:text(button_label)
    end

    -- Hovering the row says who it is: the character's name once the session is in the world, the account's
    -- name while it is still on the login or the character screen
    if row.tooltip ~= display_label then
      row.tooltip = display_label
      row.mirror:tooltip(display_label)
      row.placeholder:tooltip(display_label)
      row.select_button:tooltip(display_label)
    end

    -- The row of the character on screen can be left out, and so can a hidden account's
    local row_shown = (show_current or (session ~= current_session))
      and not MultiSession.Options.is_account_hidden(account_name)
    row.hidden = not row_shown
    show(row.select_button, row_shown and show_names)
    show(row.close_button, row_shown and show_names)

    if row_shown then
      shown_rows = shown_rows + 1
      update_row_portrait(row, session)

      local row_x, row_y = item_origin(horizontal and configuration.PORTRAIT_SIZE or row_length)
      place(row.placeholder, row_x, row_y)
      place(row.mirror, row_x, row_y)

      -- The buttons follow the portrait, centred on its height
      if show_names then
        local button_offset = math.floor((configuration.PORTRAIT_SIZE - row.select_button:size().h) / 2)
        local name_x = row_x + configuration.PORTRAIT_SIZE + configuration.GAP_SIZE
        local close_x = name_x + configuration.NAME_BUTTON_WIDTH + configuration.GAP_SIZE
        place(row.select_button, name_x, row_y + button_offset)
        place(row.close_button, close_x, row_y + button_offset)
      end

      advance(horizontal and row_length or configuration.PORTRAIT_SIZE)
    else
      show(row.placeholder, false)
      show(row.mirror, false)
    end
  end

  -- Clean up rows for disconnected sessions
  for account_name, row in pairs(session_rows) do
    if not seen_active_accounts[account_name] then
      destroy_session_row(row)
      session_rows[account_name] = nil
    end
  end

  -- Filter remembered accounts that are not currently active, respecting current sort order
  local saved_accounts = MultiSession.Options.get_ordered_saved_accounts()
  local inactive_saved_accounts = {}
  for _, account_name in ipairs(saved_accounts) do
    if not seen_active_accounts[account_name] and not MultiSession.Options.is_account_hidden(account_name) then
      table.insert(inactive_saved_accounts, account_name)
    end
  end

  -- A thin divider between the session rows that are shown and the saved accounts
  local should_show_divider = (shown_rows > 0 and #inactive_saved_accounts > 0)
  if should_show_divider then
    if not (divider and divider:exists()) then
      divider = hafen.ui():widget():parent(dock):name("divider")
      divider:stock{bg = {color = configuration.PORTRAIT_EDGE}}
    end

    local divider_width = horizontal and configuration.DIVIDER_THICKNESS or breadth
    local divider_height = horizontal and breadth or configuration.DIVIDER_THICKNESS
    local divider_size = divider:size()
    if divider_size.w ~= divider_width or divider_size.h ~= divider_height then
      divider:size(divider_width, divider_height)
    end

    local divider_x, divider_y = item_origin(breadth)
    place(divider, divider_x, divider_y)
    show(divider, true)
    advance(configuration.DIVIDER_THICKNESS)
  elseif divider and divider:exists() then
    show(divider, false)
  end

  -- Layout the saved inactive accounts: a wide button with the name, or a square with the initial
  local seen_saved_accounts = {}
  for _, account_name in ipairs(inactive_saved_accounts) do
    seen_saved_accounts[account_name] = true
    local is_pending = (pending_switch_account_name == account_name)

    local connect_button = saved_session_buttons[account_name]
    local square = saved_session_squares[account_name]

    if show_names then
      if not connect_button then
        connect_button = MultiSession.UI.create_saved_session_button(account_name)
        saved_session_buttons[account_name] = connect_button
      end

      local button_label = is_pending and (account_name .. " ...") or account_name
      if connect_button:text() ~= button_label then
        connect_button:text(button_label)
      end

      show(connect_button, true)
      if square then
        show(square.widget, false)
      end
      place_wide_button(connect_button)
    else
      if not square then
        square = MultiSession.UI.create_saved_session_square(account_name)
        saved_session_squares[account_name] = square
      end

      square.state.pending = is_pending
      show(square.widget, true)
      if connect_button then
        show(connect_button, false)
      end
      place_square(square.widget)
    end
  end

  -- Clean up the saved accounts that connected or were forgotten
  for account_name, connect_button in pairs(saved_session_buttons) do
    if not seen_saved_accounts[account_name] then
      connect_button:destroy()
      saved_session_buttons[account_name] = nil
    end
  end
  for account_name, square in pairs(saved_session_squares) do
    if not seen_saved_accounts[account_name] then
      square.widget:destroy()
      saved_session_squares[account_name] = nil
    end
  end

  -- The "+" after every account: the wide button with names on, the square with names off
  if new_session_button and new_session_button:exists() and new_session_square and new_session_square:exists() then
    show(new_session_button, show_names)
    show(new_session_square, not show_names)
    if show_names then
      place_wide_button(new_session_button)
    else
      place_square(new_session_square)
    end
  end

  local dock_length = along - configuration.GAP_SIZE + configuration.PADDING
  local dock_breadth = configuration.PADDING + breadth + configuration.PADDING
  local target_width = horizontal and dock_length or dock_breadth
  local target_height = horizontal and dock_breadth or dock_length
  local current_size = dock:size()

  -- Only resize if the dimensions changed; the anchor is then written again with the new length, so the dock's
  -- top or left end stays put and the growth goes down or right
  if current_size.w ~= target_width or current_size.h ~= target_height then
    dock:size(target_width, target_height)
    if MultiSession.Options.get_placement() ~= "free" then
      MultiSession.UI.apply_dock_placement()
    end
  end
  if grip and grip:exists() then
    local grip_size = grip:size()
    if grip_size.w ~= target_width or grip_size.h ~= target_height then
      grip:size(target_width, target_height)
    end
  end

  local should_be_visible = (#session_list > 0 or #inactive_saved_accounts > 0)
  if dock:visible() ~= should_be_visible then
    dock:visible(should_be_visible)
  end
end

-- Constructs the session dock.
function MultiSession.UI.create_dock()
  if dock and dock:exists() then
    return
  end

  session_rows = {}
  saved_session_buttons = {}
  saved_session_squares = {}
  divider = nil

  -- Named so the anchor rule finds it
  dock = hafen.ui():widget()
    :name("dock")
    :size(configuration.PADDING + configuration.ROW_WIDTH + configuration.PADDING, configuration.PADDING * 2)
  dock:stock{
    bg = {color = configuration.DOCK_BACKGROUND},
    border = {box = configuration.FRAME_BOX, mode = "tile"},
  }

  -- The grip goes in first, so every button and portrait built after it takes its press before the grip does
  grip = hafen.ui():widget()
    :parent(dock)
    :position(0, 0)
    :size(configuration.PADDING + configuration.ROW_WIDTH + configuration.PADDING, configuration.PADDING * 2)

  -- A free dock remembers where it was dropped
  dock:on("Dragged", function(drag_event)
    stored_dock_place.x = drag_event:x()
    stored_dock_place.y = drag_event:y()
  end)

  new_session_button = hafen.ui():button()
    :parent(dock)
    :position(configuration.PADDING, configuration.PADDING)
    :size(configuration.ROW_WIDTH)
    :text("+")
    :tooltip("New session: go to the login screen -- your characters stay logged in")

  new_session_button:on("Pressed", function()
    hafen.timer():after(0, MultiSession.UI.switch_to_login_screen)
  end)

  -- The same "+" as a portrait-sized square, for the dock with names off
  new_session_square = create_square("new")
    :visible(false)
    :tooltip("New session: go to the login screen -- your characters stay logged in")

  new_session_square:on("Draw", function(draw_event)
    draw_centered_glyph(draw_event, "+", configuration.INITIAL_COLOR)
  end)

  new_session_square:on("MouseDown", function(press_event)
    if press_event:button() ~= 1 then
      return
    end
    press_event:preventDefault()
    hafen.timer():after(0, MultiSession.UI.switch_to_login_screen)
  end)

  -- Now that the dock is named, the anchor rule reaches it: installing sweeps every widget already up
  sheet:install()
  MultiSession.UI.apply_dock_placement()

  MultiSession.UI.refresh_dock()
end
