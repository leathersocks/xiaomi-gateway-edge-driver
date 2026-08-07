local gateways = require "gateways"

local discovery = {}

local function is_registered(driver, device_network_id)
  for _, device in ipairs(driver:get_devices()) do
    if device.device_network_id == device_network_id then
      return true
    end
  end

  return false
end

function discovery.start(driver, options, should_continue)
  for _, gateway in ipairs(gateways) do
    if should_continue and not should_continue() then
      return
    end

    if not is_registered(driver, gateway.dni) then
      driver:try_create_device({
        type = "LAN",
        device_network_id = gateway.dni,
        label = gateway.label,
        profile = "xiaomi-gateway",
        manufacturer = gateway.manufacturer,
        model = gateway.model,
        vendor_provided_label =
          gateway.label .. " (" .. gateway.market_model .. ")",
      })
    end
  end
end

return discovery
