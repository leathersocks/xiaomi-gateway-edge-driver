local log = require "log"

local child_manager = require "child_manager"
local miio_rpc = require "miio_rpc"

local auto = {}

local LAST_TOKEN_WARNING = "xiaomi_auto_child_token_warning"
local INVENTORY_FIELD = "xiaomi_gateway_child_inventory"

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

function auto.enabled(parent)
  if not parent.preferences then
    return false
  end

  local value = parent.preferences.autoChildDiscovery
  if value == nil then
    return false
  end

  return value == true
end

local function gateway_token(parent)
  if not parent.preferences then
    return ""
  end

  return trim(parent.preferences.gatewayToken)
end

local function normalize_id(value)
  return trim(value):gsub("[^%w%-_%.:]", "_")
end

local function classify_model(model)
  local value = trim(model):lower()

  if value:find("sensor_ht", 1, true) or
     value:find("weather", 1, true) or
     (value:find("temp", 1, true) and value:find("humid", 1, true)) then
    return "temp-humidity"
  end

  if value:find("magnet", 1, true) or
     value:find("contact", 1, true) or
     value:find("door", 1, true) then
    return "contact"
  end

  if value:find("motion", 1, true) or
     value:find("occup", 1, true) or
     value:find("presence", 1, true) then
    return "motion"
  end

  if value:find("wleak", 1, true) or
     value:find("water", 1, true) or
     value:find("leak", 1, true) then
    return "water"
  end

  return "generic"
end

local function key_for_device(did)
  if did:match("^lumi%.") then
    return "zb-" .. normalize_id(did)
  end

  return "xiaomi-" .. normalize_id(did)
end

local function label_for_device(did, model)
  local short_did = did
  if #short_did > 12 then
    short_did = short_did:sub(-12)
  end

  return string.format(
    "%s %s",
    model ~= "" and model or "Xiaomi child",
    short_did
  )
end

local function definitions_from_result(result)
  local definitions = {}
  local seen = {}

  if type(result) ~= "table" then
    return definitions
  end

  for _, item in pairs(result) do
    if type(item) == "table" then
      local did = trim(item.did or item.sid or "")
      local model = trim(item.model or "")

      if did ~= "" and not seen[did] then
        seen[did] = true

        -- BLE children are enrolled from live MQTT advertisements.
        if did:match("^blt%.") then
          log.debug(string.format(
            "Skipping BLE child from authenticated discovery: did=%s model=%s",
            did,
            model
          ))
        else
          local child_type = classify_model(model)
          local key = key_for_device(did)
          local label = label_for_device(did, model)

          local definition = child_manager.make_definition(
            child_type,
            key,
            label,
            model,
            did
          )

          if definition then
            definitions[#definitions + 1] = definition

            log.info(string.format(
              "Xiaomi child discovered: did=%s model=%s type=%s key=%s",
              did,
              model,
              child_type,
              key
            ))
          end
        end
      end
    end
  end

  return definitions
end

function auto.sync(driver, parent, source)
  if not auto.enabled(parent) then
    return {
      enabled = false,
      source = source,
    }
  end

  local token = gateway_token(parent)
  local ip = parent.preferences and
    trim(parent.preferences.gatewayIp) or ""

  if ip == "" then
    return {
      enabled = true,
      local_discovery = false,
      reason = "gateway IP is not configured",
    }
  end

  if token ~= "" and not miio_rpc.valid_token_hex(token) then
    log.warn(string.format(
      "%s auto child discovery skipped: TOKEN must be exactly 32 hex characters",
      parent.label
    ))

    return {
      enabled = true,
      local_discovery = false,
      reason = "invalid gateway token format",
    }
  end

  local ok, response = miio_rpc.call(
    ip,
    token,
    "get_device_list",
    3
  )

  if not ok then
    if response and response.token_required then
      if not parent:get_field(LAST_TOKEN_WARNING) then
        parent:set_field(
          LAST_TOKEN_WARNING,
          true,
          { persist = false }
        )
        log.warn(string.format(
          "%s authenticated child discovery needs this gateway's 32-hex miIO TOKEN",
          parent.label
        ))
      end
    else
      log.warn(string.format(
        "%s get_device_list unavailable: source=%s reason=%s",
        parent.label,
        tostring(source or "unknown"),
        tostring(response and response.reason or "unknown error")
      ))
    end

    return {
      enabled = true,
      local_discovery = false,
      reason = response and response.reason or "RPC failed",
    }
  end

  parent:set_field(LAST_TOKEN_WARNING, false, { persist = false })

  local definitions = definitions_from_result(response.result)

  parent:set_field(
    INVENTORY_FIELD,
    definitions,
    { persist = false }
  )

  local sync_result = child_manager.sync_definitions(
    driver,
    parent,
    definitions,
    "gateway-get_device_list"
  )

  log.info(string.format(
    "%s automatic child discovery complete: source=%s token_source=%s discovered=%d",
    parent.label,
    tostring(source or "unknown"),
    tostring(response.token_source or ""),
    #definitions
  ))

  return {
    enabled = true,
    local_discovery = true,
    discovered = #definitions,
    sync = sync_result,
  }
end

return auto
