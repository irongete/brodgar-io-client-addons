-- Materials Preview: Cataloger and interactive in-world previewer for variable-material game objects.

-- Declare database schema for variable-material game objects
local gob_models_table = hafen.store():table("gob_models")
  :column("resource", "text")
  :column("name", "text")
  :column("slot_count", "integer")
  :column("slots_info", "json")
  :column("first_seen", "integer")
  :column("last_seen", "integer")
  :key("resource")
  :create()

-- Declare database schema for discovered variable materials
local materials_table = hafen.store():table("materials")
  :column("resource", "text")
  :column("name", "text")
  :column("category", "text")
  :column("first_seen", "integer")
  :key("resource")
  :index("category")
  :create()

-- Declare database schema for game object slot material associations
local gob_slot_materials_table = hafen.store():table("gob_slot_materials")
  :column("gob_resource", "text")
  :column("slot_index", "integer")
  :column("slot_wire", "integer")
  :column("material_resource", "text")
  :column("first_seen", "integer")
  :key("gob_resource", "slot_index", "material_resource")
  :index("gob_resource")
  :index("material_resource")
  :create()

-- In-memory sets to prevent redundant SQLite writes
local known_gob_models = {}
local known_materials = {}
local known_slot_materials = {}

-- Preload known records into memory sets to eliminate repeated SQLite writes
local function preload_cache()
  local existing_gob_models = gob_models_table:list()
  for _, record in ipairs(existing_gob_models) do
    if record.resource then
      known_gob_models[record.resource] = true
    end
  end

  local existing_materials = materials_table:list()
  for _, record in ipairs(existing_materials) do
    if record.resource then
      known_materials[record.resource] = true
    end
  end

  local existing_slot_materials = gob_slot_materials_table:list()
  for _, record in ipairs(existing_slot_materials) do
    if record.gob_resource and record.slot_index and record.material_resource then
      local relation_key = record.gob_resource .. "#" .. tostring(record.slot_index) .. "#" .. record.material_resource
      known_slot_materials[relation_key] = true
    end
  end
end

preload_cache()

-- Derive a clean human-readable title from a resource path segment
local function format_fallback_name(resource_path)
  local last_segment = string.match(resource_path, "([^/]+)$") or resource_path
  local readable_name = string.gsub(last_segment, "[-_]", " ")
  readable_name = string.gsub(readable_name, "(%a)([%w]*)", function(first_letter, rest_of_word)
    return string.upper(first_letter) .. rest_of_word
  end)
  return readable_name
end

-- Extract human-readable name from resource tooltip layer or fallback format
local function resolve_resource_name(resource_path)
  local resource_handle = hafen.resource():get(resource_path)
  if resource_handle:loaded() then
    local tooltip_layer = resource_handle:layers():get("tooltip")
    if tooltip_layer then
      local tooltip_info = tooltip_layer:info()
      if tooltip_info and tooltip_info.text and tooltip_info.text ~= "" then
        return tooltip_info.text
      end
    end
  end
  return format_fallback_name(resource_path)
end

-- Infer broad material category from path keywords
local function infer_material_category(resource_path)
  local path_lower = string.lower(resource_path)
  if string.find(path_lower, "wood", 1, true) then
    return "wood"
  elseif string.find(path_lower, "stone", 1, true) or string.find(path_lower, "rock", 1, true) then
    return "stone"
  elseif string.find(path_lower, "metal", 1, true) or string.find(path_lower, "iron", 1, true)
    or string.find(path_lower, "bronze", 1, true) or string.find(path_lower, "copper", 1, true)
    or string.find(path_lower, "gold", 1, true) or string.find(path_lower, "silver", 1, true)
    or string.find(path_lower, "steel", 1, true) or string.find(path_lower, "tin", 1, true)
    or string.find(path_lower, "lead", 1, true) then
    return "metal"
  elseif string.find(path_lower, "cloth", 1, true) or string.find(path_lower, "fabric", 1, true)
    or string.find(path_lower, "silk", 1, true) or string.find(path_lower, "wool", 1, true)
    or string.find(path_lower, "linen", 1, true) then
    return "cloth"
  elseif string.find(path_lower, "leather", 1, true) or string.find(path_lower, "hide", 1, true) then
    return "leather"
  elseif string.find(path_lower, "bone", 1, true) or string.find(path_lower, "antler", 1, true)
    or string.find(path_lower, "horn", 1, true) then
    return "bone"
  elseif string.find(path_lower, "glass", 1, true) then
    return "glass"
  end
  return "other"
