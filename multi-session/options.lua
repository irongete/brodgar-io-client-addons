-- =============================================================================
-- Multi-Session - Options Module
-- Manages addon options panel, account sorting preferences, and manual ordering.
-- =============================================================================

MultiSession.Options = {}

local client_options = hafen.client():options():addon()
local sort_by_name_option = client_options:boolean("sort_by_name"):default(true):add()
local persistent_settings = hafen.store():var("settings")

-- Queries saved account names remembered by the client engine.
local function fetch_saved_accounts()
  if hafen.session().saved then
    local success, saved_accounts = pcall(function()
      return hafen.session():saved()
    end)
    if success and type(saved_accounts) == "table" then
      return saved_accounts
    end
  end
  return {}
end

-- Checks whether automatic alphabetical sorting is currently active.
function MultiSession.Options.is_sort_by_name_enabled()
  return sort_by_name_option:value() == true
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

  if MultiSession.UI and MultiSession.UI.refresh_session_window then
    hafen.timer():after(0, MultiSession.UI.refresh_session_window)
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

  local sort_checkbox = hafen.ui():check()
    :parent(root_container)
    :text("Sort accounts by name")
    :bind(sort_by_name_option)

  local list_header_label = hafen.ui():label()
    :parent(root_container)
    :text("Manual account order:")
    :enabled(not MultiSession.Options.is_sort_by_name_enabled())

  local accounts_column = hafen.ui():column()
    :gap(MultiSession.Config.REORDER_ROW_GAP)
    :parent(root_container)

  sort_checkbox:on("Changed", function(is_checked)
    -- Defers cross-tree UI updates to the engine step to avoid tree monitor deadlocks
    hafen.timer():after(0, function()
      if list_header_label and list_header_label:exists() then
        list_header_label:enabled(not is_checked)
      end
      if accounts_column and accounts_column:exists() then
        refresh_account_rows(accounts_column)
      end
      if MultiSession.UI and MultiSession.UI.refresh_session_window then
        MultiSession.UI.refresh_session_window()
      end
    end)
  end)

  refresh_account_rows(accounts_column)
end)

-- Updates switcher window on the next tick when sort option changes from outside panel.
sort_by_name_option:on("Changed", function()
  hafen.timer():after(0, function()
    if MultiSession.UI and MultiSession.UI.refresh_session_window then
      MultiSession.UI.refresh_session_window()
    end
  end)
end)
