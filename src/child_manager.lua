local capabilities = require "st.capabilities"
local log = require "log"

local child_manager = {}

local PROFILE_BY_TYPE = {
  ["generic"] = "xiaomi-child-generic",
  ["sensor"] = "xiaomi-child-generic",

  ["temp-humidity"] = "xiaomi-child-temp-hum",
  ["temperature-humidity"] = "xiaomi-child-temp-hum",
  ["temphumidity"] = "xiaomi-child-temp-hum",
  ["th"] = "xiaomi-child-temp-hum",

  ["contact"] = "xiaomi-child-contact",
  ["door"] = "xiaomi-child-contact",
  ["window"] = "xiaomi-child-contact",

  ["motion"] = "xiaomi-child-motion",
  ["occupancy"] = "xiaomi-child-motion",

  ["water"] = "xiaomi-child-water",
  ["leak"] = "xiaomi-child-water",
}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalize_type(value)
  return trim(value):lower():gsub("_", "-")
end

local function normalize_key(value)
  local key = trim(value)
  key = key:gsub("%s+", "_")
  key = key:gsub("[^%w%._:%-]", "_")
  return key
end

local function split_fields(entry)
  local fields = {}
  local start = 1

  while true do
    local pos = entry:find("|", start, true)
    if not pos then
      fields[#fields + 1] = entry:sub(start)
      break
    end

    fields[#fields + 1] = entry:sub(start, pos - 1)
    start = pos + 1
  end

  return fields
end

function child_manager.is_gateway(device, gateways)
  for _, gateway in ipairs(gateways or {}) do
    if gateway.dni == device.device_network_id then
      return true
    end
  end

  return false
end

function child_manager.parse_manifest(text)
  local result = {}
  local seen = {}

  text = tostring(text or "")

  -- Accept both paragraph/newline input and semicolon-separated input.
  for raw in text:gmatch("[^;\r\n]+") do
    local entry = trim(raw)

    if entry ~= "" and entry:sub(1, 1) ~= "#" then
      local fields = split_fields(entry)
      local child_type = normalize_type(fields[1])
      local key = normalize_key(fields[2])
      local label = trim(fields[3])
      local model = trim(fields[4])

      if child_type == "" then
        child_type = "generic"
      end

      local profile = PROFILE_BY_TYPE[child_type]
      if not profile then
        log.warn(string.format(
          "Unknown child type '%s'; using generic profile",
          child_type
        ))
        child_type = "generic"
        profile = PROFILE_BY_TYPE.generic
      end

      if key == "" then
        log.warn(string.format(
          "Ignoring child manifest entry without key: %s",
          entry
        ))
      elseif seen[key] then
        log.warn(string.format(
          "Ignoring duplicate child key '%s'",
          key
        ))
      else
        seen[key] = true

        if label == "" then
          label = "Xiaomi " .. child_type .. " " .. key
        end

        if model == "" then
          model = "unknown"
        end

        result[#result + 1] = {
          type = child_type,
          key = key,
          label = label,
          model = model,
          profile = profile,
        }
      end
    end
  end

  return result
end

local function follows_gateway(parent)
  if not parent.preferences then
    return true
  end

  local value = parent.preferences.childFollowsGateway
  if value == nil then
    return true
  end

  return value == true
end

local function emit_presence(child, value)
  if child:supports_capability(capabilities.presenceSensor) then
    child:emit_event(capabilities.presenceSensor.presence(value))
  end
end

function child_manager.set_children_reachable(parent, reachable)
  if not follows_gateway(parent) then
    return
  end

  local children = parent:get_child_list() or {}

  for _, child in ipairs(children) do
    if reachable then
      child:online()
      emit_presence(child, "present")
    else
      emit_presence(child, "not present")
      child:offline()
    end
  end
end

function child_manager.initialize_child(child)
  child:online()
  emit_presence(child, "present")
end

function child_manager.sync(driver, parent)
  local text_parts = {}
  if parent.preferences then
    for _, preference_name in ipairs({
      "childDevices",
      "childDevices2",
      "childDevices3",
      "childDevices4",
    }) do
      local value = parent.preferences[preference_name]
      if value ~= nil and tostring(value) ~= "" then
        text_parts[#text_parts + 1] = tostring(value)
      end
    end
  end

  local text = table.concat(text_parts, "\n")
  local definitions = child_manager.parse_manifest(text)
  local created = 0
  local existing = 0
  local updated = 0

  for _, definition in ipairs(definitions) do
    local child = parent:get_child_by_parent_assigned_key(definition.key)

    if child then
      existing = existing + 1

      if child.profile and child.profile.id then
        -- Do not rely on profile IDs here; Edge profile metadata can be opaque.
        -- The requested profile is still applied on creation.
      end

      -- Keep model metadata current without forcing the user's renamed label.
      local ok = pcall(function()
        child:try_update_metadata({
          model = definition.model,
          vendor_provided_label = definition.label,
        })
      end)

      if ok then
        updated = updated + 1
      end
    else
      log.info(string.format(
        "%s creating child: key=%s type=%s profile=%s label=%s model=%s",
        parent.label,
        definition.key,
        definition.type,
        definition.profile,
        definition.label,
        definition.model
      ))

      driver:try_create_device({
        type = "EDGE_CHILD",
        label = definition.label,
        profile = definition.profile,
        parent_device_id = parent.id,
        parent_assigned_child_key = definition.key,
        manufacturer = "Xiaomi",
        model = definition.model,
        vendor_provided_label = definition.label,
        external_id = definition.key,
      })

      created = created + 1
    end
  end

  log.info(string.format(
    "%s child sync complete: configured=%d created=%d existing=%d metadata_updates=%d",
    parent.label,
    #definitions,
    created,
    existing,
    updated
  ))

  return {
    configured = #definitions,
    created = created,
    existing = existing,
    updated = updated,
  }
end

return child_manager
