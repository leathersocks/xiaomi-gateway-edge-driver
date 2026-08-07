local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local log = require "log"

local discovery = require "discovery"
local gateways = require "gateways"
local miio_probe = require "miio_probe"
local diagnostics = require "diagnostics"

local DEFAULT_INTERVAL = 60
local DEFAULT_TIMEOUT = 3
local DEFAULT_FAILURE_THRESHOLD = 3

local LAST_PRESENCE_FIELD = "xiaomi_gateway_last_presence"
local LAST_HEALTH_FIELD = "xiaomi_gateway_last_health"

local function gateway_definition(device)
  for _, gateway in ipairs(gateways) do
    if gateway.dni == device.device_network_id then
      return gateway
    end
  end

  return nil
end

local function get_ip(device)
  if not device.preferences then
    return ""
  end

  return tostring(device.preferences.gatewayIp or ""):match("^%s*(.-)%s*$")
end

local function get_interval(device)
  local interval = DEFAULT_INTERVAL

  if device.preferences then
    interval = tonumber(device.preferences.checkInterval) or DEFAULT_INTERVAL
  end

  if interval < 30 then
    return 30
  elseif interval > 3600 then
    return 3600
  end

  return interval
end

local function get_timeout(device)
  local timeout = DEFAULT_TIMEOUT

  if device.preferences then
    timeout = tonumber(device.preferences.probeTimeout) or DEFAULT_TIMEOUT
  end

  if timeout < 1 then
    return 1
  elseif timeout > 10 then
    return 10
  end

  return timeout
end

local function get_failure_threshold(device)
  local threshold = DEFAULT_FAILURE_THRESHOLD

  if device.preferences then
    threshold =
      tonumber(device.preferences.failureThreshold) or DEFAULT_FAILURE_THRESHOLD
  end

  if threshold < 1 then
    return 1
  elseif threshold > 5 then
    return 5
  end

  return threshold
end

local function local_now()
  -- Korea Standard Time (UTC+9). Korea does not observe DST.
  return os.date("!%H:%M:%S", os.time() + (9 * 60 * 60))
end

local function emit_presence(device, value, force)
  local previous = device:get_field(LAST_PRESENCE_FIELD)
  if force or previous ~= value then
    device:set_field(LAST_PRESENCE_FIELD, value, { persist = false })
    device:emit_event(capabilities.presenceSensor.presence(value))
  end
end

local function emit_health(device, value, force)
  local previous = device:get_field(LAST_HEALTH_FIELD)
  if force or previous ~= value then
    device:set_field(LAST_HEALTH_FIELD, value, { persist = false })
    device:emit_event(capabilities.healthCheck.healthStatus(value))
  end
end

local function emit_check_interval(device)
  local interval = get_interval(device)
  local threshold = get_failure_threshold(device)
  local platform_interval = math.min(
    604800,
    math.max(60, (interval * threshold) + get_timeout(device) + 15)
  )

  device:emit_event(capabilities.healthCheck.checkInterval(platform_interval))
end

local function set_online(device, force)
  device:online()
  emit_presence(device, "present", force)
  emit_health(device, "online", force)
end

local function set_offline(device, force)
  emit_presence(device, "not present", force)
  emit_health(device, "offline", force)
  device:offline()
end

