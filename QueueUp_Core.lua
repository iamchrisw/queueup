local addonName, addon = ...

addon._priv = addon._priv or {}
local priv = addon._priv
priv.util = priv.util or {}
priv.const = priv.const or {}
priv.state = priv.state or {}
priv.data = priv.data or {}
priv.rules = priv.rules or {}
priv.ui = priv.ui or {}
priv.ui2 = priv.ui2 or {}

local util = priv.util
local const = priv.const
local state = priv.state

const.DEFAULTS = {
  firstRun = true,
  rules = {
    roleWeights = {
      TANK = 3,
      HEALER = 3,
      DAMAGER = 2,
    },
    neededRoles = {
      TANK = true,
      HEALER = true,
      DAMAGER = true,
    },
    minRating = 2000,
    minIlvl = 240,
    classSpecPrefs = {},
    enableFlags = {
      useRole = true,
      useClassSpec = false,
      useRating = true,
      useIlvl = true,
    },
  },
  sort = {
    mode = "score",
    direction = "desc",
  },
  playerNotes = {},
}

local function CopyTable(tbl)
  if type(tbl) ~= "table" then
    return tbl
  end

  local out = {}
  for k, v in pairs(tbl) do
    out[k] = CopyTable(v)
  end
  return out
end

local function MergeDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then
        target[k] = CopyTable(v)
      else
        MergeDefaults(target[k], v)
      end
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

local function EnsureDB()
  QueueUpDB = QueueUpDB or {}

  local oldFirstRun = QueueUpDB.firstRun
  MergeDefaults(QueueUpDB, const.DEFAULTS)
  QueueUpDB.autoDecline = nil
  if oldFirstRun ~= nil then
    QueueUpDB.firstRun = oldFirstRun
  end

  return QueueUpDB
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99QueueUp|r: " .. tostring(msg))
end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end

  local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
  if not ok then
    return nil
  end
  return a, b, c, d, e, f, g, h, i, j, k, l
end

-- QueueUp UI tokens. Feature files should use these helpers instead of choosing
-- ad-hoc colours, fonts, and chrome for each screen.
const.UI = {
  spacing = { xs = 4, sm = 8, md = 12 },
  rowHeight = 24,
  headerHeight = 22,
  fonts = {
    -- Keep every QueueUp label on one face.  If an installed media addon has
    -- Accidental Presidency registered, ResolvePreferredFont() below swaps
    -- this fallback for that file automatically.
    primary = "Fonts\\ARIALN.TTF",
  },
  fontStrings = {},
  colors = {
    window = { 0.008, 0.009, 0.012, 0.98 },
    surface = { 0.018, 0.020, 0.026, 0.98 },
    elevated = { 0.030, 0.034, 0.043, 0.98 },
    header = { 0.040, 0.044, 0.054, 1 },
    border = { 0.15, 0.17, 0.21, 0.9 },
    accent = { 0.28, 0.70, 0.82, 1 },
    text = { 0.92, 0.93, 0.95, 1 },
    muted = { 0.55, 0.58, 0.63, 1 },
    warning = { 1.0, 0.72, 0.18, 1 },
    danger = { 0.92, 0.25, 0.25, 1 },
    success = { 0.30, 0.82, 0.46, 1 },
  },
}

local function ResolvePreferredFont()
  local fallback = "Fonts\\ARIALN.TTF"
  local libStub = rawget(_G, "LibStub")
  if type(libStub) == "function" then
    local ok, media = pcall(libStub, "LibSharedMedia-3.0", true)
    if ok and media and type(media.Fetch) == "function" then
      local fetchedOK, fetched = pcall(media.Fetch, media, "font", "Accidental Presidency", true)
      if fetchedOK and type(fetched) == "string" and fetched ~= "" then
        return fetched
      end
    end
  end
  return fallback
end

const.UI.fonts.primary = ResolvePreferredFont()
const.UI_COLUMNS = {
  name = 12,
  fit = 260,
  rating = 336,
  best = 404,
  ilvl = 452,
  role = 508,
  actions = 788,
}

local function ApplyUIFrame(frame, kind, edgeSize)
  if not frame or type(frame.SetBackdrop) ~= "function" then
    return
  end
  local colors = const.UI.colors
  local c = colors[kind or "surface"] or colors.surface
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = edgeSize or 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(c[1], c[2], c[3], c[4])
  local b = colors.border
  frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
