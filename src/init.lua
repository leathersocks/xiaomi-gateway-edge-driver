local Driver = require "st.driver"
local log = require "log"

local discovery = require "discovery"
local miio_probe = require "miio_probe"
local diagnostics = require "diagnostics"
local child_manager = require "child_manager"
local auto_discovery = require "auto_discovery"
local child_state = require "child_state"
local mqtt_ble = require "mqtt_ble"
local gateway_runtime = require "gateway_runtime"

local DEFAULT_INTERVAL = 60
local PROBE_TIMEOUT = 3
local FAILURE_THRESHOLD = 3
local AUTO_DISCOVERY_INTERVAL = 300

local function is_gateway_device(device)
  return gateway_runtime.is_gateway(device)
end

local function get_ip(device)
  return gateway_runtime.gateway_ip(device)
end

local function get_interval(device)
  local interval = DEFAULT_INTERVAL

  if device.preferences then
    interval =
      tonumber(device.preferences.checkInterval) or DEFAULT_INTERVAL
  end

  if interval < 30 then
    return 30
  elseif interval > 3600 then
    return 3600
  end

  return interval
end

local function local_now()
  return os.date("!%H:%M:%S", os.time() + (9 * 60 * 60))
end

local function set_online(device)
  device:online()
  child_manager.set_children_reachable(device, true)
end

local function set_offline(device)
  child_manager.set_children_reachable(device, false)
  device:offline()
end

local function check_gateway(device, source)
  local ip = get_ip(device)

  if ip == "" then
    diagnostics.record_failure(device, ip, 1)
    set_offline(device)
    log.warn(string.format(
      "%s health check skipped: IP address is not configured",
      device.label
    ))
    return false
  end

  if not miio_probe.valid_ipv4(ip) then
    diagnostics.record_failure(device, ip, 1)
    set_offline(device)
    log.warn(string.format(
      "%s health check failed: invalid IPv4 address '%s'",
      device.label,
      ip
    ))
    return false
  end

  local ok, result = miio_probe.check(ip, PROBE_TIMEOUT)

  if ok then
    local last_seen = local_now()

    diagnostics.record_success(device, ip, result, last_seen)
    set_online(device)

    log.info(string.format(
      "%s miIO health check OK: source=%s ip=%s port=%s device_id=%s latency=%dms last_seen=%s timestamp=%s role=%s",
      device.label,
      tostring(source or "unknown"),
      tostring(result.ip),
      tostring(result.port),
      tostring(result.device_id or ""),
      tonumber(result.latency_ms) or 0,
      last_seen,
      tostring(result.timestamp or ""),
      gateway_runtime.role_summary(device)
    ))

    return true
  end

  local failures =
    diagnostics.record_failure(
      device,
      ip,
      FAILURE_THRESHOLD
    )

  if failures >= FAILURE_THRESHOLD then
    set_offline(device)

    log.warn(string.format(
      "%s miIO health check FAILED/OFFLINE: source=%s ip=%s failures=%d/%d reason=%s",
      device.label,
      tostring(source or "unknown"),
      ip,
      failures,
      FAILURE_THRESHOLD,
      tostring(result and result.reason or "unknown error")
    ))
  else
    set_online(device)

    log.warn(string.format(
      "%s miIO health check DEGRADED: source=%s ip=%s failures=%d/%d reason=%s",
      device.label,
      tostring(source or "unknown"),
      ip,
      failures,
      FAILURE_THRESHOLD,
      tostring(result and result.reason or "unknown error")
    ))
  end

  return false
end

local function cancel_timer(device, field)
  local timer =
    device.transient_store and device.transient_store[field]

  if timer then
    pcall(function()
      device.thread:cancel_timer(timer)
    end)
    device.transient_store[field] = nil
  end
end

local function schedule_health_check(device)
  cancel_timer(device, "health_timer")

  local interval = get_interval(device)

  device.transient_store.health_timer =
    device.thread:call_on_schedule(
      interval,
      function()
        check_gateway(device, "scheduled")
      end,
      "xiaomi gateway miIO health check"
    )

  log.info(string.format(
    "%s health check scheduled: interval=%ds timeout=%ds offline_after=%d failures",
    device.label,
    interval,
    PROBE_TIMEOUT,
    FAILURE_THRESHOLD
  ))
