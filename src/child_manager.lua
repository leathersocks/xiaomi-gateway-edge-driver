local capabilities = require "st.capabilities"
local log = require "log"

local gateway_runtime = require "gateway_runtime"
local product_registry = require "product_registry"

local child_manager = {}

local PROFILE_BY_TYPE = {
  ["generic"] = "xiaomi-child-generic",
  ["sensor"] = "xiaomi-child-generic",
  ["temp-humidity"] = "xiaomi-child-temp-hum-v174",
  ["temperature-humidity"] = "xiaomi-child-temp-hum-v174",
  ["temphumidity"] = "xiaomi-child-temp-hum-v174",
  ["th"] = "xiaomi-child-temp-hum-v174",
  ["contact"] = "xiaomi-child-contact",
  ["door"] = "xiaomi-child-contact",
  ["window"] = "xiaomi-child-contact",
  ["motion"] = "xiaomi-child-motion",
  ["occupancy"] = "xiaomi-child-motion",
  ["water"] = "xiaomi-child-water",
  ["leak"] = "xiaomi-child-water",
}

local BLE_TEMP_HUM_PDID = product_registry.PDID.TEMP_HUMIDITY
local BLE_TOOTHBRUSH_PDID = product_registry.PDID.TOOTHBRUSH_T700I

local BLE_TEMP_HUM_PRODUCT = product_registry.ble_product(BLE_TEMP_HUM_PDID)
local BLE_TOOTHBRUSH_PRODUCT = product_registry.ble_product(BLE_TOOTHBRUSH_PDID)

local PENDING_BLE_CREATES = {}

local TOOTHBRUSH_ACTIVE_FIELD = "xiaomi_toothbrush_active"
local TOOTHBRUSH_START_TS_FIELD = "xiaomi_toothbrush_start_timestamp"
local TOOTHBRUSH_RESTORE_WINDOW_SECONDS = 10 * 60

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

local function normalize_mac(value)
  return trim(value):upper():gsub("[^0-9A-F]", "")
end

function child_manager.is_gateway(device)
  return gateway_runtime.is_gateway(device)
end

local function emit_presence(child, value)
  if child:supports_capability(capabilities.presenceSensor) then
    child:emit_event(capabilities.presenceSensor.presence(value))
  end
end

local function set_selected_children_reachable(parent, reachable, selector)
  for _, child in ipairs(parent:get_child_list() or {}) do
    if selector(child) then
      if reachable then
        child:online()
        emit_presence(child, "present")
      else
        emit_presence(child, "not present")
        child:offline()
      end
    end
  end
end

function child_manager.set_ble_children_reachable(parent, reachable)
  set_selected_children_reachable(
    parent,
    reachable,
    function(child)
      return product_registry.is_ble_model(child.model)
    end
  )
end

function child_manager.set_miio_children_reachable(parent, reachable)
  set_selected_children_reachable(
    parent,
    reachable,
    function(child)
      return not product_registry.is_ble_model(child.model)
    end
  )
end

function child_manager.initialize_child(child)
  child:online()
  emit_presence(child, "present")

  -- Toothbrush restart/session recovery is intentionally model-scoped.
  -- Generic Xiaomi motion children also expose motionSensor, but they must
  -- not be reset to inactive by toothbrush-specific state restoration.
  if tostring(child.model or "") == BLE_TOOTHBRUSH_PRODUCT.model and
     child:supports_capability(capabilities.motionSensor) then
    local active_raw =
      child:get_field(TOOTHBRUSH_ACTIVE_FIELD)

    local start_raw =
      child:get_field(TOOTHBRUSH_START_TS_FIELD)

    local start_ts =
      tonumber(start_raw) or 0

    local now =
      os.time()

    local restore_active =
      active_raw == true and
      start_ts > 0 and
      now >= start_ts and
      (now - start_ts) <= TOOTHBRUSH_RESTORE_WINDOW_SECONDS

    if restore_active then
      child:emit_event(
        capabilities.motionSensor.motion.active()
      )
    else
      child:emit_event(
        capabilities.motionSensor.motion.inactive()
      )

      if active_raw == true or start_ts > 0 then
        child:set_field(
          TOOTHBRUSH_ACTIVE_FIELD,
          false,
          { persist = true }
        )

        child:set_field(
          TOOTHBRUSH_START_TS_FIELD,
          0,
          { persist = true }
        )
      end
    end
  end
end

