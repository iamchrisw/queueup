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