end

local function run_child_sync(driver, device, source)
  auto_discovery.sync(driver, device, source)

  if child_state.enabled(device) then
    child_state.poll(
      device,
      tostring(source or "sync") .. ".state"
    )
  end
end

local function schedule_auto_discovery(driver, device)
  cancel_timer(device, "auto_discovery_timer")

  if not auto_discovery.enabled(device) then
    log.info(string.format(
      "%s auto child discovery disabled",
      device.label
    ))
    return
  end

  device.transient_store.auto_discovery_timer =
    device.thread:call_on_schedule(
      AUTO_DISCOVERY_INTERVAL,
      function()
        auto_discovery.sync(
          driver,
          device,
          "scheduled"
        )
      end,
      "xiaomi gateway child discovery"
    )

  log.info(string.format(
    "%s auto child discovery scheduled every %d seconds",
    device.label,
    AUTO_DISCOVERY_INTERVAL
  ))
end

local function schedule_child_state_poll(device)
  cancel_timer(device, "child_state_timer")

  if not child_state.enabled(device) then
    log.info(string.format(
      "%s Zigbee state polling disabled",
      device.label
    ))
    return
  end

  if not auto_discovery.enabled(device) then
    log.warn(string.format(
      "%s Zigbee state polling requires Auto child discovery to build the current child inventory",
      device.label
    ))
    return
  end

  local interval = child_state.interval(device)

  device.transient_store.child_state_timer =
    device.thread:call_on_schedule(
      interval,
      function()
        child_state.poll(device, "scheduled")
      end,
      "xiaomi gateway Zigbee state poll"
    )

  log.info(string.format(
    "%s Zigbee state polling scheduled every %d seconds",
    device.label,
    interval
  ))
end

local function start_ble_mqtt(driver, device, source)
  mqtt_ble.start(driver, device, source or "lifecycle")
end

local function stop_ble_mqtt(device, source)
  mqtt_ble.stop(device, source or "removed")
end

local function log_configuration(device)
  log.info(string.format(
    "%s configured: ip=%s health_interval=%ds timeout=%ds failure_threshold=%d role=%s",
    device.label,
    get_ip(device),
    get_interval(device),
    PROBE_TIMEOUT,
    FAILURE_THRESHOLD,
    gateway_runtime.role_summary(device)
  ))
end

local function start_services(driver, device, source)
  run_child_sync(driver, device, source)
  schedule_health_check(device)
  schedule_auto_discovery(driver, device)
  schedule_child_state_poll(device)
  start_ble_mqtt(driver, device, source)
  check_gateway(device, source)
end

local function added_handler(driver, device)
  if not is_gateway_device(device) then
    child_manager.initialize_child(device)
    return
  end

  log_configuration(device)
  diagnostics.emit_cached(device, get_ip(device))
  start_services(driver, device, "added")
end

local function init_handler(driver, device)
  if not is_gateway_device(device) then
    child_manager.initialize_child(device)
    return
  end

  diagnostics.emit_cached(device, get_ip(device))
  start_services(driver, device, "init")
end

local function info_changed_handler(driver, device, event, args)
  if not is_gateway_device(device) then
    return
  end

  log_configuration(device)
  diagnostics.emit_cached(device, get_ip(device))
  start_services(driver, device, "infoChanged")
end

local function removed_handler(driver, device)
  if not is_gateway_device(device) then
    return
  end

  cancel_timer(device, "health_timer")
  cancel_timer(device, "auto_discovery_timer")
  cancel_timer(device, "child_state_timer")
  stop_ble_mqtt(device, "removed")
end

local driver = Driver("xiaomi-gateway-registration", {
  discovery = discovery.start,

  lifecycle_handlers = {
    added = added_handler,
    init = init_handler,
    infoChanged = info_changed_handler,
    removed = removed_handler,
  },
})

driver:run()
