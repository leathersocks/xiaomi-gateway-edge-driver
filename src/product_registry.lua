local registry = {}

registry.PDID = {
  TEMP_HUMIDITY = 5860,
  TOOTHBRUSH_T700I = 6032,
}

registry.BLE = {
  [registry.PDID.TEMP_HUMIDITY] = {
    kind = "temp-humidity",
    model = "miaomiaoce.sensor_ht.o2",
    profile = "xiaomi-child-temp-hum-v174",
    label_prefix = "BLE Temperature/Humidity",
    events = {
      temperature = 19457,
      humidity = 19458,
      battery = 18435,
    },
  },
  [registry.PDID.TOOTHBRUSH_T700I] = {
    kind = "toothbrush",
    model = "k0918.toothbrush.t700i",
    profile = "xiaomi-child-toothbrush",
    label_prefix = "BLE Toothbrush",
    events = {
      state = 12291,
      battery = 4106,
    },
  },
}

function registry.ble_product(pdid)
  return registry.BLE[tonumber(pdid)]
end

function registry.is_ble_model(model)
  model = tostring(model or "")

  for _, product in pairs(registry.BLE) do
    if product.model == model then
      return true
    end
  end

  return false
end

return registry
