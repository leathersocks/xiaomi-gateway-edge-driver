package.path = "./src/?.lua;" .. package.path

local frame_counter = require "frame_counter"
local products = require "product_registry"
local device_summary = require "device_summary"

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

local summary = device_summary.build({
  { id = "2", label = "Bedroom", model = "sensor.b" },
  { id = "1", label = "Living room", model = "sensor.a" },
  { id = "1", label = "Duplicate", model = "sensor.a" },
}, nil, 512)

expect(summary.count, 2, "connected device count")
expect(
  summary.text,
  "Bedroom (sensor.b), Living room (sensor.a)",
  "connected device labels"
)

summary = device_summary.build({
  { id = "1", label = "Living room", model = "sensor.a" },
  { id = "2", label = "Bedroom", model = "sensor.b" },
}, "1", 512)

expect(summary.count, 1, "removed device exclusion")
expect(summary.text, "Bedroom (sensor.b)", "removed device list")

summary = device_summary.build({}, nil, 512)
expect(summary.count, 0, "empty device count")
expect(summary.text, "-", "empty device list")

local korean_label = "서재 온습도"
summary = device_summary.build({
  { id = "1", label = korean_label },
  { id = "2", label = string.rep("히", 100) },
}, nil, 64)
expect(summary.count, 2, "truncated total count")
expect(summary.text, korean_label .. " ... (+1)", "whole UTF-8 label retained")
assert(#summary.text <= 64, "truncated text must respect length limit")

summary = device_summary.build({
  { id = "1", label = string.rep("가", 200) },
}, nil, 512)
expect(summary.count, 1, "oversize label count")
expect(summary.text, "... (+1)", "oversize label omitted without splitting UTF-8")

print("frame counter, product registry, and device summary tests passed")
