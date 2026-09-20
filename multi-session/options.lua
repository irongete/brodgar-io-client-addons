-- =============================================================================
-- Multi-Session - Options Module
-- Manages addon options panel, account sorting preferences, and manual ordering.
-- =============================================================================

MultiSession.Options = {}

local client_options = hafen.client():options():addon()
local sort_by_name_option = client_options:boolean("sort_by_name"):default(true):add()
local show_names_option = client_options:boolean("show_names"):default(true):add()
local show_current_option = client_options:boolean("show_current"):default(true):add()
local show_circles_option = client_options:boolean("show_circles"):default(true):add()
local choose_placement_option = client_options:boolean("choose_placement"):default(false):add()
local placement_option = client_options:choice("placement")
  :choices{"Anchor left", "Anchor right", "Anchor top", "Anchor bottom", "Free"}
  :default("Anchor left")
  :add()
local edge_offset_option = client_options:number("edge_offset")
  :range(-MultiSession.Config.OFFSET_RANGE, MultiSession.Config.OFFSET_RANGE)
  :default(0)
  :add()
local edge_inset_option = client_options:number("edge_inset")
  :range(0, MultiSession.Config.INSET_RANGE)
  :default(0)
  :add()
local orientation_option = client_options:choice("orientation")
  :choices{"Vertical", "Horizontal"}
  :default("Vertical")
  :add()

-- The placement choice as the dock reads it
local PLACEMENT_MODES = {
  ["Anchor left"] = "left",
  ["Anchor right"] = "right",
  ["Anchor top"] = "top",
  ["Anchor bottom"] = "bottom",
  ["Free"] = "free",
}
local persistent_settings = hafen.store():var("settings")

-- Queries saved account names remembered by the client engine.
local function fetch_saved_accounts()
  local success, saved_accounts = pcall(function()
    return hafen.session():saved()
  end)
  if success and type(saved_accounts) == "table" then
    return saved_accounts
  end
  return {}
end

-- Checks whether automatic alphabetical sorting is currently active.
function MultiSession.Options.is_sort_by_name_enabled()
  return sort_by_name_option:value() == true
end

-- Checks whether the dock shows the name and log-out buttons beside each portrait.
function MultiSession.Options.is_show_names_enabled()
  return show_names_option:value() == true
end

-- Design pixels the dock's top (or its left end) stands from the middle of the edge it is anchored to, along
-- that edge: down or right when positive, up or left when negative. The dock grows away from that end.
function MultiSession.Options.get_edge_offset()
  return edge_offset_option:value() or 0
end

-- Design pixels an anchored dock stands in from its edge, towards the middle of the screen.
function MultiSession.Options.get_edge_inset()
  return edge_inset_option:value() or 0
end

-- Checks whether the dock lays its rows out across the screen rather than down it.
function MultiSession.Options.is_horizontal()
  return orientation_option:value() == "Horizontal"
end

-- Checks whether the row of the character on screen is shown.
function MultiSession.Options.is_show_current_enabled()
  return show_current_option:value() == true
end

-- Checks whether a coloured circle is drawn on the ground under each character.
function MultiSession.Options.is_show_circles_enabled()
  return show_circles_option:value() == true
end

-- Checks whether the placement choice is in force; unchecked, the dock is anchored to the left edge.
function MultiSession.Options.is_choose_placement_enabled()
  return choose_placement_option:value() == true
end

-- Where the dock stands: "left" or "right" (anchored to that edge), or "free" (dragged where you like).
function MultiSession.Options.get_placement()
  if not MultiSession.Options.is_choose_placement_enabled() then
    return "left"
  end
  return PLACEMENT_MODES[placement_option:value()] or "left"
end

-- Accounts kept out of the dock, logged in or not: {[account_name] = true}.
local function hidden_accounts()
  if not persistent_settings.hidden_accounts then
    persistent_settings.hidden_accounts = {}
  end
  return persistent_settings.hidden_accounts
end

-- Checks whether an account is kept out of the dock.
function MultiSession.Options.is_account_hidden(account_name)
  return hidden_accounts()[account_name] == true
end

-- Shows or hides an account in the dock, and keeps the choice.
function MultiSession.Options.set_account_hidden(account_name, hidden)
  hidden_accounts()[account_name] = hidden or nil
  if MultiSession.UI and MultiSession.UI.refresh_dock then
    hafen.timer():after(0, MultiSession.UI.refresh_dock)
  end
end

