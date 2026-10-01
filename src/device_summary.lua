local device_summary = {}

local DEFAULT_MAX_LENGTH = 512

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function display_name(child)
  local label = trim(child and child.label or "")

  if label == "" then
    label = trim(child and child.vendor_provided_label or "")
  end

  local model = trim(child and child.model or "")

  if label == "" then
    label = model
  end

  if label == "" then
    label = trim(child and child.id or "")
  end

  if label == "" then
    label = "Xiaomi device"
  end

  if model ~= "" and
     model ~= "unknown" and
     not label:find(model, 1, true) then
    return string.format("%s (%s)", label, model)
  end

  return label
end

function device_summary.build(children, excluded_id, max_length)
  children = type(children) == "table" and children or {}
  excluded_id = trim(excluded_id)
  max_length = math.floor(tonumber(max_length) or DEFAULT_MAX_LENGTH)

  if max_length < 32 then
    max_length = 32
  end

  local entries = {}
  local seen_ids = {}

  for index, child in ipairs(children) do
    local child_id = trim(child and child.id or "")
    local identity = child_id ~= "" and child_id or
      string.format("anonymous-%d", index)

    if (excluded_id == "" or child_id ~= excluded_id) and
       not seen_ids[identity] then
      seen_ids[identity] = true
      entries[#entries + 1] = {
        id = child_id,
        text = display_name(child),
      }
    end
  end

  table.sort(entries, function(left, right)
    local left_text = left.text:lower()
    local right_text = right.text:lower()

    if left_text == right_text then
      return left.id < right.id
    end

    return left_text < right_text
  end)

  local count = #entries
  if count == 0 then
    return {
      count = 0,
      text = "-",
      entries = entries,
    }
  end

  local included = {}
  local best_text = ""

  for index, entry in ipairs(entries) do
    local candidate_parts = {}
    for part_index, value in ipairs(included) do
      candidate_parts[part_index] = value
    end
    candidate_parts[#candidate_parts + 1] = entry.text

    local remaining = count - index
    local candidate = table.concat(candidate_parts, ", ")

    if remaining > 0 then
      candidate = candidate .. string.format(" ... (+%d)", remaining)
    end

    if #candidate > max_length then
      break
    end

    included[#included + 1] = entry.text
    best_text = candidate
  end

  if #included == 0 then
    best_text = string.format("... (+%d)", count)
  end

  return {
    count = count,
    text = best_text,
    entries = entries,
  }
end

return device_summary