end

-- Inspect a game object, cataloging variable material slots and materials
local function process_game_object(game_object, retry_count)
  if not game_object:exists() then
    return
  end

  local materials_collection = game_object:materials()
  local slot_count = materials_collection:count()
  if slot_count == 0 then
    return
  end

  local gob_resource = game_object:name()
  if not gob_resource or gob_resource == "" then
    local current_retry = retry_count or 0
    if current_retry < 5 then
      hafen.timer():after(0.5, function()
        process_game_object(game_object, current_retry + 1)
      end)
    end
    return
  end

  local current_timestamp = math.floor(os.time())

  -- Record game object model definition if not already registered
  if not known_gob_models[gob_resource] then
    local slots_metadata = {}
    local slot_list = materials_collection:list()
    for _, material_slot in ipairs(slot_list) do
      table.insert(slots_metadata, {
        index = material_slot:index(),
        wire = material_slot:wire()
      })
    end

    local readable_gob_name = resolve_resource_name(gob_resource)
    gob_models_table:put({
      resource = gob_resource,
      name = readable_gob_name,
      slot_count = slot_count,
      slots_info = slots_metadata,
      first_seen = current_timestamp,
      last_seen = current_timestamp
    })
    known_gob_models[gob_resource] = true
  end

  -- Record individual material slots and observed native materials
  local slot_list = materials_collection:list()
  for _, material_slot in ipairs(slot_list) do
    local native_resource = material_slot:native()
    local material_resource_name = native_resource and native_resource:name()

    if material_resource_name and material_resource_name ~= "" then
      -- Store material in catalog if new
      if not known_materials[material_resource_name] then
        local readable_material_name = resolve_resource_name(material_resource_name)
        local category_name = infer_material_category(material_resource_name)
        materials_table:put({
          resource = material_resource_name,
          name = readable_material_name,
          category = category_name,
          first_seen = current_timestamp
        })
        known_materials[material_resource_name] = true
      end

      -- Store game object slot to material relationship if new
      local slot_index = material_slot:index()
      local slot_wire = material_slot:wire()
      local relation_key = gob_resource .. "#" .. tostring(slot_index) .. "#" .. material_resource_name

      if not known_slot_materials[relation_key] then
        gob_slot_materials_table:put({
          gob_resource = gob_resource,
          slot_index = slot_index,
          slot_wire = slot_wire,
          material_resource = material_resource_name,
          first_seen = current_timestamp
        })
        known_slot_materials[relation_key] = true
      end
    end
  end
end

-- Scan currently loaded game objects in the active world
local function scan_current_world()
  local active_session = hafen.session():current()
  if not active_session then
    return
  end

  local world_subsystem = active_session:world()
  if not world_subsystem then
    return
  end

  local loaded_gobs = world_subsystem:gob():list()
  for _, game_object in ipairs(loaded_gobs) do
    process_game_object(game_object, 0)
  end
end

-- -----------------------------------------------------------------------------
-- Interactive In-World 3D Preview Widget
-- -----------------------------------------------------------------------------

local selection_mode_active = false
local active_virtual_widget = nil
local active_preview_window = nil
local active_target_gob = nil

-- Enable or disable object selection targeting mode
local function set_selection_mode(enabled)
  selection_mode_active = enabled
  local mouse_subsystem = hafen.ui():mouse()
  if enabled then
    mouse_subsystem:cursor("study")
    hafen.log():write("Materials Preview: Click an object with variable materials to inspect (Right-click to cancel)")
  else
    mouse_subsystem:cursor(nil)
  end
end

-- Retrieve all discovered materials from storage, sorted alphabetically
local function get_available_materials_list()
  local materials_list = {}
  local registered_resources = {}

  local database_rows = materials_table:list()
  for _, row in ipairs(database_rows) do
    if row.resource and not registered_resources[row.resource] then
      registered_resources[row.resource] = true
      table.insert(materials_list, {
        resource = row.resource,
        name = row.name or format_fallback_name(row.resource)
      })
    end
  end

  table.sort(materials_list, function(first_entry, second_entry)
    return first_entry.name < second_entry.name
  end)

  return materials_list
end

