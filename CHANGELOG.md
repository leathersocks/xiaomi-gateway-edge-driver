# Changelog

## v1.3.0-child-r3 - 2026-08-07

- Fixed the remaining SmartThings `name` length violation.
- Renamed preference `childOnlineFollowsGateway` (25 chars) to
  `childFollowsGateway` (19 chars).
- Updated `src/child_manager.lua` to use the new preference name.
- Re-validated every YAML `name` field recursively: all are 3-24 characters.
- Retains r1/r2 fixes for preference maxLength and child profile names.
- No changes to EDGE_CHILD logic, miIO UDP 54321, gateway diagnostics, MQTT,
  or Telnet behavior.
