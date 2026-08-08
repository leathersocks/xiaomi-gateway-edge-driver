local socket = require "cosock.socket"
local capabilities = require "st.capabilities"
local json = require "st.json"
local log = require "log"

local child_manager = require "child_manager"
local gateway_runtime = require "gateway_runtime"

local mqtt = {}

local DEFAULT_PORT = 1883
local DEFAULT_TOPIC = "#"
local KEEPALIVE_SECONDS = 30
local PING_INTERVAL_SECONDS = 15
local PING_RESPONSE_TIMEOUT_SECONDS = 10
local READ_TIMEOUT_SECONDS = 5
local RECONNECT_SECONDS = 3

local GENERATION_FIELD = "xiaomi_ble_mqtt_generation"
local STATE_FIELD = "xiaomi_ble_mqtt_state"

-- Runtime sockets are kept in-memory rather than in SmartThings device fields.
-- This avoids storing a cosock userdata object through device:set_field().
local ACTIVE_SOCKETS = {}
local LAST_SEQ_PREFIX = "xiaomi_ble_mqtt_seq_"

local EID_TEMPERATURE = 19457
local EID_HUMIDITY = 19458
local EID_BATTERY = 18435

local PDID_TEMP_HUMIDITY = 5860
local PDID_TOOTHBRUSH_T700I = 6032
local EID_TOOTHBRUSH_EVENT = 12291 -- 0x3003
local EID_STANDARD_BATTERY = 4106  -- 0x100A
local TOOTHBRUSH_LIVE_WINDOW_SECONDS = 60
local TOOTHBRUSH_MAX_SESSION_SECONDS = 10 * 60
local TOOTHBRUSH_WATCHDOG_SECONDS = 30

local TOOTHBRUSH_ACTIVE_FIELD = "xiaomi_toothbrush_active"
local TOOTHBRUSH_START_TS_FIELD = "xiaomi_toothbrush_start_timestamp"
local TOOTHBRUSH_LAST_TS_FIELD = "xiaomi_toothbrush_last_timestamp"
local TOOTHBRUSH_LAST_SCORE_FIELD = "xiaomi_toothbrush_last_score"
local TOOTHBRUSH_LAST_DURATION_FIELD = "xiaomi_toothbrush_last_duration"
local TOOTHBRUSH_WATCHDOG_GENERATION_FIELD = "xiaomi_toothbrush_watchdog_generation"
local TOOTHBRUSH_LAST_ACTIVITY_FIELD = "xiaomi_toothbrush_last_activity_timestamp"

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalize_mac(value)
  return trim(value):upper():gsub("[^0-9A-F]", "")
end

local function valid_ipv4(ip)
  local a, b, c, d =
    tostring(ip or ""):match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")

  if not a then
    return false
  end

  for _, value in ipairs({
    tonumber(a),
    tonumber(b),
    tonumber(c),
    tonumber(d),
  }) do
    if not value or value < 0 or value > 255 then
      return false
    end
  end

  return true
end

local function enabled(source)
  return gateway_runtime.mqtt_enabled(source)
end

local function broker_ip(source)
  if not source.preferences then
    return ""
  end

  local explicit = trim(source.preferences.bleMqttBrokerIp)
  if explicit ~= "" then
    return explicit
  end

  return trim(source.preferences.gatewayIp)
end

local function broker_port(source)
  local value = DEFAULT_PORT

  if source.preferences then
    value = tonumber(source.preferences.bleMqttPort) or DEFAULT_PORT
  end

  if value < 1 or value > 65535 then
    return DEFAULT_PORT
  end

  return math.floor(value)
end

local function broker_topic(source)
  -- v1.7.7: topic is intentionally fixed internally.
  -- "#" covers both miio/report and central/report.
  return DEFAULT_TOPIC
end

local function applicable(source)
  return gateway_runtime.is_gateway(source)
end

