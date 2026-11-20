-- Forever Metrics: minimap tracking probe (temporary)
-- /fm minimap test lists every minimap tracking option the game offers
-- addons (name, category, on or off), to see whether Forever has the
-- town-service ones (vendors, repair, trainers, innkeeper...) before
-- building shop icons on the minimap.

local ADDON, ns = ...
local FM = ns.FM

local function say(msg) print("|cffe8c27aForever Metrics minimap|r " .. msg) end

local function show(v)
  if issecretvalue and issecretvalue(v) then return "SECRET" end
  return tostring(v)
end

function FM:MinimapCommand(rest)
  local n, get
  if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
    n, get = C_Minimap.GetNumTrackingTypes(), function(i)
      local info = C_Minimap.GetTrackingInfo(i)
      if type(info) == "table" then return info.name, info.active, info.type, info.subType end
      return info -- some clients return values, not a table
    end
    say("using C_Minimap tracking")
  elseif GetNumTrackingTypes and GetTrackingInfo then
    n, get = GetNumTrackingTypes(), function(i)
      local name, _, active, category, nested = GetTrackingInfo(i)
      return name, active, category, nested
    end
    say("using the older tracking functions")
  else
    say("this client has no minimap tracking functions.")
    return
  end
  say(("%s tracking options:"):format(show(n)))
  for i = 1, tonumber(n) or 0 do
    local ok, name, active, category, sub = pcall(get, i)
    if ok then
      say(("  %d. %s  ·  %s  ·  type %s %s"):format(i, show(name), active and "|cff7fd36bon|r" or "off", show(category), show(sub)))
    else
      say(("  %d. error: %s"):format(i, tostring(name)))
    end
  end
  say(("towns: C_Map %s · C_AreaPoiInfo %s · C_VignetteInfo %s"):format(
    type(C_Map), type(C_AreaPoiInfo), type(C_VignetteInfo)))
end
