local addonName, addon = ...

local priv = addon._priv
local util = priv.util
local const = priv.const
local state = priv.state

local CopyTable = util.CopyTable
local EnsureDB = util.EnsureDB
local Print = util.Print
local SafeCall = util.SafeCall

local DEFAULTS = const.DEFAULTS
local PANEL_WIDTH = const.PANEL_WIDTH
local PANEL_HEIGHT = const.PANEL_HEIGHT
local ApplyUIFrame = util.ApplyUIFrame
local SkinUIButton = util.SkinUIButton
local SetUIButtonText = util.SetUIButtonText
local CreateUIFont = util.CreateUIFont

local UI = addon.UI
local BuildLFGTab = priv.ui.BuildLFGTab
local BuildUtilityTab = priv.ui2.BuildUtilityTab
local Debug = priv.debug

local function SelectTab(name)
  addon.activeTab = name

  if addon.tabLFG then
    SkinUIButton(addon.tabLFG, name == "lfg" and "header" or "elevated")
  end
  if addon.tabUtility then
    SkinUIButton(addon.tabUtility, name == "utility" and "header" or "elevated")
  end

  if addon.lfgTab then
    addon.lfgTab:SetShown(name == "lfg")
  end
  if addon.utilityTab then
    addon.utilityTab:SetShown(name == "utility")
  end

  if name == "lfg" then
    SafeCall(UI.RefreshApplicants)
  else
    SafeCall(UI.RefreshUtilityTab)
  end
end

local function RoleTex(role)
  if role == "TANK" then
    return 0, 19 / 64, 22 / 64, 41 / 64
  elseif role == "HEALER" then
    return 20 / 64, 39 / 64, 1 / 64, 20 / 64
  end
  return 20 / 64, 39 / 64, 22 / 64, 41 / 64
end