local function hex_bytes(value)
  value = trim(value):gsub("%s+", "")

  if value == "" or (#value % 2) ~= 0 or value:find("[^0-9a-fA-F]") then
    return nil
  end

  local bytes = {}
  for i = 1, #value, 2 do
    bytes[#bytes + 1] = tonumber(value:sub(i, i + 1), 16)
  end

  return bytes
end

local function little_float32(hex_value)
  local bytes = hex_bytes(hex_value)
  if not bytes or #bytes < 4 then
    return nil
  end

  local bits =
    bytes[1] |
    (bytes[2] << 8) |
    (bytes[3] << 16) |
    (bytes[4] << 24)

  local sign = ((bits >> 31) & 1) == 1 and -1 or 1
  local exponent = (bits >> 23) & 0xff
  local mantissa = bits & 0x7fffff

  if exponent == 0xff then
    return nil
  elseif exponent == 0 then
    if mantissa == 0 then
      return sign * 0.0
    end

    return sign * (mantissa / 8388608) * (2 ^ -126)
  end

  return sign *
    (1 + (mantissa / 8388608)) *
    (2 ^ (exponent - 127))
end

local function byte_value(hex_value)
  local bytes = hex_bytes(hex_value)
  if not bytes or #bytes < 1 then
    return nil
  end

  return bytes[1]
end

local function little_u32_from_bytes(bytes, offset)
  offset = offset or 1

  if not bytes or #bytes < (offset + 3) then
    return nil
  end

  return
    bytes[offset] +
    (bytes[offset + 1] * 256) +
    (bytes[offset + 2] * 65536) +
    (bytes[offset + 3] * 16777216)
end

local function format_kst(timestamp)
  timestamp = tonumber(timestamp)
  if not timestamp or timestamp <= 0 then
    return nil
  end

  return os.date(
    "!%Y-%m-%d %H:%M:%S",
    timestamp + (9 * 60 * 60)
  )
end

local function format_duration(seconds)
  seconds = tonumber(seconds)
  if not seconds or seconds < 0 then
    return nil
  end

  seconds = math.floor(seconds + 0.5)
  local minutes = math.floor(seconds / 60)
  local remain = seconds % 60

  return string.format("%02d:%02d", minutes, remain)
end

local function round(value, digits)
  local factor = 10 ^ (digits or 0)

  if value >= 0 then
    return math.floor((value * factor) + 0.5) / factor
  end

  return math.ceil((value * factor) - 0.5) / factor
end

local function emit_temperature(child, value)
  if not value or value < -60 or value > 100 then
    return false
  end

  child:emit_event(
    capabilities.temperatureMeasurement.temperature({
      value = round(value, 1),
      unit = "C",
    })
  )
  return true
end

local function emit_humidity(child, value)
  if not value or value < 0 or value > 100 then
    return false
  end

  child:emit_event(
    capabilities.relativeHumidityMeasurement.humidity(round(value, 1))
  )
  return true
end

local function emit_battery(child, value)
  if not value or value < 0 or value > 100 then
    return false
  end

  if child:supports_capability(capabilities.battery) then
    child:emit_event(
      capabilities.battery.battery(math.floor(value + 0.5))
    )
    return true
  end

  return false
end

local function emit_toothbrush_state(child, value)
  if not child:supports_capability(capabilities.motionSensor) then
    return false
  end

  if value == "brushing" then
    child:emit_event(
      capabilities.motionSensor.motion.active()
    )
    return true
  elseif value == "idle" then
    child:emit_event(
      capabilities.motionSensor.motion.inactive()
    )
    return true
  end

  return false
end

local function numeric_field(device, field_name)
  local raw = device:get_field(field_name)
  return tonumber(raw) or 0
end

local function toothbrush_watchdog_generation(child)
  return numeric_field(child, TOOTHBRUSH_WATCHDOG_GENERATION_FIELD)
end

local function invalidate_toothbrush_watchdog(child)
  local generation = toothbrush_watchdog_generation(child) + 1

  child:set_field(
    TOOTHBRUSH_WATCHDOG_GENERATION_FIELD,
    generation,
    { persist = false }
  )

  child:set_field(
    TOOTHBRUSH_LAST_ACTIVITY_FIELD,
    0,
    { persist = false }
  )

  return generation
end

local function arm_toothbrush_watchdog(child, source_label, reason)
  if not child.thread then
    log.warn(string.format(
      "%s BLE MQTT toothbrush watchdog unavailable: label=%s reason=no-device-thread",
      tostring(source_label or "Xiaomi Gateway"),
      tostring(child.label or child.id)
    ))
    return false
  end

  local generation = toothbrush_watchdog_generation(child) + 1
  local activity_timestamp = os.time()

  child:set_field(
    TOOTHBRUSH_WATCHDOG_GENERATION_FIELD,
    generation,
    { persist = false }
  )

  child:set_field(
    TOOTHBRUSH_LAST_ACTIVITY_FIELD,
    activity_timestamp,
    { persist = false }
  )

  child.thread:call_with_delay(
    TOOTHBRUSH_WATCHDOG_SECONDS,
    function()
      if toothbrush_watchdog_generation(child) ~= generation then
        return
      end

      local active_raw = child:get_field(TOOTHBRUSH_ACTIVE_FIELD)
      if active_raw ~= true then
        return
      end

      local last_activity =
        numeric_field(child, TOOTHBRUSH_LAST_ACTIVITY_FIELD)
      local now = os.time()

      if last_activity > 0 and
         (now - last_activity) < TOOTHBRUSH_WATCHDOG_SECONDS then
        return
      end

      emit_toothbrush_state(child, "idle")

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

      child:set_field(
        TOOTHBRUSH_LAST_ACTIVITY_FIELD,
        0,
        { persist = false }
      )

      log.warn(string.format(
        "%s BLE MQTT toothbrush watchdog timeout: label=%s inactivity=%ss reason=%s; forcing motion inactive",
        tostring(source_label or "Xiaomi Gateway"),
        tostring(child.label or child.id),
        TOOTHBRUSH_WATCHDOG_SECONDS,
        tostring(reason or "no-start-heartbeat")
      ))
    end,
    "xiaomi T700i activity watchdog"
  )

  return true
end

local function refresh_duplicate_toothbrush_watchdog(child, params, source_label)
  if child:get_field(TOOTHBRUSH_ACTIVE_FIELD) ~= true then
    return false
  end

  for _, event in ipairs(params.evt or {}) do
    if tonumber(event.eid) == EID_TOOTHBRUSH_EVENT then
      local bytes = hex_bytes(event.edata)

      if bytes and #bytes >= 1 and bytes[1] == 0 then
        return arm_toothbrush_watchdog(
          child,
          source_label,
          "repeated-start-advertisement"
        )
      end
    end
  end

  return false
end

local function log_toothbrush_raw_packet(source, params, topic)
  local dev = params.dev or {}
  local events = {}

  for index, event in ipairs(params.evt or {}) do
    local eid = tonumber(event.eid)
    local edata = trim(event.edata)
    local bytes = hex_bytes(edata)
    local event_type = nil
    local event_timestamp = nil

    if eid == EID_TOOTHBRUSH_EVENT and bytes and #bytes >= 1 then
      event_type = bytes[1]
      if #bytes >= 5 then
        event_timestamp = little_u32_from_bytes(bytes, 2)
      end
    end

    events[#events + 1] = string.format(
      "#%d eid=%s eid_hex=%s edata=%s bytes=%s type=%s event_ts=%s",
      index,
      tostring(eid or event.eid or "-"),
      eid and string.format("0x%04X", eid) or "-",
      edata ~= "" and edata or "-",
      bytes and tostring(#bytes) or "-",
      event_type ~= nil and tostring(event_type) or "-",
      event_timestamp and tostring(event_timestamp) or "-"
    )
  end

  log.info(string.format(
    "%s BLE MQTT T700i RAW: topic=%s did=%s mac=%s pdid=%s frmCnt=%s gwts=%s events=[%s]",
    tostring(source.label or "Xiaomi Gateway"),
    tostring(topic or ""),
    tostring(dev.did or ""),
    tostring(dev.mac or ""),
    tostring(dev.pdid or ""),
    tostring(params.frmCnt or ""),
    tostring(params.gwts or ""),
    #events > 0 and table.concat(events, " | ") or "-"
  ))
end

local function process_toothbrush_event(
  child,
  event,
  gateway_timestamp,
  source_label
)
  local bytes = hex_bytes(event.edata)
  if not bytes or #bytes < 5 then
    return 0, nil
  end

  local event_type = bytes[1]
  local event_timestamp = little_u32_from_bytes(bytes, 2)
  local score = #bytes >= 6 and bytes[6] or nil

  -- Xiaomi MiBeacon toothbrush events use 0 for brushing start and a
  -- non-zero event type for brushing finish. Normal T700i sessions have
  -- been observed with type=1, while an early/manual stop may use another
  -- non-zero finish code. Treat every non-zero 0x3003 type as an end event
  -- so a forced stop is reflected immediately instead of waiting for the
  -- watchdog fallback.

  local reference_timestamp =
    tonumber(gateway_timestamp) or os.time()

  local delta = event_timestamp and
    math.abs(reference_timestamp - event_timestamp) or nil

  local is_live =
    delta ~= nil and
    delta <= TOOTHBRUSH_LIVE_WINDOW_SECONDS

  local emitted = 0

  -- Read fields into locals before tonumber(). Edge get_field() may return
  -- zero Lua values for an unset field, so nested tonumber(get_field()) is
  -- intentionally avoided.
  local previous_last_raw =
    child:get_field(TOOTHBRUSH_LAST_TS_FIELD)
  local previous_last =
    tonumber(previous_last_raw) or 0

  local active_raw =
    child:get_field(TOOTHBRUSH_ACTIVE_FIELD)
  local session_active =
    active_raw == true

  local start_raw =
    child:get_field(TOOTHBRUSH_START_TS_FIELD)
  local session_start =
    tonumber(start_raw) or 0

  local duration = nil
  local session_started = false
  local session_completed = false

  if event_type == 0 then
    if is_live then
      -- T700i may repeat start advertisements during one brushing session.
      -- Preserve the first live start timestamp instead of resetting the
      -- duration on every repeated type=0 event.
      local start_valid =
        session_active and
        session_start > 0 and
        event_timestamp and
        event_timestamp >= session_start and
        (event_timestamp - session_start) <= TOOTHBRUSH_MAX_SESSION_SECONDS

      if not start_valid then
        session_start = event_timestamp or reference_timestamp

        child:set_field(
          TOOTHBRUSH_START_TS_FIELD,
          session_start,
          { persist = true }
        )

        child:set_field(
          TOOTHBRUSH_ACTIVE_FIELD,
          true,
          { persist = true }
        )

        session_active = true
        session_started = true
      end

      if emit_toothbrush_state(child, "brushing") then
        emitted = emitted + 1
      end

      arm_toothbrush_watchdog(
        child,
        source_label,
        session_started and "live-start" or "live-start-heartbeat"
      )
    end
  else
    -- Only a LIVE end event changes current brushing state or calculates
    -- duration. Historical replay packets never terminate a live session.
    if is_live then
      invalidate_toothbrush_watchdog(child)

      if emit_toothbrush_state(child, "idle") then
        emitted = emitted + 1
      end

      if session_active and
         session_start > 0 and
         event_timestamp and
         event_timestamp >= session_start then
        local candidate =
          event_timestamp - session_start

        if candidate >= 0 and
           candidate <= TOOTHBRUSH_MAX_SESSION_SECONDS then
          duration = candidate

          child:set_field(
            TOOTHBRUSH_LAST_DURATION_FIELD,
            duration,
            { persist = true }
          )
        end
      end

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

      session_completed = true
    end

    -- A historical end record may still be useful metadata if it is newer
    -- than the last stored completed brushing record.
    if event_timestamp and event_timestamp > previous_last then
      child:set_field(
        TOOTHBRUSH_LAST_TS_FIELD,
        event_timestamp,
        { persist = true }
      )

      if score ~= nil then
        child:set_field(
          TOOTHBRUSH_LAST_SCORE_FIELD,
          score,
          { persist = true }
        )
      end
    end
  end

  return emitted, {
    event_type = event_type,
    timestamp = event_timestamp,
    score = score,
    delta = delta,
    live = is_live,
    session_start = session_start,
    session_started = session_started,
    session_completed = session_completed,
    duration = duration,
  }
end

local function process_ble_params(driver, source, params, topic)
  if type(params) ~= "table" or type(params.dev) ~= "table" then
    return 0
  end

  local dev = params.dev
  local mac = normalize_mac(dev.mac)
  local did = trim(dev.did)
  local pdid = tonumber(dev.pdid)

  -- Log raw T700i data before child resolution and frmCnt duplicate
  -- suppression so forced-stop packets can be inspected even when no
  -- SmartThings state event is emitted.
  if pdid == PDID_TOOTHBRUSH_T700I then
    log_toothbrush_raw_packet(source, params, topic)
  end

  local child
  local parent
  local child_status

  if pdid == PDID_TEMP_HUMIDITY then
    child, parent, child_status =
      child_manager.ensure_ble_temp_humidity_child(
        driver,
        source,
        dev
      )
  elseif pdid == PDID_TOOTHBRUSH_T700I then
    child, parent, child_status =
      child_manager.ensure_ble_toothbrush_child(
        driver,
        source,
        dev
      )
  else
    child_status = "unsupported-pdid"
  end

  if not child then
    if child_status == "created" then
      log.info(string.format(
        "%s BLE MQTT child automatic registration requested: topic=%s did=%s mac=%s pdid=%s parent=%s; telemetry will apply on a subsequent advertisement",
        source.label,
        tostring(topic or ""),
        did,
        tostring(dev.mac or ""),
        tostring(pdid or ""),
        parent and parent.label or "-"
      ))
    elseif child_status ~= "creation-pending" then
      log.debug(string.format(
        "%s BLE MQTT event not mapped to a child: reason=%s topic=%s did=%s mac=%s pdid=%s",
        source.label,
        tostring(child_status or "unknown"),
        tostring(topic or ""),
        did,
        tostring(dev.mac or ""),
        tostring(pdid or "")
      ))
    end

    return 0
  end

  local sequence = tonumber(params.frmCnt)
  local sequence_key = did ~= "" and did or mac
  local sequence_field = LAST_SEQ_PREFIX .. sequence_key
  local sequence_owner = parent or source

  local previous_sequence = sequence_owner:get_field(sequence_field)
  if sequence and previous_sequence == sequence then
    if pdid == PDID_TOOTHBRUSH_T700I then
      refresh_duplicate_toothbrush_watchdog(
        child,
        params,
        source.label
      )
    end
    return 0
  end

  if sequence then
    sequence_owner:set_field(
      sequence_field,
      sequence,
      { persist = false }
    )
  end

  local emitted = 0

  if pdid == PDID_TOOTHBRUSH_T700I then
    local toothbrush_result = nil
    local battery = nil

    for _, event in ipairs(params.evt or {}) do
      local eid = tonumber(event.eid)

      if eid == EID_TOOTHBRUSH_EVENT then
        local count
        count, toothbrush_result =
          process_toothbrush_event(
            child,
            event,
            params.gwts,
            source.label
          )
        emitted = emitted + count
      elseif eid == EID_STANDARD_BATTERY then
        battery = byte_value(event.edata)
        if emit_battery(child, battery) then
          emitted = emitted + 1
        end
      end
    end

    if emitted > 0 then
      child:online()

      local last_score_raw =
        child:get_field(TOOTHBRUSH_LAST_SCORE_FIELD)
      local last_score =
        tonumber(last_score_raw)

      local last_duration_raw =
        child:get_field(TOOTHBRUSH_LAST_DURATION_FIELD)
      local last_duration =
        tonumber(last_duration_raw)

      local last_timestamp_raw =
        child:get_field(TOOTHBRUSH_LAST_TS_FIELD)
      local last_timestamp =
        tonumber(last_timestamp_raw)

      log.info(string.format(
        "%s BLE MQTT toothbrush state OK: topic=%s label=%s parent=%s pdid=%s frmCnt=%s type=%s event_ts=%s event_kst=%s live=%s delta=%s start_ts=%s duration=%ss duration_text=%s score=%s last_score=%s last_brushing=%s battery=%s%%",
        source.label,
        tostring(topic or ""),
        child.label,
        parent and parent.label or "-",
        tostring(pdid or ""),
        tostring(sequence or ""),
        toothbrush_result and tostring(toothbrush_result.event_type) or "-",
        toothbrush_result and tostring(toothbrush_result.timestamp) or "-",
        toothbrush_result and format_kst(toothbrush_result.timestamp) or "-",
        toothbrush_result and tostring(toothbrush_result.live) or "-",
        toothbrush_result and tostring(toothbrush_result.delta) or "-",
        toothbrush_result and tostring(toothbrush_result.session_start or "-") or "-",
        toothbrush_result and tostring(toothbrush_result.duration or "-") or "-",
        toothbrush_result and format_duration(toothbrush_result.duration) or "-",
        toothbrush_result and tostring(toothbrush_result.score or "-") or "-",
        last_score and tostring(last_score) or "-",
        last_timestamp and format_kst(last_timestamp) or "-",
        battery and tostring(math.floor(battery + 0.5)) or "-"
      ))

      if toothbrush_result and
         toothbrush_result.session_completed and
         toothbrush_result.live then
        log.info(string.format(
          "%s BLE MQTT toothbrush session complete: label=%s start=%s end=%s duration=%ss duration_text=%s score=%s",
          source.label,
          child.label,
          format_kst(toothbrush_result.session_start) or "-",
          format_kst(toothbrush_result.timestamp) or "-",
          tostring(toothbrush_result.duration or "-"),
          format_duration(toothbrush_result.duration) or "-",
          tostring(toothbrush_result.score or "-")
        ))
      end
    end

    return emitted
  end

  local temperature
  local humidity
  local battery

  for _, event in ipairs(params.evt or {}) do
    local eid = tonumber(event.eid)
    local edata = trim(event.edata)

    if eid == EID_TEMPERATURE then
      temperature = little_float32(edata)
      if emit_temperature(child, temperature) then
        emitted = emitted + 1
      end
    elseif eid == EID_HUMIDITY then
      humidity = byte_value(edata)
      if emit_humidity(child, humidity) then
        emitted = emitted + 1
      end
    elseif eid == EID_BATTERY then
      battery = byte_value(edata)
      if emit_battery(child, battery) then
        emitted = emitted + 1
      end
    end
  end

  if emitted > 0 then
    child:online()

    log.info(string.format(
      "%s BLE MQTT state OK: topic=%s label=%s parent=%s did=%s mac=%s pdid=%s frmCnt=%s temperature=%sC humidity=%s%% battery=%s%%",
      source.label,
      tostring(topic or ""),
      child.label,
      parent and parent.label or "-",
      did,
      tostring(dev.mac or ""),
      tostring(pdid or ""),
      tostring(sequence or ""),
      temperature and tostring(round(temperature, 1)) or "-",
      humidity and tostring(round(humidity, 1)) or "-",
      battery and tostring(math.floor(battery + 0.5)) or "-"
    ))
  end

  return emitted
end

local function collect_ble_events(node, out)
  if type(node) ~= "table" then
    return
  end

  if node.method == "_async.ble_event" and type(node.params) == "table" then
    out[#out + 1] = node.params
  end

  for _, value in pairs(node) do
    if type(value) == "table" then
      collect_ble_events(value, out)
    end
  end
end

local function process_json_payload(driver, source, topic, payload)
  if not tostring(payload or ""):find("_async.ble_event", 1, true) then
    return 0
  end

  local ok, decoded = pcall(json.decode, payload)
  if not ok or type(decoded) ~= "table" then
    log.warn(string.format(
      "%s BLE MQTT JSON decode failed: topic=%s",
      source.label,
      tostring(topic or "")
    ))
    return 0
  end

  local events = {}
  collect_ble_events(decoded, events)

  local emitted = 0
  for _, params in ipairs(events) do
    emitted = emitted +
      process_ble_params(driver, source, params, topic)
  end

  return emitted
end

local function encode_u16(value)
  value = math.floor(value)
  return string.char(
    math.floor(value / 256) % 256,
    value % 256
  )
end

local function encode_string(value)
  value = tostring(value or "")
  return encode_u16(#value) .. value
end

local function encode_remaining_length(value)
  local out = {}

  repeat
    local digit = value % 128
    value = math.floor(value / 128)

    if value > 0 then
      digit = digit + 128
    end

    out[#out + 1] = string.char(digit)
  until value == 0

  return table.concat(out)
end

local function safe_close(sock)
  if sock then
    pcall(function()
      sock:close()
    end)
  end
end

local function receive_exact(sock, count)
  local chunks = {}
  local received = 0

  while received < count do
    local data, err, partial = sock:receive(count - received)

    if data and #data > 0 then
      chunks[#chunks + 1] = data
      received = received + #data
    elseif partial and #partial > 0 then
      chunks[#chunks + 1] = partial
      received = received + #partial

      if err and err ~= "timeout" then
        return nil, err
      end

      if err == "timeout" then
        return nil, "timeout"
      end
    else
      return nil, err or "connection closed"
    end
  end

  return table.concat(chunks)
end

local function read_packet(sock)
  local first_data, first_err = receive_exact(sock, 1)
  if not first_data then
    return nil, nil, first_err
  end

  local first = first_data:byte(1)
  local multiplier = 1
  local remaining = 0

  while true do
    local encoded, err = receive_exact(sock, 1)
    if not encoded then
      return nil, nil, err
    end

    local byte = encoded:byte(1)
    remaining = remaining + ((byte & 0x7f) * multiplier)

    if (byte & 0x80) == 0 then
      break
    end

    multiplier = multiplier * 128
    if multiplier > 2097152 then
      return nil, nil, "malformed MQTT remaining length"
    end
  end

  local body = ""
  if remaining > 0 then
    body, first_err = receive_exact(sock, remaining)
    if not body then
      return nil, nil, first_err
    end
  end

  return first, body, nil
end

local function send_packet(sock, header, body)
  body = body or ""

  local packet =
    string.char(header) ..
    encode_remaining_length(#body) ..
    body

  local sent, err = sock:send(packet)
  if not sent then
    return false, err
  end

  return true
end

local function parse_publish(first, body)
  if #body < 2 then
    return nil, nil, "short MQTT PUBLISH"
  end

  local b1, b2 = body:byte(1, 2)
  local topic_length = (b1 * 256) + b2

  if #body < 2 + topic_length then
    return nil, nil, "short MQTT topic"
  end

  local topic = body:sub(3, 2 + topic_length)
  local position = 3 + topic_length

  local qos = (first >> 1) & 0x03
  if qos > 0 then
    if #body < position + 1 then
      return nil, nil, "short MQTT packet identifier"
    end
    position = position + 2
  end

  return topic, body:sub(position), nil
end

local function mqtt_handshake(sock, source)
  local client_id =
    ("st-ble-%s"):format(
      tostring(source.id or "gateway"):
        gsub("[^%w%-]", ""):
        sub(1, 36)
    )

  local variable_header =
    encode_string("MQTT") ..
    string.char(4, 2) ..
    encode_u16(KEEPALIVE_SECONDS)

  local connect_body = variable_header .. encode_string(client_id)

  log.info(string.format(
    "%s BLE MQTT CONNECT sending",
    source.label
  ))

  local ok, err = send_packet(sock, 0x10, connect_body)
  if not ok then
    return false, "CONNECT send failed: " .. tostring(err)
  end

  local first, body, read_err = read_packet(sock)
  if not first then
    return false, "CONNACK read failed: " .. tostring(read_err)
  end

  if (first >> 4) ~= 2 or #body < 2 or body:byte(2) ~= 0 then
    return false, "MQTT broker rejected connection"
  end

  log.info(string.format(
    "%s BLE MQTT CONNACK OK",
    source.label
  ))

  local topic = broker_topic(source)
  local subscribe_body =
    encode_u16(1) ..
    encode_string(topic) ..
    string.char(0)

  log.info(string.format(
    "%s BLE MQTT SUBSCRIBE sending: topic=%s",
    source.label,
    topic
  ))

  ok, err = send_packet(sock, 0x82, subscribe_body)
  if not ok then
    return false, "SUBSCRIBE send failed: " .. tostring(err)
  end

  first, body, read_err = read_packet(sock)
  if not first or (first >> 4) ~= 9 then
    return false, "SUBACK read failed: " .. tostring(read_err)
  end

  log.info(string.format(
    "%s BLE MQTT SUBACK OK: topic=%s",
    source.label,
    topic
  ))

  return true
end

local function current_generation(source)
  -- SmartThings get_field() can return zero Lua values when the field has
  -- never been set. Passing that call directly into tonumber() therefore
  -- raises "bad argument #1 to 'tonumber' (value expected)".
  -- Assign first so Lua normalizes the absent result to a single nil value.
  local value = source:get_field(GENERATION_FIELD)

  if value == nil then
    return 0
  end

  return tonumber(value) or 0
end

local function generation_matches(source, generation)
  return current_generation(source) == generation
end

local function socket_key(source)
  return tostring(source.id or source.device_network_id or source.label or "gateway")
end

local function set_state(source, value)
  source:set_field(STATE_FIELD, tostring(value or "unknown"), { persist = false })
end

function mqtt.status(source)
  local value = source:get_field(STATE_FIELD)

  if value == nil then
    return "never-started"
  end

  return tostring(value)
end

local function listen_session(driver, source, generation)
  local ip = broker_ip(source)
  local port = broker_port(source)
  local key = socket_key(source)

  log.info(string.format(
    "%s BLE MQTT session attempt: generation=%d broker=%s:%d topic=%s",
    source.label,
    generation,
    tostring(ip),
    port,
    broker_topic(source)
  ))

  if not valid_ipv4(ip) then
    set_state(source, "invalid-broker-ip")
    return false, "invalid MQTT broker IPv4 address: " .. tostring(ip)
  end

  local sock, create_err = socket.tcp()
  if not sock then
    set_state(source, "socket-create-failed")
    return false, "unable to create MQTT TCP socket: " .. tostring(create_err)
  end

  ACTIVE_SOCKETS[key] = sock

  set_state(source, "tcp-connecting")
  log.info(string.format(
    "%s BLE MQTT TCP connecting: %s:%d",
    source.label,
    ip,
    port
  ))

  sock:settimeout(5)
  local connected, connect_err = sock:connect(ip, port)
  if not connected then
    safe_close(sock)
    ACTIVE_SOCKETS[key] = nil
    set_state(source, "tcp-connect-failed")
    return false, "connect failed: " .. tostring(connect_err)
  end

  set_state(source, "tcp-connected")
  log.info(string.format(
    "%s BLE MQTT TCP connected: %s:%d",
    source.label,
    ip,
    port
  ))

  sock:settimeout(READ_TIMEOUT_SECONDS)

  local handshake_ok, handshake_err = mqtt_handshake(sock, source)
  if not handshake_ok then
    safe_close(sock)
    ACTIVE_SOCKETS[key] = nil
    set_state(source, "mqtt-handshake-failed")
    return false, handshake_err
  end

  set_state(source, "subscribed")

  log.info(string.format(
    "%s BLE MQTT connected: broker=%s:%d topic=%s auto_ble_parent=true generation=%d",
    source.label,
    ip,
    port,
    broker_topic(source),
    generation
  ))

  local last_outbound = os.time()
  local ping_sent_at = nil

  while generation_matches(source, generation) and enabled(source) do
    local now = os.time()

    if ping_sent_at and
       (now - ping_sent_at) >= PING_RESPONSE_TIMEOUT_SECONDS then
      safe_close(sock)
      ACTIVE_SOCKETS[key] = nil
      set_state(source, "ping-response-timeout")
      return false, "PINGRESP timeout"
    end

    if not ping_sent_at and
       (now - last_outbound) >= PING_INTERVAL_SECONDS then
      local ping_ok, ping_err = send_packet(sock, 0xc0, "")
      if not ping_ok then
        safe_close(sock)
        ACTIVE_SOCKETS[key] = nil
        set_state(source, "ping-failed")
        return false, "PINGREQ failed: " .. tostring(ping_err)
      end

      last_outbound = now
      ping_sent_at = now

      log.debug(string.format(
        "%s BLE MQTT PINGREQ sent: outbound_idle=%ds",
        source.label,
        PING_INTERVAL_SECONDS
      ))
    end

    local first, body, read_err = read_packet(sock)

    if not first then
      if read_err == "timeout" then
        -- Short receive timeouts are intentional. They let the loop schedule
        -- PINGREQ by outbound-idle time even while the broker continuously
        -- publishes openmiio messages.
      else
        safe_close(sock)
        ACTIVE_SOCKETS[key] = nil
        set_state(source, "disconnected")
        return false, tostring(read_err or "MQTT connection closed")
      end
    else
      local packet_type = first >> 4

      if packet_type == 3 then
        local topic, payload, parse_err = parse_publish(first, body)

        if topic and payload then
          -- openmiio/log may contain a textual copy of the same BLE event.
          -- Only the actual Xiaomi report topics are parsed to avoid duplicate
          -- diagnostics and duplicate state processing.
          if topic == "miio/report" or topic == "central/report" then
            if tostring(payload):find("_async.ble_event", 1, true) then
              log.info(string.format(
                "%s BLE MQTT PUBLISH matched BLE event: topic=%s bytes=%d",
                source.label,
                tostring(topic),
                #payload
              ))
            end
            process_json_payload(driver, source, topic, payload)
          end
        elseif parse_err then
          log.warn(string.format(
            "%s BLE MQTT PUBLISH parse failed: %s",
            source.label,
            tostring(parse_err)
          ))
        end
      elseif packet_type == 13 then
        ping_sent_at = nil
        log.debug(string.format(
          "%s BLE MQTT PINGRESP OK",
          source.label
        ))
      end
    end
  end

  safe_close(sock)
  ACTIVE_SOCKETS[key] = nil
  set_state(source, "stopped")

  return true
end

local function schedule_session(driver, source, generation, delay_seconds, reason)
  set_state(source, "scheduled")

  log.info(string.format(
    "%s BLE MQTT listener scheduled: source=%s generation=%d delay=%ss broker=%s:%d topic=%s",
    source.label,
    tostring(reason or "unknown"),
    generation,
    tostring(delay_seconds),
    broker_ip(source),
    broker_port(source),
    broker_topic(source)
  ))

  source.thread:call_with_delay(
    delay_seconds,
    function()
      log.info(string.format(
        "%s BLE MQTT listener callback entered: source=%s generation=%d current_generation=%d enabled=%s applicable=%s",
        source.label,
        tostring(reason or "unknown"),
        generation,
        current_generation(source),
        enabled(source) and "true" or "false",
        applicable(source) and "true" or "false"
      ))

      if not generation_matches(source, generation) or
         not enabled(source) or
         not applicable(source) then
        log.warn(string.format(
          "%s BLE MQTT listener callback skipped: generation_match=%s enabled=%s applicable=%s",
          source.label,
          generation_matches(source, generation) and "true" or "false",
          enabled(source) and "true" or "false",
          applicable(source) and "true" or "false"
        ))
        return
      end

      local call_ok, session_ok, session_reason =
        pcall(listen_session, driver, source, generation)

      if not call_ok then
        session_reason = tostring(session_ok)
        session_ok = false
        set_state(source, "session-exception")
        log.error(string.format(
          "%s BLE MQTT session exception: %s",
          source.label,
          session_reason
        ))
      end

      if not generation_matches(source, generation) or
         not enabled(source) then
        log.info(string.format(
          "%s BLE MQTT reconnect suppressed: generation_match=%s enabled=%s state=%s",
          source.label,
          generation_matches(source, generation) and "true" or "false",
          enabled(source) and "true" or "false",
          mqtt.status(source)
        ))
        return
      end

      if session_ok then
        log.info(string.format(
          "%s BLE MQTT session stopped normally: state=%s",
          source.label,
          mqtt.status(source)
        ))
      else
        set_state(source, "reconnect-wait")
        log.warn(string.format(
          "%s BLE MQTT disconnected/error: %s; reconnecting in %ds",
          source.label,
          tostring(session_reason or "unknown"),
          RECONNECT_SECONDS
        ))
      end

      schedule_session(
        driver,
        source,
        generation,
        RECONNECT_SECONDS,
        "auto-reconnect"
      )
    end,
    "xiaomi BLE MQTT session"
  )
end

function mqtt.stop(source, reason)
  local generation = current_generation(source) + 1
  source:set_field(GENERATION_FIELD, generation, { persist = false })

  local key = socket_key(source)
  local sock = ACTIVE_SOCKETS[key]

  if sock then
    log.info(string.format(
      "%s BLE MQTT closing active socket: source=%s previous_state=%s",
      source.label,
      tostring(reason or "stop"),
      mqtt.status(source)
    ))
    safe_close(sock)
    ACTIVE_SOCKETS[key] = nil
  end

  set_state(source, "stopped")

  return generation
end

function mqtt.start(driver, source, reason)
  local ip = broker_ip(source)
  local port = broker_port(source)
  local topic = broker_topic(source)

  if not applicable(source) then
    log.debug(string.format(
      "%s BLE MQTT start ignored: source=%s applicable=false",
      source.label,
      tostring(reason or "unknown")
    ))
    return {
      applicable = false,
    }
  end

  log.info(string.format(
    "%s BLE MQTT start requested: source=%s enabled=%s broker=%s:%d topic=%s previous_state=%s",
    source.label,
    tostring(reason or "unknown"),
    enabled(source) and "true" or "false",
    tostring(ip),
    port,
    topic,
    mqtt.status(source)
  ))

  -- Always stop/invalidate a previous listener first. This is necessary when
  -- BLE via MQTT changes from On to Off.
  local generation =
    mqtt.stop(
      source,
      tostring(reason or "start") .. ".restart"
    )

  if not enabled(source) then
    set_state(source, "disabled")
    log.info(string.format(
      "%s BLE MQTT disabled by preference",
      source.label
    ))
    return {
      applicable = true,
      enabled = false,
    }
  end

  if not valid_ipv4(ip) then
    set_state(source, "invalid-broker-ip")
    log.warn(string.format(
      "%s BLE MQTT not started: configure a valid broker IP or IP address; broker=%s",
      source.label,
      tostring(ip)
    ))
    return {
      applicable = true,
      enabled = true,
      started = false,
      reason = "invalid broker IP",
    }
  end

  schedule_session(
    driver,
    source,
    generation,
    1,
    reason or "start"
  )

  return {
    applicable = true,
    enabled = true,
    started = true,
    generation = generation,
  }
end

function mqtt.restart(driver, source, reason)
  log.info(string.format(
    "%s BLE MQTT restart requested: source=%s previous_state=%s",
    source.label,
    tostring(reason or "manual"),
    mqtt.status(source)
  ))

  return mqtt.start(driver, source, reason or "restart")
end

return mqtt