-- Close and clean up any currently open virtual preview widget
local function close_active_preview()
  if active_virtual_widget and active_virtual_widget:exists() then
    hafen.virtual():widget():remove(active_virtual_widget)
    active_virtual_widget = nil
  end
  if active_preview_window and active_preview_window:exists() then
    active_preview_window:destroy()
    active_preview_window = nil
  end
  active_target_gob = nil
end

-- Construct and project a 3D virtual control panel floating to the right of the selected game object
local function open_preview_widget(target_gob)
  close_active_preview()

  if not target_gob or not target_gob:exists() then
    return
  end

  local materials_collection = target_gob:materials()
  local slot_count = materials_collection:count()
  if slot_count == 0 then
    hafen.log():write("Materials Preview: Selected object has no variable materials.")
    return
  end

  active_target_gob = target_gob

  local gob_resource_name = target_gob:name() or "Object"
  local readable_gob_title = resolve_resource_name(gob_resource_name)

  local available_materials = get_available_materials_list()

  -- Ensure any native or current materials of this object are included in the choices
  local registered_resources = {}
  for _, material_entry in ipairs(available_materials) do
    registered_resources[material_entry.resource] = true
  end

  for slot_number = 1, slot_count do
    local current_slot = materials_collection:get(slot_number)
    if current_slot then
      local native_handle = current_slot:native()
      local native_path = native_handle and native_handle:name()
      if native_path and not registered_resources[native_path] then
        registered_resources[native_path] = true
        table.insert(available_materials, {
          resource = native_path,
          name = resolve_resource_name(native_path)
        })
      end
    end
  end

  -- Fallback if database is completely empty
  if #available_materials == 0 then
    for slot_number = 1, slot_count do
      local current_slot = materials_collection:get(slot_number)
      local current_material_handle = current_slot and current_slot:material()
      local current_material_path = current_material_handle and current_material_handle:name()
      if current_material_path and not registered_resources[current_material_path] then
        registered_resources[current_material_path] = true
        table.insert(available_materials, {
          resource = current_material_path,
          name = resolve_resource_name(current_material_path)
        })
      end
    end
  end

  -- Track the current material index for each slot
  local slot_material_indices = {}
  for slot_number = 1, slot_count do
    local current_slot = materials_collection:get(slot_number)
    local active_material_handle = current_slot and current_slot:material()
    local active_material_name = active_material_handle and active_material_handle:name()
    local found_index = 1
    for material_index, material_entry in ipairs(available_materials) do
      if material_entry.resource == active_material_name then
        found_index = material_index
        break
      end
    end
    slot_material_indices[slot_number] = found_index
  end

  -- Construct the native UI window
  local preview_window = hafen.ui():window()
    :title(readable_gob_title .. " Materials")

  active_preview_window = preview_window

  local main_column = hafen.ui():column()
    :gap(3)
    :parent(preview_window)
    :position(0, 0)

  local slot_label_widgets = {}

  -- Helper to refresh slot label text
  local function update_slot_display(slot_number)
    local current_index = slot_material_indices[slot_number]
    local material_entry = available_materials[current_index]
    local material_display_name = material_entry and material_entry.name or "Unknown"
    local slot_label = slot_label_widgets[slot_number]
    if slot_label then
      slot_label:text(string.format("Slot %d: %s", slot_number, material_display_name))
    end
  end

  -- Build a control row for each slot: left arrow (<), center label, right arrow (>)
  for slot_number = 1, slot_count do
    local slot_row = hafen.ui():row()
      :gap(4)
      :parent(main_column)

    local left_button = hafen.ui():button()
      :text("<")
      :size(28)
      :parent(slot_row)

    local initial_index = slot_material_indices[slot_number]
    local initial_material = available_materials[initial_index]
    local initial_display = initial_material and initial_material.name or "None"

    local slot_label = hafen.ui():label()
      :text(string.format("Slot %d: %s", slot_number, initial_display))
      :parent(slot_row)

    slot_label_widgets[slot_number] = slot_label

    local right_button = hafen.ui():button()
      :text(">")
      :size(28)
      :parent(slot_row)

    left_button:on("Pressed", function()
      hafen.timer():after(0, function()
        if #available_materials == 0 then
          return
        end
        local current_index = slot_material_indices[slot_number] - 1
        if current_index < 1 then
          current_index = #available_materials
        end
        slot_material_indices[slot_number] = current_index
        local selected_material = available_materials[current_index]
        local material_slot = materials_collection:get(slot_number)
        if material_slot and selected_material then
          material_slot:material(selected_material.resource)
        end
        update_slot_display(slot_number)
      end)
    end)

    right_button:on("Pressed", function()
      hafen.timer():after(0, function()
        if #available_materials == 0 then
          return
        end
        local current_index = slot_material_indices[slot_number] + 1
        if current_index > #available_materials then
          current_index = 1
        end
        slot_material_indices[slot_number] = current_index
        local selected_material = available_materials[current_index]
        local material_slot = materials_collection:get(slot_number)
        if material_slot and selected_material then
          material_slot:material(selected_material.resource)
        end
        update_slot_display(slot_number)
      end)
    end)
  end

  -- Action buttons bottom row
  local action_row = hafen.ui():row()
    :gap(6)
    :parent(main_column)

  local reset_button = hafen.ui():button()
    :text("Reset")
    :size(48)
    :parent(action_row)

  reset_button:on("Pressed", function()
    hafen.timer():after(0, function()
      if target_gob and target_gob:exists() then
        target_gob:materials():release()
        for slot_number = 1, slot_count do
          local current_slot = materials_collection:get(slot_number)
          local native_handle = current_slot and current_slot:native()
          local native_name = native_handle and native_handle:name()
          for material_index, material_entry in ipairs(available_materials) do
            if material_entry.resource == native_name then
              slot_material_indices[slot_number] = material_index
              break
            end
          end
          update_slot_display(slot_number)
        end
      end
    end)
  end)

  local close_button = hafen.ui():button()
    :text("Close")
    :size(48)
    :parent(action_row)

  close_button:on("Pressed", function()
    hafen.timer():after(0, function()
      close_active_preview()
    end)
  end)

  preview_window:on("Close", function()
    hafen.timer():after(0, function()
      close_active_preview()
    end)
  end)

  -- Pack window to resolve full dimensions before standing into virtual scene
  preview_window:pack()

  -- Stand the widget in the world anchored to the target gob, floating above and in front of everything
  local virtual_widget = hafen.virtual():widget():add(preview_window, target_gob)
  virtual_widget:facing("screen")
  virtual_widget:offset(14, 0, 12)

  active_virtual_widget = virtual_widget