function UI.RefreshGroupOverview()
  if not addon.groupOverviewRows or not priv.data.GetGroupOverviewRows then
    return
  end
  local rows = SafeCall(priv.data.GetGroupOverviewRows) or {}
  if addon.groupOverviewPanel then
    local contentHeight = 72 + (math.max(1, #rows) * 22)
    addon.groupOverviewPanel:SetHeight(math.min(PANEL_HEIGHT, contentHeight))
  end
  for i = 1, #addon.groupOverviewRows do
    local row = addon.groupOverviewRows[i]
    local data = rows[i]
    if data then
      row:Show()
      row.data = data
      row.name:SetText(tostring(data.name or "-"))
      if data.quality == "bad" then
        row.name:SetTextColor(1, 0.28, 0.28)
      elseif data.quality == "warn" then
        row.name:SetTextColor(1, 0.65, 0.18)
      elseif data.quality == "good" then
        row.name:SetTextColor(0.42, 0.95, 0.42)
      else
        row.name:SetTextColor(0.84, 0.84, 0.84)
      end
      row.role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
      row.role:SetTexCoord(RoleTex(tostring(data.role or "DAMAGER")))
      if data.specIcon then
        row.spec:SetTexture(data.specIcon)
      else
        row.spec:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      end
      row.status:SetText(data.scanning and "Scanning..." or (tostring(data.issues or 0) .. " issues"))
    else
      row:Hide()
    end
  end
end

local function EnsurePanel()
  if addon.panel then
    return addon.panel
  end

  local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetFrameLevel(200)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:Hide()

  ApplyUIFrame(panel, "window", 1)
  panel.TitleText = CreateUIFont(panel, "OVERLAY", "GameFontNormalLarge", "heading")
  panel.TitleText:SetText("QueueUp")
  panel.TitleText:SetTextColor(0.92, 0.95, 1)
  panel.TitleText:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
  local titleRule = panel:CreateTexture(nil, "ARTWORK")
  titleRule:SetColorTexture(0.28, 0.70, 0.82, 0.85)
  titleRule:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -30)
  titleRule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -30)
  titleRule:SetHeight(1)

  local close = CreateFrame("Button", nil, panel, "BackdropTemplate")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
  ApplyUIFrame(close, "elevated", 1)
  close.label = CreateUIFont(close, "OVERLAY", "GameFontNormal", "body")
  close.label:SetPoint("CENTER", 0, 1)
  close.label:SetText("×")
  close.label:SetTextColor(0.78, 0.80, 0.84)
  close:SetScript("OnClick", function() panel:Hide() end)
  close:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.35, 0.35) end)
  close:SetScript("OnLeave", function(self) self.label:SetTextColor(0.78, 0.80, 0.84) end)

  local tabLFG = CreateFrame("Button", nil, panel, "BackdropTemplate")
  tabLFG:SetSize(92, 22)
  tabLFG:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -36)
  tabLFG:SetText("LFG Tools")
  SkinUIButton(tabLFG, "elevated")
  SetUIButtonText(tabLFG, "LFG Tools")

  local tabUtility = CreateFrame("Button", nil, panel, "BackdropTemplate")
  tabUtility:SetSize(72, 22)
  tabUtility:SetPoint("LEFT", tabLFG, "RIGHT", 6, 0)
  tabUtility:SetText("Utility")
  SkinUIButton(tabUtility, "elevated")
  SetUIButtonText(tabUtility, "Utility")

  SafeCall(BuildLFGTab, panel)
  SafeCall(BuildUtilityTab, panel)

  tabLFG:SetScript("OnClick", function()
    SelectTab("lfg")
  end)

  tabUtility:SetScript("OnClick", function()
    SelectTab("utility")
  end)

  panel:SetScript("OnShow", function()
    panel:Raise()
    SafeCall(SelectTab, addon.activeTab or "lfg")
    SafeCall(UI.RefreshApplicants)
    SafeCall(UI.RefreshUtilityTab)
    SafeCall(UI.RefreshGroupOverview)
    if addon.groupOverviewPanel then
      addon.groupOverviewPanel:Show()
    end
  end)
  panel:SetScript("OnHide", function()
    if addon.groupOverviewPanel then
      addon.groupOverviewPanel:Hide()
    end
  end)

  addon.panel = panel
  addon.tabLFG = tabLFG
  addon.tabUtility = tabUtility

  local side = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  side:SetSize(260, PANEL_HEIGHT)
  side:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
  side:SetFrameStrata("DIALOG")
  side:SetFrameLevel(200)
  side:EnableMouse(true)
  side:SetToplevel(true)
  side:Hide()
  ApplyUIFrame(side, "window", 1)
  side.TitleText = CreateUIFont(side, "OVERLAY", "GameFontNormalLarge", "heading")
  side.TitleText:SetText("Group Overview")
  side.TitleText:SetTextColor(0.92, 0.95, 1)
  side.TitleText:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -10)
  local sideRule = side:CreateTexture(nil, "ARTWORK")
  sideRule:SetColorTexture(0.28, 0.70, 0.82, 0.85)
  sideRule:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -30)
  sideRule:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -30)
  sideRule:SetHeight(1)

  local recheckBtn = CreateFrame("Button", nil, side, "BackdropTemplate")
  recheckBtn:SetSize(68, 20)
  recheckBtn:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -36)
  recheckBtn:SetText("Re-check")
  SkinUIButton(recheckBtn, "elevated")
  SetUIButtonText(recheckBtn, "Re-check")
  recheckBtn:SetScript("OnClick", function()
    if priv.data.ClearGroupOverviewCache then
      priv.data.ClearGroupOverviewCache()
    end
    SafeCall(UI.RefreshGroupOverview)
    if C_Timer and C_Timer.After then
      C_Timer.After(0.5, function() SafeCall(UI.RefreshGroupOverview) end)
      C_Timer.After(2.0, function() SafeCall(UI.RefreshGroupOverview) end)
    end
    Print("Group overview cache cleared. Re-scanning...")
  end)

  addon.groupOverviewRows = {}
  for i = 1, 30 do
    local row = CreateFrame("Frame", nil, side)
    row:SetSize(236, 20)
    row:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -64 - ((i - 1) * 22))
    row.name = CreateUIFont(row, "OVERLAY", "GameFontHighlightSmall", "body")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(132)
    row.name:SetJustifyH("LEFT")
    row.status = CreateUIFont(row, "OVERLAY", "GameFontDisableSmall", "body")
    row.status:SetPoint("LEFT", row.name, "RIGHT", 2, 0)
    row.status:SetWidth(66)
    row.status:SetJustifyH("LEFT")
    row.role = row:CreateTexture(nil, "ARTWORK")
    row.role:SetSize(16, 16)
    row.role:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    row.spec = row:CreateTexture(nil, "ARTWORK")
    row.spec:SetSize(16, 16)
    row.spec:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      local d = self.data
      if not d then
        return
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(tostring(d.name or "Group Member"))
      if d.scanning then
        GameTooltip:AddLine("Scanning gear...", 0.85, 0.85, 0.85)
      else
        GameTooltip:AddLine(tostring(d.issues or 0) .. " issues", 1, 1, 1)
        if type(d.issueDetails) == "table" and #d.issueDetails > 0 then
          for ii = 1, #d.issueDetails do
            GameTooltip:AddLine("- " .. tostring(d.issueDetails[ii]), 1, 0.45, 0.45)
          end
        else
          GameTooltip:AddLine("No missing enchants or gems detected.", 0.42, 0.95, 0.42)
        end
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
      GameTooltip_Hide()
    end)
    addon.groupOverviewRows[#addon.groupOverviewRows + 1] = row
  end
  addon.groupOverviewPanel = side

  if addon.lfgTab then addon.lfgTab:Hide() end
  if addon.utilityTab then addon.utilityTab:Hide() end

  SafeCall(SelectTab, "lfg")

  return panel
end

local function TogglePanel()
  local okPanel, panelOrErr = pcall(EnsurePanel)
  local panel = okPanel and panelOrErr or nil
  if not panel then
    Print("Panel failed to initialize: " .. tostring(panelOrErr or "unknown error"))
    return
  end
  local toggledOk, toggleErr = pcall(function()
    panel:SetShown(not panel:IsShown())
  end)
  if not toggledOk then
    Print("Panel toggle failed: " .. tostring(toggleErr or "unknown error"))
    return
  end
  if panel:IsShown() then
    if addon.pveButton then
      addon.pveButton:Hide()
    end
    SafeCall(UI.RefreshApplicants)
    SafeCall(UI.RefreshGroupOverview)
  else
    if addon.pveButton then
      addon.pveButton:Show()
    end
  end
end

local function CreateLauncherButton(parent, name, tooltipText)
  local button = CreateFrame("Button", name, parent, "BackdropTemplate")
  button:SetSize(96, 24)
  button:RegisterForClicks("LeftButtonUp")
  button:SetFrameStrata("TOOLTIP")
  button:SetFrameLevel(100)
  button:SetClampedToScreen(true)
  button:SetIgnoreParentAlpha(true)
  button:SetIgnoreParentScale(true)
  button:SetText("QueueUp")
  SkinUIButton(button, "elevated")
  SetUIButtonText(button, "QueueUp")

  button:SetScript("OnClick", TogglePanel)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("QueueUp")
    GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)

  return button