-- Reconciles stored manual account order with currently remembered accounts.
function MultiSession.Options.get_manual_accounts_order()
  local saved_accounts = fetch_saved_accounts()
  local saved_set = {}
  for _, account_name in ipairs(saved_accounts) do
    saved_set[account_name] = true
  end

  local existing_order = persistent_settings.manual_account_order or {}
  local reconciled_order = {}
  local seen_accounts = {}

  for _, account_name in ipairs(existing_order) do
    if saved_set[account_name] and not seen_accounts[account_name] then
      table.insert(reconciled_order, account_name)
      seen_accounts[account_name] = true
    end
  end

  for _, account_name in ipairs(saved_accounts) do
    if not seen_accounts[account_name] then
      table.insert(reconciled_order, account_name)
      seen_accounts[account_name] = true
    end
  end

  persistent_settings.manual_account_order = reconciled_order
  return reconciled_order
end

-- Returns saved accounts ordered either alphabetically or by the stored manual order.
function MultiSession.Options.get_ordered_saved_accounts()
  local saved_accounts = fetch_saved_accounts()
  if MultiSession.Options.is_sort_by_name_enabled() then
    local alphabetical_list = {}
    for _, account_name in ipairs(saved_accounts) do
      table.insert(alphabetical_list, account_name)
    end
    table.sort(alphabetical_list, function(first_account, second_account)
      return string.lower(first_account) < string.lower(second_account)
    end)
    return alphabetical_list
  else
    return MultiSession.Options.get_manual_accounts_order()
  end
end

-- Swaps positions of two saved accounts in manual order and updates persistent storage.
function MultiSession.Options.swap_saved_accounts(first_index, second_index)
  local account_list = MultiSession.Options.get_manual_accounts_order()
  if first_index < 1 or first_index > #account_list or second_index < 1 or second_index > #account_list then
    return
  end

  local temporary_holder = account_list[first_index]
  account_list[first_index] = account_list[second_index]
  account_list[second_index] = temporary_holder
  persistent_settings.manual_account_order = account_list

  if MultiSession.UI and MultiSession.UI.refresh_dock then
    hafen.timer():after(0, MultiSession.UI.refresh_dock)
  end
end

local refresh_account_rows = nil

local function build_account_row(container_column, account_index, account_name, total_accounts, is_manual_mode)
  local row_widget = hafen.ui():row()
    :gap(MultiSession.Config.REORDER_ROW_GAP)
    :parent(container_column)
    :enabled(is_manual_mode)

  local up_button = hafen.ui():button()
    :parent(row_widget)
    :size(MultiSession.Config.REORDER_BUTTON_WIDTH)
    :text("Up")
    :tooltip("Move " .. account_name .. " higher in list")
    :enabled(is_manual_mode and account_index > 1)

  up_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.Options.swap_saved_accounts(account_index, account_index - 1)
      refresh_account_rows(container_column)
      MultiSession.Options.order_changed()
    end)
  end)

  local down_button = hafen.ui():button()
    :parent(row_widget)
    :size(MultiSession.Config.REORDER_BUTTON_WIDTH)
    :text("Down")
    :tooltip("Move " .. account_name .. " lower in list")
    :enabled(is_manual_mode and account_index < total_accounts)

  down_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.Options.swap_saved_accounts(account_index, account_index + 1)
      refresh_account_rows(container_column)
      MultiSession.Options.order_changed()
    end)
  end)

  local account_label = hafen.ui():label()
    :parent(row_widget)
    :text(account_name)
    :enabled(is_manual_mode)

  local vertical_offset = math.floor((up_button:size().h - account_label:size().h) / 2)
  if vertical_offset > 0 then
    account_label:rule():margin(0, vertical_offset, 0, 0)
  end
end

-- Called after the manual order moved; the panel points it at its visibility column while it is open.
function MultiSession.Options.order_changed()
end

-- One account of the visibility list: its name, and at the right a button reading "Visible" or "Hidden"
-- that flips on a click. The names are laid in a column of one width so the buttons line up.
local function build_visibility_row(container_column, account_name, name_width)
  local configuration = MultiSession.Config
  local row_widget = hafen.ui():row()
    :gap(configuration.REORDER_ROW_GAP)
    :parent(container_column)

  local account_label = hafen.ui():label()
    :parent(row_widget)
    :text(account_name)

  local function caption()
    return MultiSession.Options.is_account_hidden(account_name) and "Hidden" or "Visible"
  end

  local visibility_button = hafen.ui():button()
    :parent(row_widget)
    :size(configuration.VISIBILITY_BUTTON_WIDTH)
    :text(caption())
    :tooltip("Show or hide " .. account_name .. " in the dock")

  local label_size = account_label:size()
  local button_indent = math.max(0, name_width - label_size.w)
  local label_offset = math.floor((visibility_button:size().h - label_size.h) / 2)
  account_label:rule():margin(0, math.max(0, label_offset), 0, 0)
  visibility_button:rule():margin(button_indent, 0, 0, 0)

  visibility_button:on("Pressed", function()
    hafen.timer():after(0, function()
      MultiSession.Options.set_account_hidden(account_name, not MultiSession.Options.is_account_hidden(account_name))
      if visibility_button:exists() then
        visibility_button:text(caption())
      end
    end)
  end)