function child_manager.sync_definitions(driver, parent, definitions, source)
  definitions = definitions or {}

  local created = 0
  local existing = 0
  local updated = 0

  for _, definition in ipairs(definitions) do
    local child =
      parent:get_child_by_parent_assigned_key(definition.key)

    if child then
      existing = existing + 1

      local ok = pcall(function()
        child:try_update_metadata({
          profile = definition.profile,
          model = definition.model,
          vendor_provided_label = definition.label,
        })
      end)

      if ok then
        updated = updated + 1
      end
    else
      log.info(string.format(
        "%s creating child: source=%s key=%s type=%s profile=%s label=%s model=%s did=%s",
        parent.label,
        tostring(source or "auto"),
        definition.key,
        definition.type,
        definition.profile,
        definition.label,
        definition.model,
        tostring(definition.did or "")
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
        external_id = definition.did or definition.key,
      })

      created = created + 1
    end
  end

  log.info(string.format(
    "%s child sync complete: source=%s configured=%d created=%d existing=%d metadata_updates=%d",
    parent.label,
    tostring(source or "auto"),
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

function child_manager.make_definition(child_type, key, label, model, did)
  child_type = normalize_type(child_type)
  local profile = PROFILE_BY_TYPE[child_type]

  if not profile then
    child_type = "generic"
    profile = PROFILE_BY_TYPE.generic
  end

  key = normalize_key(key)
  label = trim(label)
  model = trim(model)

  if key == "" then
    return nil
  end

  if label == "" then
    label = "Xiaomi " .. child_type .. " " .. key
  end

  if model == "" then
    model = "unknown"
  end

  return {
    type = child_type,
    key = key,
    label = label,
    model = model,
    profile = profile,
    did = trim(did),
  }
end

function child_manager.ble_child_key(mac)
  local normalized = normalize_mac(mac)
  if normalized == "" then
    return nil
  end

  return "ble-" .. normalized
end

local function is_supported_ble_child(child)
  if not child then
    return false
  end

  local model = tostring(child.model or "")
  if product_registry.is_ble_model(model) then
    return true
  end

  return child:supports_capability(capabilities.temperatureMeasurement) and
    child:supports_capability(capabilities.relativeHumidityMeasurement)
end

function child_manager.find_ble_child_anywhere(driver, mac)
  local key = child_manager.ble_child_key(mac)
  if not key then
    return nil, nil
  end

  for _, parent in ipairs(driver:get_devices() or {}) do
    if gateway_runtime.is_gateway(parent) then
      local child = parent:get_child_by_parent_assigned_key(key)
      if child then
        return child, parent
      end
    end
  end

  return nil, nil
end

local function find_gateway_with_existing_ble_children(driver)
  local best_parent = nil
  local best_count = 0

  for _, parent in ipairs(driver:get_devices() or {}) do
    if gateway_runtime.is_gateway(parent) then
      local count = 0

      for _, child in ipairs(parent:get_child_list() or {}) do
        if is_supported_ble_child(child) then
          count = count + 1
        end
      end

      if count > best_count then
        best_count = count
        best_parent = parent
      end
    end
  end

  return best_parent, best_count
end

local function first_gateway(driver)
  for _, device in ipairs(driver:get_devices() or {}) do
    if gateway_runtime.is_gateway(device) then
      return device
    end
  end

  return nil
end

function child_manager.select_ble_parent(driver, source_gateway)
  local parent, count =
    find_gateway_with_existing_ble_children(driver)

  if parent and count > 0 then
    return parent, "existing-ble-parent"
  end

  if source_gateway and gateway_runtime.is_gateway(source_gateway) then
    return source_gateway, "mqtt-source"
  end

  parent = first_gateway(driver)
  if parent then
    return parent, "first-gateway"
  end

  return nil, "no-gateway"
end


local function ensure_supported_ble_child(
  driver,
  source_gateway,
  dev,
  expected_pdid,
  profile,
  model,
  label_prefix,
  log_type
)
  if type(dev) ~= "table" then
    return nil, nil, "invalid-device"
  end

  local pdid = tonumber(dev.pdid)
  if pdid ~= expected_pdid then
    return nil, nil, "unsupported-pdid"
  end

  local mac = normalize_mac(dev.mac)
  local did = trim(dev.did)

  if mac == "" then
    return nil, nil, "missing-mac"
  end

  local key = "ble-" .. mac

  local existing, existing_parent =
    child_manager.find_ble_child_anywhere(driver, mac)

  if existing then
    PENDING_BLE_CREATES[key] = nil
    return existing, existing_parent, "existing"
  end

  local parent, parent_reason =
    child_manager.select_ble_parent(driver, source_gateway)

  if not parent then
    return nil, nil, "no-parent"
  end

  local now = os.time()
  local last_attempt = PENDING_BLE_CREATES[key]

  if last_attempt and (now - last_attempt) < 30 then
    return nil, parent, "creation-pending"
  end

  PENDING_BLE_CREATES[key] = now

  local suffix = mac:sub(-4)
  local label = label_prefix .. " " .. suffix

  log.info(string.format(
    "%s automatically registering BLE %s child: key=%s did=%s mac=%s pdid=%s parent_reason=%s",
    parent.label,
    log_type,
    key,
    did,
    mac,
    tostring(pdid),
    parent_reason
  ))

  local ok, err = pcall(function()
    driver:try_create_device({
      type = "EDGE_CHILD",
      label = label,
      profile = profile,
      parent_device_id = parent.id,
      parent_assigned_child_key = key,
      manufacturer = "Xiaomi",
      model = model,
      vendor_provided_label = label,
      external_id = did ~= "" and did or key,
    })
  end)

  if not ok then
    PENDING_BLE_CREATES[key] = nil

    log.warn(string.format(
      "%s BLE %s child automatic registration failed: key=%s reason=%s",
      parent.label,
      log_type,
      key,
      tostring(err)
    ))

    return nil, parent, "create-failed"
  end

  return nil, parent, "created"
end

function child_manager.ensure_ble_temp_humidity_child(driver, source_gateway, dev)
  return ensure_supported_ble_child(
    driver,
    source_gateway,
    dev,
    BLE_TEMP_HUM_PDID,
    BLE_TEMP_HUM_PRODUCT.profile,
    BLE_TEMP_HUM_PRODUCT.model,
    BLE_TEMP_HUM_PRODUCT.label_prefix,
    "temp/humidity"
  )
end

function child_manager.ensure_ble_toothbrush_child(driver, source_gateway, dev)
  return ensure_supported_ble_child(
    driver,
    source_gateway,
    dev,
    BLE_TOOTHBRUSH_PDID,
    BLE_TOOTHBRUSH_PRODUCT.profile,
    BLE_TOOTHBRUSH_PRODUCT.model,
    BLE_TOOTHBRUSH_PRODUCT.label_prefix,
    "toothbrush"
  )
end

return child_manager