end

local function FindBestHostFrame()
  local candidateNames = {
    "PVEFrame",
    "LFGListFrame",
    "LFGParentFrame",
    "ChallengesFrame",
    "WeeklyRewardsFrame",
  }

  for _, name in ipairs(candidateNames) do
    local frameObj = _G[name]
    if frameObj and frameObj.GetObjectType and frameObj:GetObjectType() == "Frame" then
      if frameObj.IsVisible and frameObj:IsVisible() then
        return frameObj, true
      end
    end
  end

  return nil, false
end

local function EnsureButton()
  if addon.pveButton then
    return addon.pveButton
  end

  addon.pveButton = CreateLauncherButton(UIParent, "QueueUpPVEButton", "Open QueueUp panel")
  addon.pveButton:ClearAllPoints()
  addon.pveButton:SetPoint("TOP", UIParent, "TOP", 0, -120)
  addon.pveButton:Hide()
  return addon.pveButton
end

local function ReanchorButton()
  local button = EnsureButton()
  if addon.panel and addon.panel:IsShown() then
    button:Hide()
    return false
  end

  local hostFrame, hostVisible = FindBestHostFrame()

  if hostFrame and hostVisible then
    button:ClearAllPoints()
    if hostFrame.CloseButton then
      button:SetPoint("RIGHT", hostFrame.CloseButton, "LEFT", -4, 0)
    else
      button:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -34, -24)
    end
    button:Show()
    return true
  end

  button:Hide()
  return false
end

local function EnsureEmbeddedButtons()
  EnsureButton()
  ReanchorButton()
end

local function TryInstallFrameHooks()
  local candidateNames = {
    "PVEFrame",
    "LFGListFrame",
    "LFGParentFrame",
    "ChallengesFrame",
    "WeeklyRewardsFrame",
  }

  for _, name in ipairs(candidateNames) do
    local frameObj = _G[name]
    if frameObj and frameObj.GetObjectType and frameObj:GetObjectType() == "Frame" and not state.hookedFrames[name] then
      frameObj:HookScript("OnShow", EnsureEmbeddedButtons)
      frameObj:HookScript("OnHide", EnsureEmbeddedButtons)
      state.hookedFrames[name] = true
    end
  end
end

local function StartApplicantRefreshTicker()
  if state.applicantTicker or not C_Timer or not C_Timer.NewTicker then
    return
  end

  -- Event-driven updates are the primary source of truth.
  -- Keep this ticker as a low-frequency safety net only while actively listed.
  state.applicantTicker = C_Timer.NewTicker(2, function()
    if not (addon.panel and addon.panel:IsShown() and addon.activeTab == "lfg") then
      return
    end
    local listingKind = (priv.data.GetActiveListingKind and priv.data.GetActiveListingKind()) or "none"
    if listingKind ~= "none" then
      UI.RefreshApplicants()
    else
      local now = (type(GetTime) == "function" and tonumber(GetTime())) or 0
      if now >= (state.nextStandbyTickerRefreshAt or 0) then
        state.nextStandbyTickerRefreshAt = now + 5
        UI.RefreshApplicants()
      end
    end
  end)
end