end

-- Rebuilds the visibility list: one row per saved account, in the order the dock uses. The names take the
-- list's width less the button and the scrollbar's room, so every button stands at the right edge.
local function refresh_visibility_rows(container_column, list_width)
  if not (container_column and container_column:exists()) then
    return
  end

  for _, child_widget in ipairs(container_column:children():list()) do
    child_widget:destroy()
  end

  local saved_accounts = MultiSession.Options.get_ordered_saved_accounts()
  if #saved_accounts == 0 then
    hafen.ui():label()
      :parent(container_column)
      :text("No saved accounts found.")
    return
  end

  local configuration = MultiSession.Config
  local name_width = list_width - configuration.REORDER_ROW_GAP - configuration.VISIBILITY_BUTTON_WIDTH
    - configuration.VISIBILITY_BAR_ROOM
  for _, account_name in ipairs(saved_accounts) do
    build_visibility_row(container_column, account_name, name_width)
  end
end

refresh_account_rows = function(container_column)
  if not (container_column and container_column:exists()) then
    return
  end

  for _, child_widget in ipairs(container_column:children():list()) do
    child_widget:destroy()
  end

  local is_manual_mode = not MultiSession.Options.is_sort_by_name_enabled()
  local manual_accounts = MultiSession.Options.get_manual_accounts_order()

  container_column:enabled(is_manual_mode)

  if #manual_accounts == 0 then
    hafen.ui():label()
      :parent(container_column)
      :text("No saved accounts found.")
      :enabled(is_manual_mode)
    return
  end

  for account_index, account_name in ipairs(manual_accounts) do
    build_account_row(container_column, account_index, account_name, #manual_accounts, is_manual_mode)
  end
end

-- Registers the addon options panel.
client_options:panel(function(root_container)
  root_container:gap(6)

  local show_names_checkbox = hafen.ui():check()
    :parent(root_container)
    :text("Show names and log-out buttons")
    :bind(show_names_option)

  show_names_checkbox:on("Changed", function()
    hafen.timer():after(0, function()
      if MultiSession.UI and MultiSession.UI.refresh_dock then
        MultiSession.UI.refresh_dock()
      end
    end)
  end)

  local show_current_checkbox = hafen.ui():check()
    :parent(root_container)
    :text("Show the current character")
    :bind(show_current_option)

  show_current_checkbox:on("Changed", function()
    hafen.timer():after(0, function()
      if MultiSession.UI and MultiSession.UI.refresh_dock then
        MultiSession.UI.refresh_dock()
      end
    end)
  end)

  local show_circles_checkbox = hafen.ui():check()
    :parent(root_container)
    :text("Show a circle under each character")
    :bind(show_circles_option)

  show_circles_checkbox:on("Changed", function()
    hafen.timer():after(0, function()
      if MultiSession.SelectionCircles and MultiSession.SelectionCircles.synchronize_selection_circles then
        MultiSession.SelectionCircles.synchronize_selection_circles()
      end
    end)
  end)

  -- Where the dock stands: the choice is greyed until the checkbox lets you make it, and the vertical
  -- position only counts while the dock is anchored to an edge
  local choose_placement_checkbox = hafen.ui():check()
    :parent(root_container)
    :text("Choose where the dock stands")
    :bind(choose_placement_option)

  local placement_label = hafen.ui():label()
    :parent(root_container)
    :text("Placement:")

  local placement_dropdown = hafen.ui():dropdown()
    :parent(root_container)
    :size(MultiSession.Config.PLACEMENT_DROPDOWN_WIDTH)
    :bind(placement_option)

  local offset_label = hafen.ui():label()
    :parent(root_container)
    :text("Position along the edge")

  local offset_slider = hafen.ui():slider()
    :parent(root_container)
    :size(MultiSession.Config.OFFSET_SLIDER_WIDTH)
    :bind(edge_offset_option)

  local inset_label = hafen.ui():label()
    :parent(root_container)
    :text("Distance from the edge")

  local inset_slider = hafen.ui():slider()
    :parent(root_container)
    :size(MultiSession.Config.OFFSET_SLIDER_WIDTH)
    :bind(edge_inset_option)

  hafen.ui():label()
    :parent(root_container)
    :text("Orientation:")

  hafen.ui():dropdown()
    :parent(root_container)
    :size(MultiSession.Config.PLACEMENT_DROPDOWN_WIDTH)
    :bind(orientation_option)

  local function update_placement_controls()
    local choosing = MultiSession.Options.is_choose_placement_enabled()
    local anchored = MultiSession.Options.get_placement() ~= "free"
    for _, control in ipairs({placement_label, placement_dropdown}) do
      if control:exists() then
        control:enabled(choosing)
      end
    end
    for _, control in ipairs({offset_label, offset_slider, inset_label, inset_slider}) do
      if control:exists() then
        control:enabled(anchored)
      end
    end
  end

  choose_placement_checkbox:on("Changed", function()
    hafen.timer():after(0, update_placement_controls)
  end)

  placement_dropdown:on("Changed", function()
    hafen.timer():after(0, update_placement_controls)
  end)

  update_placement_controls()

  -- Two panels side by side: the order on the left, the visibility on the right
  local panels = hafen.ui():row()
    :gap(MultiSession.Config.PANELS_GAP)
    :parent(root_container)

  local left_panel = hafen.ui():column()
    :gap(MultiSession.Config.REORDER_ROW_GAP)
    :parent(panels)

  local right_panel = hafen.ui():column()
    :gap(MultiSession.Config.REORDER_ROW_GAP)
    :parent(panels)

  local sort_checkbox = hafen.ui():check()
    :parent(left_panel)
    :text("Sort accounts by name")
    :bind(sort_by_name_option)

  local list_header_label = hafen.ui():label()
    :parent(left_panel)
    :text("Manual account order:")
    :enabled(not MultiSession.Options.is_sort_by_name_enabled())

  local accounts_column = hafen.ui():column()
    :gap(MultiSession.Config.REORDER_ROW_GAP)
    :parent(left_panel)

  hafen.ui():label()
    :parent(right_panel)
    :text("Account visibility:")

  -- The list scrolls once it outgrows its box. The box is as wide as the page leaves beside the order panel,
  -- whose width is known once its rows are built, so the page's own scrollbar is never covered
  refresh_account_rows(accounts_column)
  local visibility_width = math.max(
    MultiSession.Config.VISIBILITY_LIST_MIN_WIDTH,
    root_container:size().w - left_panel:size().w - MultiSession.Config.PANELS_GAP
  )
  local visibility_scroll = hafen.ui():scroll()
    :parent(right_panel)
    :size(visibility_width, MultiSession.Config.VISIBILITY_LIST_HEIGHT)

  local visibility_column = hafen.ui():column()
    :gap(MultiSession.Config.REORDER_ROW_GAP)
    :parent(visibility_scroll)
    :position(0, 0)

  sort_checkbox:on("Changed", function(is_checked)
    -- Defers cross-tree UI updates to the engine step to avoid tree monitor deadlocks
    hafen.timer():after(0, function()
      if list_header_label and list_header_label:exists() then
        list_header_label:enabled(not is_checked)
      end
      if accounts_column and accounts_column:exists() then
        refresh_account_rows(accounts_column)
      end
      refresh_visibility_rows(visibility_column, visibility_width)
      if MultiSession.UI and MultiSession.UI.refresh_dock then
        MultiSession.UI.refresh_dock()
      end
    end)
  end)

  MultiSession.Options.order_changed = function()
    refresh_visibility_rows(visibility_column, visibility_width)
  end

  refresh_visibility_rows(visibility_column, visibility_width)
end)

-- Updates the dock on the next tick when an option changes, from the panel or from outside it.
for _, option in ipairs({sort_by_name_option, show_names_option, show_current_option, orientation_option}) do
  option:on("Changed", function()
    hafen.timer():after(0, function()
      if MultiSession.UI and MultiSession.UI.refresh_dock then
        MultiSession.UI.refresh_dock()
      end
    end)
  end)
end

-- Draws or removes the ground circles on the next tick when their option changes.
show_circles_option:on("Changed", function()
  hafen.timer():after(0, function()
    if MultiSession.SelectionCircles and MultiSession.SelectionCircles.synchronize_selection_circles then
      MultiSession.SelectionCircles.synchronize_selection_circles()
    end
  end)
end)

-- Places the dock again on the next tick when its placement or its vertical position changes: the anchor
-- rule is rewritten or released, which reaches every tree, so never from inside the panel's own handler.
for _, option in ipairs({choose_placement_option, placement_option, edge_offset_option, edge_inset_option}) do
  option:on("Changed", function()
    hafen.timer():after(0, function()
      if MultiSession.UI and MultiSession.UI.apply_dock_placement then
        MultiSession.UI.apply_dock_placement()
      end
    end)
  end)
end
