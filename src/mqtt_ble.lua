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

local function process_ble_params(driver, source, params, topic)
  if type(params) ~= "table" or type(params.dev) ~= "table" then
    return 0
  end

  local dev = params.dev
  local mac = normalize_mac(dev.mac)
  local did = trim(dev.did)
  local pdid = tonumber(dev.pdid)

  local child, parent, child_status =
    child_manager.ensure_ble_temp_humidity_child(
      driver,
      source,
      dev
    )

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