state.frame:RegisterEvent("PLAYER_LOGIN")
state.frame:RegisterEvent("ADDON_LOADED")
state.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
state.frame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
state.frame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
state.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
state.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
state.frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
state.frame:RegisterEvent("UNIT_AURA")
state.frame:RegisterEvent("INSPECT_READY")
state.frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    state.DB = EnsureDB()

    if state.DB.firstRun then
      Print("installed. Use the QueueUp icon in Dungeons & Raids.")
      state.DB.firstRun = false
    end

    EnsurePanel()
    EnsureEmbeddedButtons()
    TryInstallFrameHooks()
    StartApplicantRefreshTicker()

    if not state.reanchorTicker and C_Timer and C_Timer.NewTicker then
      state.reanchorTicker = C_Timer.NewTicker(2, function()
        TryInstallFrameHooks()
        EnsureEmbeddedButtons()
      end)
    end
    return
  end

  if event == "ADDON_LOADED" and type(arg1) == "string" and arg1:find("^Blizzard_") then
    TryInstallFrameHooks()
    EnsureEmbeddedButtons()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    TryInstallFrameHooks()
    EnsureEmbeddedButtons()
    UI.RefreshApplicants()
    UI.RefreshUtilityTab()
    UI.RefreshGroupOverview()
    return
  end

  if event == "UNIT_AURA" and arg1 == "player" then
    if addon.panel and addon.panel:IsShown() and addon.activeTab == "lfg" then
      local listingKind = (priv.data.GetActiveListingKind and priv.data.GetActiveListingKind()) or "none"
      if listingKind == "none" then
        local now = (type(GetTime) == "function" and tonumber(GetTime())) or 0
        if now >= (state.nextStandbyAuraRefreshAt or 0) then
          state.nextStandbyAuraRefreshAt = now + 5
          UI.RefreshApplicants()
        end
      end
    end
    return
  end

  if event == "LFG_LIST_APPLICANT_LIST_UPDATED" or event == "LFG_LIST_APPLICANT_UPDATED" then
    UI.RefreshApplicants()
    return
  end

  if event == "PLAYER_EQUIPMENT_CHANGED" then
    if priv.data.ClearGroupOverviewCache then
      priv.data.ClearGroupOverviewCache()
    end
    UI.RefreshGroupOverview()
    return
  end

  if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
    UI.RefreshApplicants()
    UI.RefreshUtilityTab()
    UI.RefreshGroupOverview()
    return
  end

  if event == "INSPECT_READY" then
    UI.RefreshGroupOverview()
    return
  end
end)

SLASH_QUEUEUP1 = "/queueup"
SLASH_QUEUEUP2 = "/gu"

SlashCmdList.QUEUEUP = function(msg)
  local command = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if command == "" then
    TogglePanel()
    return
  end

  if command == "help" then
    Print("Commands:")
    Print("  /queueup         - toggle panel")
    Print("  /queueup help    - show this help")
    Print("  /queueup reset   - reset saved variables")
    Print("  /queueup debug on|off")
    Print("  /queueup debug add [count]")
    Print("  /queueup debug clear")
    Print("  /queueup debug list dungeon|raid|none")
    Print("Rules are in LFG Tools. Utility is in Utility.")
    return
  end

  if command:find("^debug") == 1 then
    if not Debug then
      Print("Debug module not loaded.")
      return
    end

    local sub = command:sub(6):gsub("^%s+", "")
    if sub == "" then
      Print("Debug: " .. (Debug.enabled and "ON" or "OFF") .. ", fake applicants: " .. tostring(Debug.ListCount()))
      return
    end

    if sub == "on" then
      Debug.SetEnabled(true)
      UI.RefreshApplicants()
      return
    end

    if sub == "off" then
      Debug.SetEnabled(false)
      UI.RefreshApplicants()
      return
    end

    if sub == "clear" then
      Debug.Clear()
      if Debug.SetListingKind then
        Debug.SetListingKind("none")
      end
      UI.RefreshApplicants()
      return
    end

    local listingKind = sub:match("^list%s+(%S+)$")
    if listingKind and Debug.SetListingKind then
      Debug.SetListingKind(listingKind)
      UI.RefreshApplicants()
      return
    end

    local addCount = sub:match("^add%s+(%d+)$")
    if addCount or sub == "add" then
      Debug.Add(addCount or 1)
      if not Debug.enabled then
        Debug.SetEnabled(true)
      end
      UI.RefreshApplicants()
      return
    end

    Print("Debug commands: /queueup debug on|off|add [count]|clear|list dungeon|raid|none")
    return
  end

  if command == "reset" then
    QueueUpDB = CopyTable(DEFAULTS)
    state.DB = QueueUpDB
    Print("settings reset.")
    UI.RefreshApplicants()
    return
  end

  Print("Unknown command: " .. command .. " (try /queueup help)")
end
