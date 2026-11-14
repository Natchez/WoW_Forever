-- Forever Metrics: Quality of Life toggles (Leatrix-style)
-- Every feature here is off by default and toggled from the Settings tab
-- under "Quality of Life". To add one: add a setting in Core.lua's
-- FM.SETTINGS with group = "qol", then check FM:GetSetting(key) here.

local ADDON, ns = ...
local FM = ns.FM

local function say(msg) print("|cffe8c27aForever Metrics|r " .. msg) end

local function money(c)
  if GetCoinTextureString then return GetCoinTextureString(c) end
  return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

---------------------------------------------------------------------------
-- Container API (modern C_Container, with fallback for older clients)
---------------------------------------------------------------------------

local NUM_BAGS = NUM_BAG_SLOTS or 4

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- Returns quality, stack count, locked, hasNoValue, itemLink
local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if not i then return end
    return i.quality, i.stackCount, i.isLocked, i.hasNoValue, i.hyperlink
  end
  if GetContainerItemInfo then
    local _, count, locked, quality, _, _, link, _, noValue = GetContainerItemInfo(bag, slot)
    return quality, count, locked, noValue, link
  end
end

local function useItem(bag, slot)
  if C_Container and C_Container.UseContainerItem then return C_Container.UseContainerItem(bag, slot) end
  if UseContainerItem then return UseContainerItem(bag, slot) end
end

local function sellPrice(link)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not f or not link then return 0 end
  local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(f, link)
  return ok and price or 0
end

---------------------------------------------------------------------------
-- Sell junk + auto repair (at merchants)
---------------------------------------------------------------------------

local selling