end

local function TrackUIFont(fontString, role)
  if not fontString then return end
  fontString._queueupFontRole = role
  if fontString._queueupFontTracked then return end
  fontString._queueupFontTracked = true
  const.UI.fontStrings[#const.UI.fontStrings + 1] = fontString
end

local function SkinUIButton(button, kind)
  if not button then return end
  ApplyUIFrame(button, kind or "elevated", 1)
  local normal = button.GetNormalTexture and button:GetNormalTexture()
  if normal then normal:SetAlpha(0) end
  local pushed = button.GetPushedTexture and button:GetPushedTexture()
  if pushed then pushed:SetAlpha(0) end
  local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
  if not highlight then
    highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
  end
  local c = const.UI.colors.accent
  highlight:SetColorTexture(c[1], c[2], c[3], 0.12)
  local text = button.GetFontString and button:GetFontString()
  if not text then
    text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button._queueupText = text
    if button.GetText then
      text:SetText(button:GetText() or "")
    end
  end
  if text then
    local t = const.UI.colors.text
    TrackUIFont(text, "body")
    text:SetFont(const.UI.fonts.primary, 11, "")
    text:SetTextColor(t[1], t[2], t[3])
  end
end

local function SetUIButtonText(button, value)
  if not button then return end
  local text = button._queueupText
  if not text then
    text = button.GetFontString and button:GetFontString()
    if not text then
      text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
    button._queueupText = text
  end
  TrackUIFont(text, "body")
  text:SetText(tostring(value or ""))
  text:SetFont(const.UI.fonts.primary, 11, "")
  local c = const.UI.colors.text
  text:SetTextColor(c[1], c[2], c[3])
end

local function SkinUIFont(fontString, role)
  if not fontString or not fontString.SetFont then return end
  TrackUIFont(fontString, role)
  local isHeading = role == "heading"
  local size = isHeading and 13 or 11
  fontString:SetFont(const.UI.fonts.primary, size, "")
end

local function CreateUIFont(parent, layer, template, role)
  if not parent or not parent.CreateFontString then return nil end
  local fontString = parent:CreateFontString(nil, layer or "OVERLAY", template)
  SkinUIFont(fontString, role)
  return fontString
end

local function SkinUIEditBox(box)
  if not box then return end
  ApplyUIFrame(box, "elevated", 1)
  if box.SetFont then
    TrackUIFont(box, "body")
    box:SetFont(const.UI.fonts.primary, 11, "")
  end
  if box.SetTextColor then
    local t = const.UI.colors.text
    box:SetTextColor(t[1], t[2], t[3])
  end
end

util.ApplyUIFrame = ApplyUIFrame
util.SkinUIButton = SkinUIButton
util.SetUIButtonText = SetUIButtonText
util.SkinUIFont = SkinUIFont
util.CreateUIFont = CreateUIFont
util.SkinUIEditBox = SkinUIEditBox

local function RefreshUIFont()
  local preferred = ResolvePreferredFont()
  if preferred == const.UI.fonts.primary then return end
  const.UI.fonts.primary = preferred
  for i = 1, #const.UI.fontStrings do
    local fontString = const.UI.fontStrings[i]
    if fontString and fontString.SetFont then
      SkinUIFont(fontString, fontString._queueupFontRole)
    end
  end
end

util.RefreshUIFont = RefreshUIFont

-- SharedMedia-based font packs can load after QueueUp.  Re-apply the one
-- QueueUp face when that happens so a /reload is enough to pick it up.
local fontEvents = CreateFrame("Frame")
fontEvents:RegisterEvent("ADDON_LOADED")
fontEvents:RegisterEvent("PLAYER_LOGIN")
fontEvents:SetScript("OnEvent", function()
  RefreshUIFont()
end)

local RATING_PALETTE = {
  { min = 3800, hex = "ff8000" }, { min = 3645, hex = "f9753f" }, { min = 3525, hex = "f16961" },
  { min = 3405, hex = "e75e7f" }, { min = 3285, hex = "db529c" }, { min = 3165, hex = "cc47b9" },
  { min = 3045, hex = "b83dd6" }, { min = 2915, hex = "9c3eed" }, { min = 2795, hex = "715be5" },
  { min = 2675, hex = "2c6dde" }, { min = 2515, hex = "397ece" }, { min = 2395, hex = "5090bb" },
  { min = 2275, hex = "5ba2a8" }, { min = 2155, hex = "5fb494" }, { min = 2035, hex = "5ec67e" },
  { min = 1915, hex = "56d966" }, { min = 1795, hex = "46ec47" }, { min = 1675, hex = "1eff00" },
  { min = 1550, hex = "4fff35" }, { min = 1425, hex = "6bff4f" }, { min = 1300, hex = "81ff65" },
  { min = 1175, hex = "94ff78" }, { min = 1050, hex = "a5ff8b" }, { min = 925, hex = "b4ff9c" },
  { min = 800, hex = "c3ffae" }, { min = 675, hex = "d0ffbf" }, { min = 550, hex = "ddffd0" },
  { min = 425, hex = "eeffe1" }, { min = 300, hex = "f6fff1" }, { min = 200, hex = "ffffff" },
}

const.CURRENT_SEASON = {
  name = "Midnight Season 2",
  number = 2,
  raid = {
    name = "The Venomous Abyss",
    short = "Venomous Abyss",
    bosses = 8,
    aliases = {
      "The Venomous Abyss",
      "Venomous Abyss",
    },
    achievements = {
      normal = 63521,
      heroic = 63520,
      mythic = 63522,
    },
  },
  dungeons = {
    "Altar of Fangs",
    "Murder Row",
    "Den of Nalorakk",
    "The Blinding Vale",
    "Voidscar Arena",
    "Kings' Rest",
    "Temple of Sethraliss",
    "Ruby Life Pools",
  },
  ratingMilestones = {
    { rating = 1500, label = "Keystone Conqueror" },
    { rating = 2000, label = "Keystone Master - Breath of Blight" },
    { rating = 3000, label = "Keystone Legend - Breath of Ruin" },
  },
}

local function HexToRGB(hex)
  if type(hex) ~= "string" or #hex ~= 6 then
    return 1, 1, 1
  end
  local r = tonumber(hex:sub(1, 2), 16) or 255
  local g = tonumber(hex:sub(3, 4), 16) or 255
  local b = tonumber(hex:sub(5, 6), 16) or 255
  return r / 255, g / 255, b / 255
end

local function GetRatingColor(rating)
  rating = tonumber(rating) or 0
  if _G.RaiderIO and type(_G.RaiderIO.GetScoreColor) == "function" then
    local r, g, b = SafeCall(_G.RaiderIO.GetScoreColor, rating)
    if tonumber(r) and tonumber(g) and tonumber(b) then
      return r, g, b
    end
  end
  for i = 1, #RATING_PALETTE do
    if rating >= RATING_PALETTE[i].min then
      return HexToRGB(RATING_PALETTE[i].hex)
    end
  end
  return 1, 1, 1
end

const.PANEL_WIDTH = 900
const.PANEL_HEIGHT = 700
const.ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
const.ROLE_LABELS = {
  TANK = "Tank",
  HEALER = "Healer",
  DAMAGER = "Damage",
}
const.FIT_LABEL_BY_STEPS = {
  [1] = "Awful Fit",
  [2] = "Bad Fit",
  [3] = "Maybe",
  [4] = "Good Fit",
  [5] = "Great Fit",
  [6] = "Strong Fit",
  [7] = "Very Strong",
  [8] = "Excellent",
  [9] = "Top Contender",
  [10] = "Perfect Fit",
}

state.DB = EnsureDB()
state.frame = state.frame or CreateFrame("Frame")
state.reanchorTicker = state.reanchorTicker or nil
state.hookedFrames = state.hookedFrames or {}
state.applicantTicker = state.applicantTicker or nil

addon.UI = addon.UI or {}
addon.ApplicantData = addon.ApplicantData or {}
addon.RulesEngine = addon.RulesEngine or {}
addon.Actions = addon.Actions or {}
addon.NotesStore = addon.NotesStore or {}

util.CopyTable = CopyTable
util.MergeDefaults = MergeDefaults
util.EnsureDB = EnsureDB
util.Print = Print
util.SafeCall = SafeCall
util.GetRatingColor = GetRatingColor
