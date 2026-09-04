local addonName, addon = ...

local priv = addon._priv
local util = priv.util
local const = priv.const
local state = priv.state

local Print = util.Print
local SafeCall = util.SafeCall
local GetRatingColor = util.GetRatingColor

local PANEL_WIDTH = const.PANEL_WIDTH
local ROLE_ORDER = const.ROLE_ORDER
local ROLE_LABELS = const.ROLE_LABELS
local UI_COLORS = const.UI.colors
local UI_COLUMNS = const.UI_COLUMNS

local UI = addon.UI
local ApplicantData = addon.ApplicantData
local RulesEngine = addon.RulesEngine
local Actions = addon.Actions

local function CompactRaidProgress(text)
  text = tostring(text or "")
  local difficulties = {
    { token = "[Nn]ormal", suffix = "N" },
    { token = "[Hh][Cc]", suffix = "H" },
    { token = "[Mm]ythic", suffix = "M" },
  }
  local parts = {}
  for i = 1, #difficulties do
    local difficulty = difficulties[i]
    local killed, total = text:match("(%d+)/(%d+)%s+" .. difficulty.token)
    if killed and total then
      parts[#parts + 1] = string.format("%s%s/%s", difficulty.suffix, killed, total)
    end
  end
  return #parts > 0 and table.concat(parts, " ") or "--"
end

local function UpdateListHeadersForKind(kind)
  if not addon.bestHeaderButton or not addon.bestHeaderButton.label then
    return
  end
  if kind == "raid" then
    addon.bestHeaderButton.label:SetText("Progress")
  elseif kind == "dungeon" then
    addon.bestHeaderButton.label:SetText("Best Key")
  else
    addon.bestHeaderButton.label:SetText("Best")
  end
end

local function RefreshStandbyBars()
  if addon.standbyCenterMessage then
    addon.standbyCenterMessage:SetText("No active group listing detected.")
  end
end

local function MakeHeaderButton(parent, text, width, x, y, key)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width, 24)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  util.ApplyUIFrame(btn, "header", 1)

  local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER")
  label:SetText(text)
  label:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])
  btn.label = label

  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(0.28, 0.70, 0.82, 0.12)

  if key then
    btn:SetScript("OnEnter", function(self)
      if self.label then
        self.label:SetTextColor(UI_COLORS.warning[1], UI_COLORS.warning[2], UI_COLORS.warning[3])
      end
    end)
    btn:SetScript("OnLeave", function(self)
      if self.label then
        self.label:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])
      end
    end)
    btn:SetScript("OnClick", function()
      if state.DB.sort.mode == key then
        state.DB.sort.direction = (state.DB.sort.direction == "desc") and "asc" or "desc"
      else
        state.DB.sort.mode = key
        state.DB.sort.direction = "desc"
      end
      UI.RefreshApplicants()
    end)
  else
    btn:EnableMouse(false)
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnClick", nil)
  end

  return btn
end

