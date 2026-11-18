-- Forever Metrics: zone levels on the world map
-- Hover a zone on a continent map (or open a zone's map) and its level range
-- shows at the top of the map, like "Westfall  10-20", coloured against your
-- level the way quests are: red/orange too high, yellow about right, green
-- easy, grey no XP to speak of.
-- Ranges come from the game (C_Map.GetMapLevels) when it has them, otherwise
-- from the Classic ranges below (Forever may differ in places).

local ADDON, ns = ...
local FM = ns.FM

local CLASSIC = {
  -- Eastern Kingdoms
  ["Elwynn Forest"] = { 1, 10 }, ["Dun Morogh"] = { 1, 10 }, ["Tirisfal Glades"] = { 1, 10 },
  ["Westfall"] = { 10, 20 }, ["Loch Modan"] = { 10, 20 }, ["Silverpine Forest"] = { 10, 20 },
  ["Redridge Mountains"] = { 15, 25 }, ["Duskwood"] = { 18, 30 }, ["Wetlands"] = { 20, 30 },
  ["Hillsbrad Foothills"] = { 20, 30 }, ["Alterac Mountains"] = { 30, 40 }, ["Arathi Highlands"] = { 30, 40 },
  ["Stranglethorn Vale"] = { 30, 45 }, ["Badlands"] = { 35, 45 }, ["Swamp of Sorrows"] = { 35, 45 },
  ["The Hinterlands"] = { 40, 50 }, ["Searing Gorge"] = { 43, 50 }, ["Blasted Lands"] = { 45, 55 },
  ["Burning Steppes"] = { 50, 58 }, ["Western Plaguelands"] = { 51, 58 }, ["Eastern Plaguelands"] = { 53, 60 },
  ["Deadwind Pass"] = { 55, 60 },
  -- Kalimdor
  ["Teldrassil"] = { 1, 10 }, ["Durotar"] = { 1, 10 }, ["Mulgore"] = { 1, 10 },
  ["Darkshore"] = { 10, 20 }, ["The Barrens"] = { 10, 25 }, ["Stonetalon Mountains"] = { 15, 27 },
  ["Ashenvale"] = { 18, 30 }, ["Thousand Needles"] = { 25, 35 }, ["Desolace"] = { 30, 40 },
  ["Dustwallow Marsh"] = { 35, 45 }, ["Feralas"] = { 40, 50 }, ["Tanaris"] = { 40, 50 },
  ["Azshara"] = { 45, 55 }, ["Felwood"] = { 48, 55 }, ["Un'Goro Crater"] = { 48, 55 },
  ["Winterspring"] = { 55, 60 }, ["Silithus"] = { 55, 60 },
}

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function levels(mapID, name)
  if C_Map and C_Map.GetMapLevels and mapID then
    local ok, lo, hi = pcall(C_Map.GetMapLevels, mapID)
    lo, hi = ok and tonumber(safe(lo)), ok and tonumber(safe(hi))
    if lo and hi and lo > 0 and hi >= lo then return lo, hi end
  end
  local r = name and CLASSIC[name]
  if r then return r[1], r[2] end
end

-- Quest-style colour of a range against your level
local function color(lo, hi)
  local me = UnitLevel("player") or 1
  if lo > me + 4 then return "ff4040" end   -- red: well above you
  if lo > me + 2 then return "ff8040" end   -- orange
  if hi < me - 9 then return "9d9d9d" end   -- grey: far below
  if hi < me - 3 then return "40bf40" end   -- green: easy
  return "ffd200"                             -- yellow: about right
end

local label, lastText
local function isZone(info)
  local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  return info and info.mapType == zone
end

local function update()
  local map = WorldMapFrame
  if not (map and map:IsShown() and FM:GetSetting("mapLevels")) then
    if label then label:Hide() end
    return
  end
  local mapID = map.GetMapID and map:GetMapID()
  if not mapID then return end
  local target
  local sc = map.ScrollContainer
  if sc and sc:IsMouseOver() and sc.GetNormalizedCursorPosition and C_Map.GetMapInfoAtPosition then
    local x, y = sc:GetNormalizedCursorPosition()
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if ok and isZone(info) and info.mapID ~= mapID then target = info end
  end
  if not target then
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if isZone(info) then target = info end
  end
  local text
  if target then
    local lo, hi = levels(target.mapID, target.name)
    if lo then
      text = ("%s  |cff%s%d-%d|r"):format(target.name, color(lo, hi), lo, hi)
    end
  end
  if text ~= lastText then
    lastText = text
    if text then label.text:SetText(text); label:Show() else label:Hide() end
  end
end

local function build()
  local map = WorldMapFrame
  if not map or label then return end
  local parent = map.ScrollContainer or map
  label = CreateFrame("Frame", nil, parent)
  label:SetSize(400, 30)
  label:SetPoint("TOP", parent, "TOP", 0, -12)
  label:SetFrameLevel((parent:GetFrameLevel() or 1) + 50)
  label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  label.text:SetPoint("CENTER")
  label.text:SetShadowOffset(1, -1)
  label:Hide()
  local acc = 0
  map:HookScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    local ok, err = pcall(update)
    if not ok and FM.debug then print("|cffff5555ForeverMetrics map error|r", err) end
  end)
  map:HookScript("OnHide", function() if label then label:Hide() end; lastText = nil end)
  FM:OnSetting("mapLevels", function() lastText = nil; pcall(update) end)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then return end
  local ok, err = pcall(build)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics map error|r", err) end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "ADDON_LOADED")