end

-- Intercept MapView clicks during selection mode
hafen.event():action():on("click", function(click_event)
  if not selection_mode_active then
    return
  end

  local widget_source = click_event:widget()
  if not widget_source or widget_source:type() ~= "MapView" then
    return
  end

  local click_arguments = click_event:args()
  local click_button = click_arguments and click_arguments[3]
  local clicked_gob = click_event:gob()

  if click_button == 1 and clicked_gob then
    click_event:preventDefault()
    set_selection_mode(false)
    local selected_gob = clicked_gob
    hafen.timer():after(0, function()
      open_preview_widget(selected_gob)
    end)
  elseif click_button == 3 then
    click_event:preventDefault()
    set_selection_mode(false)
  end
end)

-- Clean up preview widget if the target game object despawns or leaves view
hafen.event():on("GobRemoved", function(removed_gob)
  if active_target_gob and active_target_gob:id() == removed_gob:id() then
    hafen.timer():after(0, function()
      close_active_preview()
    end)
  end
end)

-- Register the Materials Preview action button into the character action menu
local function register_menu_action(session)
  local menugrid_catalog = session:menugrid()
  if not menugrid_catalog then
    return
  end

  local menu_entry = menugrid_catalog:get("materials_preview") or menugrid_catalog:add("materials_preview")
  menu_entry:name("Materials Preview")
    :tooltip("Select an object in the world to preview and modify its variable materials")
    :on("Pressed", function()
      set_selection_mode(not selection_mode_active)
    end)
end

-- Listen for newly spawned or streamed-in game objects
hafen.event():on("GobAdded", function(game_object)
  process_game_object(game_object, 0)
end)

-- Trigger full world scan and register menu button when character enters the world
hafen.event():on("SessionEnteredWorld", function()
  scan_current_world()
  local active_session = hafen.session():current()
  if active_session then
    register_menu_action(active_session)
  end
end)

-- Initialize if session is already active inside world upon load or reload
scan_current_world()
local current_active_session = hafen.session():current()
if current_active_session then
  register_menu_action(current_active_session)
end