local function CreateDataRow(parent, index, layout)
  local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  row._index = index
  row._layout = layout
  row._container = parent
  row:SetSize(layout.width, layout.height)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", layout.left, layout.top - ((index - 1) * (layout.height + layout.gap)))
  util.ApplyUIFrame(row, "surface", 1)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  local baseAlpha = (index % 2 == 0) and 0.18 or 0.08
  bg:SetColorTexture(0.09, 0.09, 0.1, baseAlpha)
  row.baseAlpha = baseAlpha
  row.bg = bg

  local leftAccent = row:CreateTexture(nil, "BORDER")
  leftAccent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
  leftAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
  leftAccent:SetWidth(2)
  leftAccent:SetColorTexture(0.28, 0.70, 0.82, 0.8)
  row.leftAccent = leftAccent

  local groupConnector = row:CreateTexture(nil, "BORDER")
  groupConnector:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -2)
  groupConnector:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 2)
  groupConnector:SetWidth(1)
  groupConnector:SetColorTexture(0.62, 0.56, 0.32, 0.7)
  groupConnector:Hide()
  row.groupConnector = groupConnector

  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 0.9, 0.45, 0.08)
  hover:Hide()
  row.hover = hover

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row, "LEFT", UI_COLUMNS.name, 0)
  row.name:SetWidth(220)
  row.name:SetJustifyH("LEFT")

  row.fitSquares = {}
  local squareColors = {
    { 0.86, 0.15, 0.15 }, -- red
    { 0.92, 0.48, 0.14 }, -- orange
    { 0.96, 0.84, 0.18 }, -- yellow
    { 0.47, 0.85, 0.34 }, -- light green
    { 0.10, 0.58, 0.23 }, -- dark green
    { 0.18, 0.68, 0.28 },
    { 0.20, 0.74, 0.40 },
    { 0.25, 0.80, 0.58 },
    { 0.35, 0.86, 0.78 },
    { 0.50, 0.92, 0.95 },
  }
  for i = 1, 10 do
    local square = row:CreateTexture(nil, "ARTWORK")
    square:SetSize(6, 10)
    square:SetPoint("LEFT", row, "LEFT", UI_COLUMNS.fit + ((i - 1) * 7), 0)
    square:SetColorTexture(squareColors[i][1], squareColors[i][2], squareColors[i][3], 0.96)
    row.fitSquares[i] = square
  end

  row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.rating:SetPoint("LEFT", row, "LEFT", UI_COLUMNS.rating, 0)
  row.rating:SetWidth(64)
  row.rating:SetJustifyH("CENTER")

  row.best = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.best:SetPoint("LEFT", row, "LEFT", UI_COLUMNS.best, 0)
  row.best:SetWidth(44)
  row.best:SetJustifyH("CENTER")

  row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.ilvl:SetPoint("LEFT", row, "LEFT", UI_COLUMNS.ilvl, 0)
  row.ilvl:SetWidth(52)
  row.ilvl:SetJustifyH("CENTER")

  row.role = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.role:SetPoint("LEFT", row, "LEFT", UI_COLUMNS.role, 0)
  row.role:SetWidth(104)
  row.role:SetJustifyH("CENTER")

  row.roleIcons = {}
  for iconIndex = 1, 3 do
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
    icon:Hide()
    row.roleIcons[iconIndex] = icon
  end
  row.roleIcons[1]:SetPoint("LEFT", row, "LEFT", 510, 0)
  row.roleIcons[2]:SetPoint("CENTER", row.role, "CENTER", 0, 0)
  row.roleIcons[3]:SetPoint("CENTER", row.role, "CENTER", 18, 0)

  row.specIcon = row:CreateTexture(nil, "ARTWORK")
  row.specIcon:SetSize(16, 16)
  row.specIcon:SetPoint("LEFT", row, "LEFT", 530, 0)
  row.specIcon:Hide()

  row.specText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.specText:SetPoint("LEFT", row, "LEFT", 550, 0)
  row.specText:SetWidth(156)
  row.specText:SetJustifyH("LEFT")
  row.specText:SetText("")

  row.deserterButton = CreateFrame("Button", nil, row)
  row.deserterButton:SetSize(14, 14)
  row.deserterButton:Hide()
  row.deserterButton.icon = row.deserterButton:CreateTexture(nil, "ARTWORK")
  row.deserterButton.icon:SetAllPoints()
  row.deserterButton.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther")
  row.deserterButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.deserterButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(71041)
      GameTooltip:AddLine("Detected on this applicant", 1, 0.35, 0.35, true)
    else
      GameTooltip:SetText("Dungeon Deserter")
      GameTooltip:AddLine("Detected on this applicant", 1, 0.35, 0.35, true)
    end
    GameTooltip:Show()
  end)
  row.deserterButton:SetScript("OnLeave", function()
    GameTooltip_Hide()
  end)

  row.noteButton = CreateFrame("Button", nil, row)
  row.noteButton:SetSize(14, 14)
  row.noteButton:Hide()
  row.noteButton.icon = row.noteButton:CreateTexture(nil, "ARTWORK")
  row.noteButton.icon:SetAllPoints()
  row.noteButton.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
  row.noteButton:SetScript("OnEnter", function(self)
    if not self.noteText or self.noteText == "" then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Signup Note")
    GameTooltip:AddLine(self.noteText, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  row.noteButton:SetScript("OnLeave", function()
    GameTooltip_Hide()
  end)

  row.score = nil

  row.decline = CreateFrame("Button", nil, row, "BackdropTemplate")
  row.decline:SetSize(24, 22)
  row.decline:SetPoint("LEFT", row, "LEFT", UI_COLUMNS.actions, 0)
  row.decline:SetText("")
  util.SkinUIButton(row.decline, "elevated")
  row.decline.icon = row.decline:CreateTexture(nil, "ARTWORK")
  row.decline.icon:SetSize(14, 14)
  row.decline.icon:SetPoint("CENTER")
  row.decline.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")

  row.invite = CreateFrame("Button", nil, row, "BackdropTemplate")
  row.invite:SetSize(24, 22)
  row.invite:SetPoint("RIGHT", row.decline, "LEFT", -4, 0)
  row.invite:SetText("")
  util.SkinUIButton(row.invite, "elevated")
  row.invite.icon = row.invite:CreateTexture(nil, "ARTWORK")
  row.invite.icon:SetSize(14, 14)
  row.invite.icon:SetPoint("CENTER")
  row.invite.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

  return row
end

local function GetHarmfulAura(unit, index)
  if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
    local aura = SafeCall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HARMFUL")
    if type(aura) == "table" then
      return aura.name, aura.duration, aura.expirationTime, aura.spellId or aura.spellID
    end
  end

  if type(UnitDebuff) == "function" then
    local name, _, _, _, duration, expirationTime, _, _, _, spellID = SafeCall(UnitDebuff, unit, index)
    return name, duration, expirationTime, spellID
  end

  return nil, nil, nil, nil
end

local function HasDungeonDeserter(unit)
  unit = unit or "player"
  if not UnitExists(unit) then
    return false, 0
  end
  for i = 1, 40 do
    local name, duration, expirationTime, spellID = GetHarmfulAura(unit, i)
    if not name then
      break
    end
    if tonumber(spellID) == 71041 then
      local remaining = 0
      if expirationTime and expirationTime > 0 and GetTime then
        remaining = math.max(0, expirationTime - GetTime())
      elseif duration and duration > 0 then
        remaining = duration
      end
      return true, remaining
    end
  end
  return false, 0
end

local function TryShowNativeApplicantTooltip(owner, data)
  if not owner or not data or type(data.applicantID) ~= "number" or data.applicantID <= 0 then
    return false
  end

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  if type(LFGListUtil_SetApplicantMemberTooltip) == "function" and type(data.memberIndex) == "number" then
    SafeCall(LFGListUtil_SetApplicantMemberTooltip, GameTooltip, data.applicantID, data.memberIndex)
    if GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
      return true
    end
    GameTooltip:ClearLines()
  end

  if type(LFGListUtil_SetApplicantTooltip) == "function" then
    SafeCall(LFGListUtil_SetApplicantTooltip, GameTooltip, data.applicantID)
    if GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
      return true
    end
    GameTooltip:ClearLines()
  end

  if type(LFGListUtil_SetSearchEntryTooltip) == "function" then
    SafeCall(LFGListUtil_SetSearchEntryTooltip, GameTooltip, data.applicantID)
    if GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
      return true
    end
    GameTooltip:ClearLines()
  end

  GameTooltip:Hide()
  return false
end

local function TryShowNativePlayerTooltip(owner, data)
  if not owner or not data then
    return false
  end
  local key = tostring(data.playerKey or data.name or "")
  key = key:gsub("^%s+", ""):gsub("%s+$", "")
  if key == "" then
    return false
  end

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  local ok = SafeCall(GameTooltip.SetHyperlink, GameTooltip, "player:" .. key)
  if ok ~= nil and GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
    return true
  end

  GameTooltip:Hide()
  return false
end

function UI.RefreshApplicants()
  if not addon.lfgTab or not addon.rows then
    return
  end

  local listingKind = "other"
  if priv.data.GetActiveListingKind then
    listingKind = priv.data.GetActiveListingKind()
  end
  local isRaidListing = (listingKind == "raid")
  local isListed = listingKind ~= "none"

  UpdateListHeadersForKind(listingKind)
  if addon.lfgListPanel then
    addon.lfgListPanel:SetShown(isListed)
  end
  if addon.lfgStandbyPanel then
    addon.lfgStandbyPanel:SetShown(not isListed)
  end

  if not isListed then
    if addon.applicantCountText then
      addon.applicantCountText:SetText("Applicants: N/A")
    end
    if addon.listingContextText then
      addon.listingContextText:SetText("Not currently listed!")
    end
    if addon.applicantDeserterText then
      addon.applicantDeserterText:SetText("Applicant deserter: --")
      addon.applicantDeserterText:SetTextColor(0.85, 0.85, 0.85)
    end
    if addon.deserterStatusText then
      local hasDeserter, remaining = HasDungeonDeserter("player")
      if hasDeserter then
        local mins = math.floor((remaining or 0) / 60)
        local secs = math.floor((remaining or 0) % 60)
        addon.deserterStatusText:SetText(string.format("Your deserter: ACTIVE (%d:%02d)", mins, secs))
        addon.deserterStatusText:SetTextColor(1, 0.3, 0.3)
      else
        addon.deserterStatusText:SetText("Your deserter: Clear")
        addon.deserterStatusText:SetTextColor(0.45, 0.95, 0.45)
      end
    end
    RefreshStandbyBars()
    return
  end

  local rows = ApplicantData.GetApplicants()
  for _, entry in ipairs(rows) do
    entry.score, entry.badge, entry.reason = RulesEngine.Score(entry)
  end

  local leaders = {}
  local membersByRoot = {}
  for _, row in ipairs(rows) do
    if row.isGroupMember then
      local root = tostring(row.groupRootID or row.applicantID or row.name)
      membersByRoot[root] = membersByRoot[root] or {}
      membersByRoot[root][#membersByRoot[root] + 1] = row
    else
      leaders[#leaders + 1] = row
    end
  end

  priv.rules.SortRows(leaders)
  for _, memberRows in pairs(membersByRoot) do
    priv.rules.SortRows(memberRows)
  end

  local displayRows = {}
  for _, leader in ipairs(leaders) do
    local root = tostring(leader.groupRootID or leader.applicantID or leader.name)
    displayRows[#displayRows + 1] = leader
    local children = membersByRoot[root]
    if children then
      for _, child in ipairs(children) do
        displayRows[#displayRows + 1] = child
      end
    end
  end

  addon.currentRows = displayRows
  local rowsPerPage = #addon.rows
  local maxOffset = math.max(0, #displayRows - rowsPerPage)

  if addon.applicantScrollFrame and addon.applicantScrollFrame.offset and addon.applicantScrollFrame.offset > maxOffset then
    addon.applicantScrollFrame.offset = maxOffset
  end

  if addon.applicantScrollFrame and FauxScrollFrame_Update and FauxScrollFrame_GetOffset then
    FauxScrollFrame_Update(addon.applicantScrollFrame, #displayRows, rowsPerPage, addon.rowStep or 40)
  end

  local offset = 0
  if addon.applicantScrollFrame and FauxScrollFrame_GetOffset then
    offset = FauxScrollFrame_GetOffset(addon.applicantScrollFrame) or 0
  end
  local startIndex = offset + 1

  for i = 1, #addon.rows do
    local widget = addon.rows[i]
    local dataIndex = startIndex + i - 1
    local data = displayRows[dataIndex]

    if data then
      local layout = widget._layout or { left = 0, top = 0, width = 834, height = 34, gap = 6 }
      local indent = data.isGroupMember and 18 or 0
      widget:ClearAllPoints()
      widget:SetPoint("TOPLEFT", widget._container or widget:GetParent(), "TOPLEFT", layout.left, layout.top - ((widget._index - 1) * (layout.height + layout.gap)))
      widget:SetSize(layout.width, layout.height)
      widget:Show()
      widget.name:ClearAllPoints()
      widget.name:SetPoint("LEFT", widget, "LEFT", 12 + indent, 0)
      widget.name:SetText(tostring(data.name or "-"))

      local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classFile or ""]
      if classColor then
        widget.name:SetTextColor(classColor.r, classColor.g, classColor.b)
      else
        widget.name:SetTextColor(0.95, 0.95, 0.95)
      end
      if data.isInvited then
        widget.name:SetTextColor(0.45, 1, 0.45)
      end

      local fitSteps = tonumber(data.fitSteps) or 1
      local fitColor = { 0.86, 0.15, 0.15 } -- awful red
      if fitSteps >= 8 then
        fitColor = { 0.35, 0.86, 0.78 } -- cyan
      elseif fitSteps >= 6 then
        fitColor = { 0.20, 0.74, 0.40 } -- strong green
      elseif fitSteps >= 5 then
        fitColor = { 0.10, 0.58, 0.23 } -- dark green
      elseif fitSteps == 4 then
        fitColor = { 0.47, 0.85, 0.34 } -- light green
      elseif fitSteps == 3 then
        fitColor = { 0.96, 0.84, 0.18 } -- yellow
      elseif fitSteps == 2 then
        fitColor = { 0.92, 0.48, 0.14 } -- orange/red
      end
      for s = 1, 10 do
        local sq = widget.fitSquares and widget.fitSquares[s]
        if sq then
          if s <= fitSteps then
            sq:SetColorTexture(fitColor[1], fitColor[2], fitColor[3], 0.96)
          else
            sq:SetColorTexture(0.20, 0.20, 0.22, 0.9)
          end
        end
      end

      widget.rating:SetText(tostring(data.rating or 0))
      local raidProgressText = tostring(data.raidProgressText or "")
      local best = tonumber(data.highestCompletion)
      if isRaidListing then
        if raidProgressText ~= "" then
          widget.best:SetText(CompactRaidProgress(raidProgressText))
        else
          widget.best:SetText("--")
        end
      else
        if best and best > 0 then
          widget.best:SetText("+" .. tostring(best))
        else
          widget.best:SetText("--")
        end
      end
      widget.ilvl:SetText(tostring(math.floor(data.ilvl or 0)))

      local primaryRole = nil
      for _, roleKey in ipairs(ROLE_ORDER) do
        if data.roles and data.roles[roleKey] then
          primaryRole = roleKey
          break
        end
      end
      if not primaryRole then
        primaryRole = data.role or "DAMAGER"
      end

      if primaryRole then
        widget.role:SetText("")
      else
        widget.role:SetText("-")
      end
      for idx = 1, #widget.roleIcons do
        local icon = widget.roleIcons[idx]
        if icon and idx == 1 and primaryRole then
          icon:SetPoint("CENTER", widget.role, "CENTER", 0, 0)
          icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
          if GetTexCoordsForRole then
            icon:SetTexCoord(GetTexCoordsForRole(primaryRole))
          else
            icon:SetTexCoord(priv.rules.GetRoleTexCoords(primaryRole))
          end
          icon:Show()
        elseif icon then
          icon:Hide()
        end
      end

      local specIcon = priv.rules.GetSpecIconForRow(data)
      if specIcon then
        widget.specIcon:SetTexture(specIcon)
        widget.specIcon:SetDesaturated(false)
        widget.specIcon:Show()
      else
        widget.specIcon:Hide()
      end
      local specText = tostring(data.spec or "")
      if specText == "" then
        specText = "-"
      end
      widget.specText:SetText(specText)
      widget.specText:SetTextColor(0.92, 0.92, 0.92)

      if data.hasDeserter then
        local textOffset = math.min((widget.name:GetStringWidth() or 0) + 8, 200)
        widget.deserterButton:ClearAllPoints()
        widget.deserterButton:SetPoint("LEFT", widget.name, "LEFT", textOffset, 0)
        widget.deserterButton:Show()
      else
        widget.deserterButton:Hide()
      end

      if data.applicationNote and data.applicationNote ~= "" and not data.isGroupMember then
        widget.noteButton.noteText = data.applicationNote
        widget.noteButton:ClearAllPoints()
        local noteOffset = math.min((widget.name:GetStringWidth() or 0) + 8, 182)
        widget.noteButton:SetPoint("LEFT", widget.name, "LEFT", noteOffset, 0)
        if widget.deserterButton:IsShown() then
          widget.noteButton:SetPoint("LEFT", widget.deserterButton, "RIGHT", 2, 0)
        end
        widget.noteButton:Show()
      else
        widget.noteButton.noteText = nil
        widget.noteButton:Hide()
      end
      widget.role:SetTextColor(0.95, 0.82, 0.3)
      local rr, rg, rb = GetRatingColor(data.rating or 0)
      widget.rating:SetTextColor(rr, rg, rb)
      widget.best:SetTextColor(0.7, 0.85, 1)
      widget.ilvl:SetTextColor(0.88, 0.88, 0.88)

      if data.badge == "Great Fit" then
        widget.leftAccent:SetColorTexture(0.14, 0.62, 0.22, 0.9)
      elseif data.badge == "Good Fit" then
        widget.leftAccent:SetColorTexture(0.3, 0.9, 0.36, 0.9)
      elseif data.badge == "Maybe" then
        widget.leftAccent:SetColorTexture(0.92, 0.7, 0.2, 0.9)
      elseif data.badge == "Bad Fit" then
        widget.leftAccent:SetColorTexture(0.95, 0.45, 0.45, 0.9)
      else
        widget.leftAccent:SetColorTexture(0.7, 0.08, 0.08, 0.95)
      end

      if data.isGroupMember then
        if widget.bg then
          if data.hasDeserter then
            widget.bg:SetColorTexture(0.28, 0.05, 0.05, 0.42)
            widget:SetBackdropBorderColor(0.56, 0.18, 0.18, 0.9)
          elseif data.isInvited then
            widget.bg:SetColorTexture(0.05, 0.24, 0.09, 0.42)
            widget:SetBackdropBorderColor(0.25, 0.66, 0.34, 0.9)
          else
            widget.bg:SetColorTexture(0.07, 0.08, 0.1, 0.36)
            widget:SetBackdropBorderColor(0.24, 0.24, 0.24, 0.9)
          end
        end
        if widget.groupConnector then
          widget.groupConnector:Show()
        end
      else
        if widget.bg then
          if data.hasDeserter then
            widget.bg:SetColorTexture(0.36, 0.06, 0.06, 0.52)
            widget:SetBackdropBorderColor(0.62, 0.2, 0.2, 0.95)
          elseif data.isInvited then
            widget.bg:SetColorTexture(0.07, 0.3, 0.12, 0.54)
            widget:SetBackdropBorderColor(0.30, 0.72, 0.40, 0.95)
          else
            widget.bg:SetColorTexture(0.08, 0.08, 0.07, widget.baseAlpha or 0.14)
            widget:SetBackdropBorderColor(0.24, 0.24, 0.24, 0.9)
          end
        end
        if widget.groupConnector then
          widget.groupConnector:Hide()
        end
      end

      widget:SetScript("OnEnter", function(self)
        if self.hover then
          self.hover:Show()
        end
        local usedNative = TryShowNativePlayerTooltip(self, data) or TryShowNativeApplicantTooltip(self, data)
        if not usedNative then
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(data.name)
          local rolesText = {}
          for _, roleKey in ipairs(ROLE_ORDER) do
            if data.roles and data.roles[roleKey] then
              rolesText[#rolesText + 1] = ROLE_LABELS[roleKey] or roleKey
            end
          end
          if #rolesText == 0 then
            rolesText[1] = ROLE_LABELS[data.role] or data.role or "-"
          end
          local classText = (data.classLocalized ~= "" and data.classLocalized) or (data.classFile ~= "" and data.classFile) or "Unknown"
          local specText = (data.spec and data.spec ~= "") and data.spec or "-"
          GameTooltip:AddLine("Role: " .. table.concat(rolesText, " + "), 1, 1, 1)
          GameTooltip:AddLine("Class - Spec: " .. classText .. " - " .. specText, 1, 1, 1)
          GameTooltip:AddLine("Score: " .. tostring(data.score), 1, 1, 1)
          if data.highestCompletion then
            GameTooltip:AddLine("Highest completion: +" .. tostring(data.highestCompletion), 0.7, 0.85, 1)
          end
          if data.raidProgressText and data.raidProgressText ~= "" then
            GameTooltip:AddLine("Raid progress: " .. tostring(data.raidProgressText), 0.7, 0.85, 1, true)
          end
        end
        if data.fitBreakdown and data.fitBreakdown ~= "" then
          GameTooltip:AddLine(data.fitBreakdown, 0.78, 0.9, 1, true)
        end
        GameTooltip:Show()
      end)
      widget:SetScript("OnLeave", function(self)
        if self.hover then
          self.hover:Hide()
        end
        GameTooltip_Hide()
      end)

      widget.invite:SetScript("OnClick", function()
        if Actions.Invite(data.applicantID) then
          Print("Invited " .. data.name)
        else
          Print("Invite failed for " .. data.name)
        end
      end)

      widget.decline:SetScript("OnClick", function()
        if Actions.Decline(data.applicantID) then
          Print("Declined " .. data.name)
        else
          Print("Decline failed for " .. data.name)
        end
      end)

      local canAct = (not data.isGroupMember) and (not data.isFake)
      widget.invite:SetEnabled(canAct)
      widget.decline:SetEnabled(canAct)
      if widget.invite.icon then
        widget.invite.icon:SetDesaturated(not canAct)
        widget.invite.icon:SetVertexColor(canAct and 1 or 0.6, canAct and 1 or 0.6, canAct and 1 or 0.6)
      end
      if widget.decline.icon then
        widget.decline.icon:SetDesaturated(not canAct)
        widget.decline.icon:SetVertexColor(canAct and 1 or 0.6, canAct and 1 or 0.6, canAct and 1 or 0.6)
      end
      widget.invite:SetShown(not data.isGroupMember)
      widget.decline:SetShown(not data.isGroupMember)

      widget.invite:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Invite")
        GameTooltip:Show()
      end)
      widget.invite:SetScript("OnLeave", function()
        GameTooltip_Hide()
      end)
      widget.decline:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Decline")
        GameTooltip:Show()
      end)
      widget.decline:SetScript("OnLeave", function()
        GameTooltip_Hide()
      end)
    else
      widget:Hide()
    end
  end

  if addon.applicantCountText then
    addon.applicantCountText:SetText("Applicants: " .. tostring(#leaders))
  end
  if addon.listingContextText then
    local kind = "Other"
    if priv.data.GetActiveListingKind then
      local rawKind = priv.data.GetActiveListingKind()
      if rawKind == "dungeon" then
        kind = "Dungeon"
      elseif rawKind == "raid" then
        kind = "Raid"
      elseif rawKind == "none" then
        kind = "Not Listed"
      end
    end
    addon.listingContextText:SetText("Listing (" .. kind .. "): " .. priv.data.GetActiveListingContext())
  end
  if addon.applicantDeserterText then
    local count = 0
    for _, row in ipairs(rows) do
      if row.hasDeserter then
        count = count + 1
      end
    end
    if count > 0 then
      addon.applicantDeserterText:SetText("Applicant deserter: " .. tostring(count))
      addon.applicantDeserterText:SetTextColor(1, 0.35, 0.35)
    else
      addon.applicantDeserterText:SetText("Applicant deserter: 0")
      addon.applicantDeserterText:SetTextColor(0.45, 0.95, 0.45)
    end
  end
  if addon.deserterStatusText then
    local hasDeserter, remaining = HasDungeonDeserter("player")
    if hasDeserter then
      local mins = math.floor((remaining or 0) / 60)
      local secs = math.floor((remaining or 0) % 60)
      addon.deserterStatusText:SetText(string.format("Your deserter: ACTIVE (%d:%02d)", mins, secs))
      addon.deserterStatusText:SetTextColor(1, 0.3, 0.3)
    else
      addon.deserterStatusText:SetText("Your deserter: Clear")
      addon.deserterStatusText:SetTextColor(0.45, 0.95, 0.45)
    end
  end
end
local function BuildLFGTab(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()

  local sectionWidth = PANEL_WIDTH - 28
  local rowLayout = {
    left = 10,
    top = -42,
    width = sectionWidth - 20,
    height = 24,
    gap = 2,
  }

  local topBar = CreateFrame("Frame", nil, tab)
  topBar:SetPoint("TOPLEFT", tab, "TOPLEFT", 14, -58)
  topBar:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -14, -58)
  topBar:SetHeight(30)
  topBar:SetFrameLevel(tab:GetFrameLevel() + 3)

  local debugLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  debugLabel:SetPoint("LEFT", topBar, "LEFT", 10, 0)
  debugLabel:SetText("Debug")
  debugLabel:SetTextColor(0.65, 0.65, 0.68)
  local debugDrop = CreateFrame("Button", "QueueUpDebugDropdown", topBar, "BackdropTemplate")
  debugDrop:SetSize(132, 22)
  debugDrop:SetPoint("LEFT", debugLabel, "RIGHT", 8, 0)
  util.SkinUIButton(debugDrop, "elevated")
  debugDrop.label = debugDrop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  debugDrop.label:SetPoint("LEFT", debugDrop, "LEFT", 8, 0)
  debugDrop.label:SetText("Simulation")
  debugDrop.label:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])
  debugDrop.arrow = debugDrop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  debugDrop.arrow:SetPoint("RIGHT", debugDrop, "RIGHT", -8, 0)
  debugDrop.arrow:SetText("▼")
  debugDrop.arrow:SetTextColor(UI_COLORS.muted[1], UI_COLORS.muted[2], UI_COLORS.muted[3])

  local debugMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  debugMenu:SetSize(196, 84)
  debugMenu:SetFrameStrata("TOOLTIP")
  util.ApplyUIFrame(debugMenu, "elevated", 1)
  debugMenu:Hide()
  debugMenu:SetPoint("TOPLEFT", debugDrop, "BOTTOMLEFT", 0, -4)
  local function AddDebugOption(index, text, value)
    local option = CreateFrame("Button", nil, debugMenu, "BackdropTemplate")
    option:SetSize(190, 24)
    option:SetPoint("TOPLEFT", debugMenu, "TOPLEFT", 3, -3 - ((index - 1) * 26))
    option:SetText(text)
    util.SkinUIButton(option, "elevated")
    option:SetScript("OnClick", function()
      if value == "stop" then
        if priv.debug and priv.debug.Stop then priv.debug.Stop() end
        debugDrop.label:SetText("Simulation")
      else
        if priv.debug and priv.debug.Start then priv.debug.Start(value) end
        debugDrop.label:SetText(value == "raid" and "Raid (50)" or "Mythic+ (50)")
      end
      debugMenu:Hide()
      UI.RefreshApplicants()
    end)
  end
  AddDebugOption(1, "Mythic+ — trickle 50", "dungeon")
  AddDebugOption(2, "Raid — trickle 50", "raid")
  AddDebugOption(3, "Stop simulation", "stop")
  debugDrop:SetScript("OnClick", function()
    debugMenu:SetShown(not debugMenu:IsShown())
  end)
  addon.debugDropdown = debugDrop

  tab.sortInfo = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tab.sortInfo:SetPoint("LEFT", topBar, "LEFT", 10, 0)
  tab.sortInfo:SetWidth(175)
  tab.sortInfo:SetJustifyH("LEFT")
  tab.sortInfo:SetText("Sort: Name / Fit / Rating / iLvl")
  tab.sortInfo:SetTextColor(0.94, 0.94, 0.94)
  tab.sortInfo:Hide()

  local deserterStatus = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  deserterStatus:SetPoint("RIGHT", topBar, "RIGHT", -14, 0)
  deserterStatus:SetWidth(148)
  deserterStatus:SetJustifyH("RIGHT")
  deserterStatus:SetText("Your deserter: Clear")
  deserterStatus:SetTextColor(0.45, 0.95, 0.45)
  addon.deserterStatusText = deserterStatus
  deserterStatus:Hide()

  local applicantDeserter = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  applicantDeserter:SetPoint("RIGHT", deserterStatus, "LEFT", -10, 0)
  applicantDeserter:SetWidth(158)
  applicantDeserter:SetJustifyH("RIGHT")
  applicantDeserter:SetText("Applicant deserter: 0")
  applicantDeserter:SetTextColor(0.45, 0.95, 0.45)
  addon.applicantDeserterText = applicantDeserter
  applicantDeserter:Hide()

  tab.applicantCount = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  tab.applicantCount:SetPoint("RIGHT", applicantDeserter, "LEFT", -10, 0)
  tab.applicantCount:SetText("Applicants: 0")
  tab.applicantCount:SetTextColor(0.98, 0.86, 0.4)
  addon.applicantCountText = tab.applicantCount

  local listingContext = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  listingContext:SetPoint("RIGHT", tab.applicantCount, "LEFT", -18, 0)
  listingContext:SetWidth(260)
  listingContext:SetJustifyH("RIGHT")
  listingContext:SetText("Listing: Not currently listed")
  listingContext:SetTextColor(0.8, 0.9, 1)
  addon.listingContextText = listingContext

  local listPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  listPanel:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
  listPanel:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -6)
  listPanel:SetHeight(430)
  util.ApplyUIFrame(listPanel, "surface", 1)
  addon.lfgListPanel = listPanel

  local headerStrip = CreateFrame("Frame", nil, listPanel, "BackdropTemplate")
  headerStrip:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -8)
  headerStrip:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -8, -8)
  headerStrip:SetHeight(22)
  util.ApplyUIFrame(headerStrip, "header", 1)

  MakeHeaderButton(headerStrip, "Name", 220, UI_COLUMNS.name + 2, -1, "name")
  MakeHeaderButton(headerStrip, "Fit", 86, UI_COLUMNS.fit - 10, -1, "score")
  MakeHeaderButton(headerStrip, "Rating", 64, UI_COLUMNS.rating - 2, -1, "rating")
  addon.bestHeaderButton = MakeHeaderButton(headerStrip, "Best", 72, UI_COLUMNS.best - 14, -1, nil)
  MakeHeaderButton(headerStrip, "iLvl", 52, UI_COLUMNS.ilvl, -1, "ilvl")
  MakeHeaderButton(headerStrip, "Role / Spec", 182, UI_COLUMNS.role, -1, nil)
  MakeHeaderButton(headerStrip, "Actions", 116, UI_COLUMNS.actions - 2, -1, nil)

  local scrollContainer = CreateFrame("Frame", nil, listPanel)
  scrollContainer:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -34)
  scrollContainer:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -26, 8)
  scrollContainer:SetClipsChildren(true)

  local scrollFrame = CreateFrame("ScrollFrame", nil, listPanel, "FauxScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 0, 0)
  scrollFrame:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", 0, 0)
  scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, rowLayout.height + rowLayout.gap, function()
      UI.RefreshApplicants()
    end)
  end)
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    if not self.ScrollBar then
      return
    end
    local step = addon.rowStep or 40
    self.ScrollBar:SetValue(self.ScrollBar:GetValue() - (delta * step))
  end)
  addon.applicantScrollFrame = scrollFrame
  addon.rowStep = rowLayout.height + rowLayout.gap

  rowLayout.left = 0
  rowLayout.top = 0
  rowLayout.width = 834

  addon.rows = {}
  for i = 1, 16 do
    addon.rows[i] = CreateDataRow(scrollContainer, i, rowLayout)
  end

  local standbyPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  standbyPanel:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
  standbyPanel:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -6)
  standbyPanel:SetHeight(430)
  util.ApplyUIFrame(standbyPanel, "surface", 1)
  standbyPanel:Hide()

  local standbyTitle = standbyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  standbyTitle:SetPoint("TOPLEFT", standbyPanel, "TOPLEFT", 12, -12)
  standbyTitle:SetText("Not Currently Listed")
  standbyTitle:SetTextColor(0.96, 0.83, 0.34)

  local standbyCenterMessage = standbyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  standbyCenterMessage:SetPoint("CENTER", standbyPanel, "CENTER", 0, 0)
  standbyCenterMessage:SetText("Create a group to see your applicants!")
  standbyCenterMessage:SetTextColor(0.9, 0.9, 0.9)
  addon.standbyCenterMessage = standbyCenterMessage

  addon.lfgStandbyPanel = standbyPanel
  SafeCall(RefreshStandbyBars)

  local rulesPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  rulesPanel:SetPoint("TOPLEFT", listPanel, "BOTTOMLEFT", 0, -10)
  rulesPanel:SetPoint("TOPRIGHT", listPanel, "BOTTOMRIGHT", 0, -10)
  rulesPanel:SetHeight(150)
  util.ApplyUIFrame(rulesPanel, "surface", 1)

  local scoringPane = CreateFrame("Frame", nil, rulesPanel)
  scoringPane:SetPoint("TOPLEFT", rulesPanel, "TOPLEFT", 10, -10)
  scoringPane:SetPoint("BOTTOMRIGHT", rulesPanel, "BOTTOMRIGHT", -10, 8)

  local function AttachTooltip(widget, title, body)
    if not widget then
      return
    end
    widget:EnableMouse(true)
    widget:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(title or "QueueUp")
      if body and body ~= "" then
        GameTooltip:AddLine(body, 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
      GameTooltip_Hide()
    end)
  end

  local rulesHelp = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rulesHelp:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -2)
  rulesHelp:SetWidth(800)
  rulesHelp:SetJustifyH("LEFT")
  rulesHelp:SetText("How applicants are scored and sorted. Enable the checks you care about, then set role and minimum thresholds.")
  rulesHelp:SetTextColor(0.78, 0.78, 0.78)

  local ratingLabel = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ratingLabel:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -26)
  ratingLabel:SetText("Min rating")

  local ratingBox = CreateFrame("EditBox", nil, scoringPane, "InputBoxTemplate")
  ratingBox:SetSize(56, 22)
  util.SkinUIEditBox(ratingBox)
  ratingBox:SetPoint("LEFT", ratingLabel, "RIGHT", 8, 0)
  ratingBox:SetAutoFocus(false)
  ratingBox:SetNumeric(true)
  ratingBox:SetNumber(state.DB.rules.minRating)
  ratingBox:SetScript("OnEnterPressed", function(self)
    state.DB.rules.minRating = self:GetNumber() or state.DB.rules.minRating
    self:ClearFocus()
    UI.RefreshApplicants()
  end)
  AttachTooltip(ratingBox, "Minimum M+ Rating", "Applicants at or above this value get the minimum-rating bonus.")

  local ilvlLabel = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ilvlLabel:SetPoint("LEFT", ratingBox, "RIGHT", 12, 0)
  ilvlLabel:SetText("Min ilvl")

  local ilvlBox = CreateFrame("EditBox", nil, scoringPane, "InputBoxTemplate")
  ilvlBox:SetSize(56, 22)
  util.SkinUIEditBox(ilvlBox)
  ilvlBox:SetPoint("LEFT", ilvlLabel, "RIGHT", 8, 0)
  ilvlBox:SetAutoFocus(false)
  ilvlBox:SetNumeric(true)
  ilvlBox:SetNumber(state.DB.rules.minIlvl)
  addon.ilvlBox = ilvlBox
  local function CommitMinIlvl(self, clearFocus)
    local n = self:GetNumber()
    if n == nil then
      n = tonumber(self:GetText() or "")
    end
    n = math.max(0, math.floor((tonumber(n) or state.DB.rules.minIlvl or 0) + 0.5))
    state.DB.rules.minIlvl = n
    self:SetNumber(n)
    if clearFocus then
      self:ClearFocus()
    end
    UI.RefreshApplicants()
  end
  ilvlBox:SetScript("OnEnterPressed", function(self)
    CommitMinIlvl(self, true)
  end)
  ilvlBox:SetScript("OnEditFocusLost", function(self)
    CommitMinIlvl(self, false)
  end)
  AttachTooltip(ilvlBox, "Minimum Item Level", "Applicants at or above this value get the item-level bonus.")

  local function AttachCheckLabel(parentFrame, check, text)
    local label = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    label:SetText(text)
    return label
  end

  local roleCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  roleCheck:SetSize(18, 18)
  roleCheck:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -54)
  AttachCheckLabel(scoringPane, roleCheck, "Role contributes to score?")
  roleCheck:SetChecked(state.DB.rules.enableFlags.useRole)
  roleCheck:SetScript("OnClick", function(self)
    state.DB.rules.enableFlags.useRole = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(roleCheck, "Use Role Match", "When enabled, a role that is needed contributes to the players score.")

  local ratingCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  ratingCheck:SetSize(18, 18)
  ratingCheck:SetPoint("LEFT", roleCheck, "RIGHT", 150, 0)
  AttachCheckLabel(scoringPane, ratingCheck, "Rating contributes to score?")
  ratingCheck:SetChecked(state.DB.rules.enableFlags.useRating)
  ratingCheck:SetScript("OnClick", function(self)
    state.DB.rules.enableFlags.useRating = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(ratingCheck, "Use Rating", "When enabled, the players rating contributes to score.")

  local ilvlCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  ilvlCheck:SetSize(18, 18)
  ilvlCheck:SetPoint("LEFT", ratingCheck, "RIGHT", 150, 0)
  AttachCheckLabel(scoringPane, ilvlCheck, "Item level contributes to score?")
  ilvlCheck:SetChecked(state.DB.rules.enableFlags.useIlvl)
  ilvlCheck:SetScript("OnClick", function(self)
    state.DB.rules.enableFlags.useIlvl = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(ilvlCheck, "Use Item Level", "When enabled, the players item level contributes to score.")

  local needRolesLabel = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  needRolesLabel:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -96)
  needRolesLabel:SetText("Needed roles:")

  local needTankCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  needTankCheck:SetSize(18, 18)
  needTankCheck:SetPoint("TOPLEFT", needRolesLabel, "BOTTOMLEFT", 0, -2)
  AttachCheckLabel(scoringPane, needTankCheck, "Tank")
  needTankCheck:SetChecked((state.DB.rules.neededRoles and state.DB.rules.neededRoles.TANK) and true or false)
  needTankCheck:SetScript("OnClick", function(self)
    state.DB.rules.neededRoles = state.DB.rules.neededRoles or {}
    state.DB.rules.neededRoles.TANK = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(needTankCheck, "Need Tank", "Applicants offering Tank role are considered role matches.")

  local needHealerCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  needHealerCheck:SetSize(18, 18)
  needHealerCheck:SetPoint("LEFT", needTankCheck, "RIGHT", 100, 0)
  AttachCheckLabel(scoringPane, needHealerCheck, "Healer")
  needHealerCheck:SetChecked((state.DB.rules.neededRoles and state.DB.rules.neededRoles.HEALER) and true or false)
  needHealerCheck:SetScript("OnClick", function(self)
    state.DB.rules.neededRoles = state.DB.rules.neededRoles or {}
    state.DB.rules.neededRoles.HEALER = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(needHealerCheck, "Need Healer", "Applicants offering Healer role are considered role matches.")

  local needDamageCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  needDamageCheck:SetSize(18, 18)
  needDamageCheck:SetPoint("LEFT", needHealerCheck, "RIGHT", 100, 0)
  AttachCheckLabel(scoringPane, needDamageCheck, "Damage")
  needDamageCheck:SetChecked((state.DB.rules.neededRoles and state.DB.rules.neededRoles.DAMAGER) and true or false)
  needDamageCheck:SetScript("OnClick", function(self)
    state.DB.rules.neededRoles = state.DB.rules.neededRoles or {}
    state.DB.rules.neededRoles.DAMAGER = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(needDamageCheck, "Need Damage", "Applicants offering Damage role are considered role matches.")

  addon.lfgClassBox = nil
  addon.lfgClassLabel = nil
  addon.lfgWhisperBox = nil
  addon.lfgWhisperHelp = nil
  addon.lfgTab = tab
end

priv.ui.BuildLFGTab = BuildLFGTab
