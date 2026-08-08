local log = require "log"

local gateway_runtime = require "gateway_runtime"

local discovery = {}

local PENDING_CREATE_UNTIL = 0
local PENDING_SECONDS = 15

local function has_unconfigured_gateway(driver)
  for _, device in ipairs(driver:get_devices() or {}) do
    if gateway_runtime.is_gateway(device) and
       gateway_runtime.gateway_ip(device) == "" then
      return true
    end
  end

  return false
end

local function next_dni()
  -- No static gateway inventory. The DNI only identifies a SmartThings
  -- registration slot; actual IP and runtime roles come from preferences.
  local now = os.time()
  local random = math.random(0, 0xFFFFFF)

  return string.format(
    "xiaomi-gateway-dynamic-%08x-%06x",
    now % 0x100000000,
    random
  )
end

function discovery.start(driver, options, should_continue)
  if should_continue and not should_continue() then
    return
  end

  if has_unconfigured_gateway(driver) then
    log.info(
      "Dynamic gateway discovery: an unconfigured Xiaomi Gateway already exists; configure its IP before adding another."
    )
    return
  end

  local now = os.time()
  if now < PENDING_CREATE_UNTIL then
    return
  end

  PENDING_CREATE_UNTIL = now + PENDING_SECONDS

  local dni = next_dni()

  log.info(string.format(
    "Dynamic gateway discovery: creating generic gateway registration %s",
    dni
  ))

  driver:try_create_device({
    type = "LAN",
    device_network_id = dni,
    label = "Xiaomi Gateway",
    profile = "xiaomi-gateway",
    manufacturer = "Xiaomi",
    model = "dynamic-miio-gateway",
    vendor_provided_label = "Xiaomi Gateway",
  })
end

return discovery