local function sellJunk()
  if selling then return end
  -- Collect grey items first, then sell a few per tick so the server keeps up
  local queue, total = {}, 0
  for bag = 0, NUM_BAGS do
    for slot = 1, numSlots(bag) do
      local quality, count, locked, noValue, link = slotInfo(bag, slot)
      if quality == 0 and not locked and not noValue then
        queue[#queue + 1] = { bag, slot }
        total = total + sellPrice(link) * (count or 1)
      end
    end
  end
  if #queue == 0 then return end
  local i, n = 0, #queue
  selling = C_Timer.NewTicker(0.15, function(t)
    if not (MerchantFrame and MerchantFrame:IsShown()) then t:Cancel(); selling = nil; return end
    for _ = 1, 4 do
      i = i + 1
      local q = queue[i]
      if not q then
        t:Cancel(); selling = nil
        say(("sold %d grey %s for %s."):format(n, n == 1 and "item" or "items", money(total)))
        return
      end
      pcall(useItem, q[1], q[2])
    end
  end)
end

local function autoRepair()
  if not (CanMerchantRepair and CanMerchantRepair()) then return end
  local cost, can = GetRepairAllCost()
  if not can or not cost or cost <= 0 then return end
  if GetMoney() < cost then
    say(("can't afford repairs (%s)."):format(money(cost)))
    return
  end
  RepairAllItems()
  say(("repaired your gear for %s."):format(money(cost)))
end

---------------------------------------------------------------------------
-- Faster auto loot: takes everything at once instead of slot by slot.
-- Follows your Auto Loot game setting (and the modifier key that flips it).
---------------------------------------------------------------------------

local lastLoot = 0
local function fastLoot()
  if GetTime() - lastLoot < 0.3 then return end
  lastLoot = GetTime()
  local auto = GetCVarBool and GetCVarBool("autoLootDefault")
  if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
  if not auto then return end
  for slot = GetNumLootItems(), 1, -1 do LootSlot(slot) end
end

---------------------------------------------------------------------------
-- Hide chat background: sets each chat window's background opacity to 0
-- using Blizzard's own chat-window setting, and remembers what it was so
-- turning the toggle off puts it back.
---------------------------------------------------------------------------

local function applyChatBg()
  if not FCF_SetWindowAlpha then return end
  local hide = FM:GetSetting("hideChatBg")
  local db = FM:DB()
  db.chatAlpha = db.chatAlpha or {}
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf then
      if hide then
        if db.chatAlpha[i] == nil and FCF_GetChatWindowInfo then
          local _, _, _, _, _, alpha = FCF_GetChatWindowInfo(i)
          db.chatAlpha[i] = alpha or DEFAULT_CHATFRAME_ALPHA or 0.25
        end
        FCF_SetWindowAlpha(cf, 0)
      elseif db.chatAlpha[i] ~= nil then
        FCF_SetWindowAlpha(cf, db.chatAlpha[i])
        db.chatAlpha[i] = nil
      end
    end
  end
end

---------------------------------------------------------------------------
-- Hide chat buttons: the menu, channel, voice and social buttons, each chat
-- window's scroll buttons/bar, and the combat log filter bar. The tabs stay.
-- Done with alpha + mouse (never Hide) so Blizzard's own show/hide logic and
-- protected UI are untouched; a SetAlpha hook stops chat fading bringing
-- them back.
---------------------------------------------------------------------------

local CHAT_GLOBAL_BUTTONS = {
  "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
  "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton", "FriendsMicroButton",
  "TextToSpeechButtonFrame", "CombatLogQuickButtonFrame_Custom",
}

local hookedChat = {}

local function setMouse(f, on)
  if InCombatLockdown() then return end
  pcall(f.EnableMouse, f, on)
  for _, child in ipairs({ f:GetChildren() }) do
    pcall(child.EnableMouse, child, on)
    for _, gc in ipairs({ child:GetChildren() }) do pcall(gc.EnableMouse, gc, on) end
  end
end

local function chatButtonFrames()
  local list = {}
  for _, name in ipairs(CHAT_GLOBAL_BUTTONS) do
    if _G[name] then list[#list + 1] = _G[name] end
  end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf then
      for _, f in ipairs({ _G["ChatFrame" .. i .. "ButtonFrame"], cf.buttonFrame, cf.ScrollToBottomButton, cf.ScrollBar }) do
        if f and f.SetAlpha then list[#list + 1] = f end
      end
    end
  end
  return list
end

local function applyChatButtons()
  local hide = FM:GetSetting("hideChatButtons")
  for _, f in ipairs(chatButtonFrames()) do
    if not hookedChat[f] then
      hookedChat[f] = true
      -- chat fades its buttons back in on hover; keep them invisible
      hooksecurefunc(f, "SetAlpha", function(self, a)
        if FM:GetSetting("hideChatButtons") and a and a > 0 then self:SetAlpha(0) end
      end)
    end
    if hide then
      f:SetAlpha(0)
      setMouse(f, false)
    elseif f:GetAlpha() == 0 then
      f:SetAlpha(1)
      setMouse(f, true)
    end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local H = {}

function H.PLAYER_LOGIN()
  -- chat windows finish setting themselves up just after login
  C_Timer.After(2, function() pcall(applyChatBg); pcall(applyChatButtons) end)
  FM:OnSetting("hideChatBg", function() pcall(applyChatBg) end)
  FM:OnSetting("hideChatButtons", function() pcall(applyChatButtons) end)
  -- new chat windows (and ones that were closed) get the same treatment
  if FCF_OpenNewWindow then
    hooksecurefunc("FCF_OpenNewWindow", function() C_Timer.After(0.2, function() pcall(applyChatBg); pcall(applyChatButtons) end) end)
  end
end

function H.PLAYER_REGEN_ENABLED()
  -- mouse changes skipped during combat get finished afterwards
  if FM:GetSetting("hideChatButtons") then pcall(applyChatButtons) end
end

function H.MERCHANT_SHOW()
  if FM:GetSetting("autoRepair") then autoRepair() end
  if FM:GetSetting("sellJunk") then sellJunk() end
end

function H.MERCHANT_CLOSED()
  if selling then selling:Cancel(); selling = nil end
end

function H.LOOT_READY()
  if FM:GetSetting("fastLoot") then fastLoot() end
end
H.LOOT_OPENED = H.LOOT_READY -- older clients without LOOT_READY

function H.DUEL_REQUESTED(who)
  if not FM:GetSetting("declineDuels") then return end
  CancelDuel()
  if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
  say(("declined a duel from %s."):format(who or "someone"))
end

ev:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(H[event], ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics QoL error|r", event, err) end
end)
for event in pairs(H) do pcall(ev.RegisterEvent, ev, event) end
