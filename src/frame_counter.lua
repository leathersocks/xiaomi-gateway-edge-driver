local frame_counter = {}

local MODULUS = 256
local HALF_RANGE = MODULUS / 2
local RESET_IDLE_SECONDS = 15 * 60

local function normalize(value)
  value = tonumber(value)
  if not value then
    return nil
  end

  return math.floor(value) % MODULUS
end

local function previous_values(previous)
  if type(previous) == "table" then
    return
      normalize(previous.counter),
      tonumber(previous.gateway_timestamp),
      tonumber(previous.seen_at)
  end

  return normalize(previous), nil, nil
end

function frame_counter.classify(previous, current, gateway_timestamp, now)
  local current_counter = normalize(current)
  if current_counter == nil then
    return "unsequenced"
  end

  local previous_counter, previous_gateway_timestamp, previous_seen_at =
    previous_values(previous)
  if previous_counter == nil then
    return "new"
  end

  local delta = (current_counter - previous_counter) % MODULUS
  if delta == 0 then
    return "duplicate"
  end
  if delta < HALF_RANGE then
    return "new"
  end

  local current_gateway_timestamp = tonumber(gateway_timestamp)
  if current_gateway_timestamp and previous_gateway_timestamp and
     current_gateway_timestamp > previous_gateway_timestamp then
    return "reset"
  end

  now = tonumber(now) or os.time()
  if previous_seen_at and (now - previous_seen_at) >= RESET_IDLE_SECONDS then
    return "reset"
  end

  return "stale"
end

function frame_counter.record(current, gateway_timestamp, now)
  return {
    counter = normalize(current),
    gateway_timestamp = tonumber(gateway_timestamp),
    seen_at = tonumber(now) or os.time(),
  }
end

return frame_counter
