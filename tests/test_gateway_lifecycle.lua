package.path = "./src/?.lua;" .. package.path

local captured_driver
local no_op = function() end
package.preload["st.driver"] = function()
  return function(_, options)
    captured_driver = options
    options.run = no_op
    options.get_devices = function() return {} end
    return options
  end
end
package.preload["log"] = function()
  return { info = no_op, warn = no_op, debug = no_op }
end
package.preload["discovery"] = function() return { start = no_op } end
package.preload["miio_probe"] = function()
  return {
    valid_ipv4 = function(ip) return ip == "192.168.10.41" end,
    check = function() return true, { latency_ms = 1 } end,
  }
end
package.preload["diagnostics"] = function()
  return {
    emit_cached = no_op, emit_connected_devices = no_op,
    record_success = no_op, record_failure = function() return 1 end,
  }
end
package.preload["child_manager"] = function()
  return { initialize_child = no_op, set_miio_children_reachable = no_op }
end
package.preload["auto_discovery"] = function()
  return { sync = no_op, enabled = function() return false end }
end
package.preload["child_state"] = function()
  return { enabled = function() return false end }
end
package.preload["mqtt_isolated"] = function()
  return { start = no_op, stop = no_op }
end

require "init"
local lifecycle = captured_driver.lifecycle_handlers
local updates = {}
local fields = {}
local device = {
  id = "existing-gateway-id", label = "Gateway",
  device_network_id = "xiaomi-gateway-existing",
  preferences = { gatewayIp = "" }, transient_store = {},
  get_field = function(_, key) return fields[key] end,
  set_field = function(_, key, value) fields[key] = value end,
  try_update_metadata = function(_, metadata)
    updates[#updates + 1] = metadata.profile
  end,
  online = no_op, offline = no_op,
  thread = { call_on_schedule = no_op, cancel_timer = no_op },
}

lifecycle.init(captured_driver, device)
assert(updates[1] == "xiaomi-gateway-setup", "missing IP must preserve Settings")
lifecycle.init(captured_driver, device)
assert(#updates == 1, "repeated init must not re-request the same profile")

device.preferences.gatewayIp = "not-an-ip"
lifecycle.infoChanged(captured_driver, device)
assert(#updates == 1, "invalid IP must remain in the setup profile")

device.preferences.gatewayIp = "192.168.10.41"
lifecycle.infoChanged(captured_driver, device)
assert(updates[2] == "xiaomi-gateway", "valid IP must select native bridge view")
lifecycle.init(captured_driver, device)
assert(#updates == 2, "configured restart must not repeat profile migration")

device.preferences.gatewayIp = ""
lifecycle.infoChanged(captured_driver, device)
assert(updates[3] == "xiaomi-gateway-setup", "clearing IP must restore setup")
assert(device.id == "existing-gateway-id", "profile switching must preserve identity")

print("gateway lifecycle profile-transition tests passed")