local function check_gateway(device, source, force)
  local gateway = gateway_definition(device)
  if not gateway then
    log.warn(string.format("%s: gateway definition not found", device.label))
    set_offline(device, true)
    return false
  end

  local ip = get_ip(device)
  if ip == "" then
    log.warn(string.format(
      "%s health check skipped: gatewayIp is not configured",
      device.label
    ))
    diagnostics.record_failure(device, ip, 1)
    set_offline(device, true)
    return false
  end

  if not miio_probe.valid_ipv4(ip) then
    log.warn(string.format(
      "%s health check failed: invalid IPv4 address '%s'",
      device.label,
      ip
    ))
    diagnostics.record_failure(device, ip, 1)
    set_offline(device, true)
    return false
  end

  local ok, result = miio_probe.check(ip, get_timeout(device))

  if ok then
    local last_seen = local_now()
    diagnostics.record_success(device, ip, result, last_seen)
    set_online(device, force == true)

    log.info(string.format(
      "%s miIO health check OK: source=%s model=%s ip=%s port=%s device_id=%s latency=%dms last_seen=%s timestamp=%s",
      device.label,
      tostring(source or "unknown"),
      gateway.model,
      tostring(result.ip),
      tostring(result.port),
      tostring(result.device_id or ""),
      tonumber(result.latency_ms) or 0,
      last_seen,
      tostring(result.timestamp or "")
    ))
    return true
  end

  local threshold = get_failure_threshold(device)
  local failures = diagnostics.record_failure(device, ip, threshold)

  if failures >= threshold then
    set_offline(device, force == true)
    log.warn(string.format(
      "%s miIO health check FAILED/OFFLINE: source=%s model=%s ip=%s port=%s failures=%d/%d reason=%s",
      device.label,
      tostring(source or "unknown"),
      gateway.model,
      ip,
      tostring(result and result.port or 54321),
      failures,
      threshold,
      tostring(result and result.reason or "unknown error")
    ))
  else
    -- A single UDP loss should not immediately flap the SmartThings device offline.
    set_online(device, false)
    log.warn(string.format(
      "%s miIO health check DEGRADED: source=%s model=%s ip=%s failures=%d/%d reason=%s",
      device.label,
      tostring(source or "unknown"),
      gateway.model,
      ip,
      failures,
      threshold,
      tostring(result and result.reason or "unknown error")
    ))
  end

  return false
end

local function cancel_health_timer(device)
  local timer = device.transient_store and device.transient_store.health_timer
  if timer then
    pcall(function()
      device.thread:cancel_timer(timer)
    end)
    device.transient_store.health_timer = nil
  end
end

local function schedule_health_check(device)
  cancel_health_timer(device)

  local interval = get_interval(device)
  local timer = device.thread:call_on_schedule(
    interval,
    function()
      check_gateway(device, "scheduled", false)
    end,
    "xiaomi gateway miIO health check"
  )

  device.transient_store.health_timer = timer
  emit_check_interval(device)

  log.info(string.format(
    "%s health check scheduled every %d seconds; offline threshold=%d failures",
    device.label,
    interval,
    get_failure_threshold(device)
  ))
end

local function log_configuration(device)
  local gateway = gateway_definition(device)
  if not gateway then
    return
  end

  local note = ""
  if device.preferences then
    note = tostring(device.preferences.installationNote or "")
  end

  log.info(string.format(
    "%s configured: model=%s market_model=%s ip=%s interval=%ss timeout=%ss failure_threshold=%d diagnostics=%s note=%s",
    device.label,
    gateway.model,
    gateway.market_model,
    get_ip(device),
    tostring(get_interval(device)),
    tostring(get_timeout(device)),
    get_failure_threshold(device),
    diagnostics.enabled() and "enabled" or "standard-only",
    note
  ))
end

local function added_handler(driver, device)
  log_configuration(device)
  diagnostics.emit_cached(device, get_ip(device))
  schedule_health_check(device)
  check_gateway(device, "added", true)
end

local function init_handler(driver, device)
  diagnostics.emit_cached(device, get_ip(device))
  schedule_health_check(device)
  check_gateway(device, "init", true)
end

local function info_changed_handler(driver, device, event, args)
  log_configuration(device)
  diagnostics.emit_cached(device, get_ip(device))
  schedule_health_check(device)
  check_gateway(device, "infoChanged", true)
end

local function removed_handler(driver, device)
  cancel_health_timer(device)
end

local function refresh_handler(driver, device, command)
  check_gateway(device, "refresh", true)
end

local function health_ping_handler(driver, device, command)
  check_gateway(device, "healthCheck.ping", true)
end

local driver = Driver("xiaomi-gateway-registration", {
  discovery = discovery.start,

  lifecycle_handlers = {
    added = added_handler,
    init = init_handler,
    infoChanged = info_changed_handler,
    removed = removed_handler,
  },

  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
    },
    [capabilities.healthCheck.ID] = {
      [capabilities.healthCheck.commands.ping.NAME] = health_ping_handler,
    },
  },
})

driver:run()
