package.path = "./src/?.lua;" .. package.path

local frame_counter = require "frame_counter"
local products = require "product_registry"

local function expect(actual, expected, label)
  assert(
    actual == expected,
    string.format("%s: expected %s, got %s", label, expected, tostring(actual))
  )
end

expect(frame_counter.classify(nil, 10, 100, 100), "new", "first frame")

local previous = frame_counter.record(10, 100, 100)
expect(frame_counter.classify(previous, 10, 100, 101), "duplicate", "duplicate")
expect(frame_counter.classify(previous, 11, 101, 101), "new", "forward")
expect(frame_counter.classify(previous, 9, 99, 101), "stale", "out of order")

previous = frame_counter.record(255, 100, 100)
expect(frame_counter.classify(previous, 0, 101, 101), "new", "wrap around")

previous = frame_counter.record(100, 100, 100)
expect(frame_counter.classify(previous, 0, 101, 101), "reset", "device reset")
expect(frame_counter.classify(previous, 0, 99, 1000), "reset", "idle reset")

expect(products.ble_product(5860).model, "miaomiaoce.sensor_ht.o2", "sensor registry")
expect(products.ble_product(6032).kind, "toothbrush", "toothbrush registry")
assert(products.ble_product(9999) == nil, "unknown product should not resolve")

print("frame counter and product registry tests passed")
