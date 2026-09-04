local addonName, addon = ...

local priv = addon._priv
local util = priv.util
local const = priv.const
local state = priv.state
local UI_COLORS = const.UI.colors

local Print = util.Print
local SafeCall = util.SafeCall

local UI = addon.UI
local NotesStore = addon.NotesStore

local function GetNextRatingMilestone(score)
  local season = const.CURRENT_SEASON or {}
  local milestones = season.ratingMilestones or {}
  score = tonumber(score) or 0
  for i = 1, #milestones do
    local milestone = milestones[i]
    local target = tonumber(milestone.rating) or 0
    if score < target then
      return string.format("Next: %s (%d rating remaining)", tostring(milestone.label or target), target - score)
    end
  end
  if #milestones > 0 then
    return tostring(milestones[#milestones].label or "Top milestone") .. " complete"
  end
  return nil
end

local function GetMythicSummary()
  local lines = {}

  local season = const.CURRENT_SEASON or {}
  local seasonRaid = season.raid or {}

  lines[#lines + 1] = "Group: " .. ((IsInGroup() and "In Group") or "Solo")
    .. "  |  Leader: " .. ((UnitName("player") and UnitIsGroupLeader("player") and "Yes") or "No")

  if C_LFGList then
    local activeInfo = SafeCall(C_LFGList.GetActiveEntryInfo)
    if type(activeInfo) == "table" then
      lines[#lines + 1] = "Listing: " .. tostring(activeInfo.name or "Active")
    else
      lines[#lines + 1] = "Listing: None"
    end
  end

  lines[#lines + 1] = "Season: " .. tostring(season.name or "Current")
  if seasonRaid.name then
    lines[#lines + 1] = string.format("Raid: %s (%d bosses)", seasonRaid.name, tonumber(seasonRaid.bosses) or 0)
  end

  if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local score = tonumber(SafeCall(C_ChallengeMode.GetOverallDungeonScore)) or 0
    lines[#lines + 1] = "M+ Rating: " .. tostring(math.floor(score + 0.5))
    local milestoneText = GetNextRatingMilestone(score)
    if milestoneText then
      lines[#lines + 1] = milestoneText
    end
  end

  return table.concat(lines, "\n")
end

local function ParseClassSpecPrefs(text)
  local prefs = {}
  for token in string.gmatch(string.upper(text or ""), "[^,%s]+") do
    prefs[token] = true
  end
  return prefs
end

local function FormatClassSpecPrefs()
  local keys = {}
  for key in pairs(state.DB.rules.classSpecPrefs) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return table.concat(keys, ",")
end
local function BuildGroupUnits()
  local units = {}
  if IsInRaid() then
    local count = GetNumGroupMembers() or 0
    for i = 1, count do
      units[#units + 1] = "raid" .. i
    end
  elseif IsInGroup() then
    units[#units + 1] = "player"
    local count = GetNumSubgroupMembers() or 0
    for i = 1, count do
      units[#units + 1] = "party" .. i
    end
  else
    units[#units + 1] = "player"
  end
  return units
end

local SPEC_LABELS = {
  [62] = "Arcane", [63] = "Fire", [64] = "Frost",
  [65] = "Holy", [66] = "Protection", [70] = "Retribution",
  [71] = "Arms", [72] = "Fury", [73] = "Protection",
  [102] = "Balance", [103] = "Feral", [104] = "Guardian", [105] = "Restoration",
  [250] = "Blood", [251] = "Frost", [252] = "Unholy",
  [253] = "Beast Mastery", [254] = "Marksmanship", [255] = "Survival",
  [256] = "Discipline", [257] = "Holy", [258] = "Shadow",
  [259] = "Assassination", [260] = "Outlaw", [261] = "Subtlety",
  [262] = "Elemental", [263] = "Enhancement", [264] = "Restoration",
  [265] = "Destruction", [266] = "Affliction", [267] = "Demonology",
  [268] = "Brewmaster", [269] = "Windwalker", [270] = "Mistweaver",
  [577] = "Havoc", [581] = "Vengeance",
  [1467] = "Devastation", [1468] = "Preservation", [1473] = "Augmentation",
}

local CLASS_LABELS = {
  DEATHKNIGHT = "Death Knight",
  DEMONHUNTER = "Demon Hunter",
  DRUID = "Druid",
  EVOKER = "Evoker",
  HUNTER = "Hunter",
  MAGE = "Mage",
  MONK = "Monk",
  PALADIN = "Paladin",
  PRIEST = "Priest",
  ROGUE = "Rogue",
  SHAMAN = "Shaman",
  WARLOCK = "Warlock",
  WARRIOR = "Warrior",
}

local function Specs(...)
  local out = {}
  local n = select("#", ...)
  for i = 1, n do
    out[#out + 1] = select(i, ...)
  end
  return out
end

local UTILITY_ENTRIES = {
  { category = "Death Knight", spellID = 47528, name = "Mind Freeze", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 207167, name = "Blinding Sleet", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 221562, name = "Asphyxiate", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 49576, name = "Death Grip", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 45524, name = "Chains of Ice", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 61999, name = "Raise Ally", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 51052, name = "Anti-Magic Zone", providers = { { class = "DEATHKNIGHT" } } },

  { category = "Druid", spellID = 1126, name = "Mark of the Wild", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 106839, name = "Skull Bash", providers = { { class = "DRUID", specs = Specs(103, 104) } } },
  { category = "Druid", spellID = 78675, name = "Solar Beam", providers = { { class = "DRUID", specs = Specs(102) } } },
  { category = "Druid", spellID = 339, name = "Entangling Roots", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 102359, name = "Mass Entanglement", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 2637, name = "Hibernate", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 33786, name = "Cyclone", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 132469, name = "Typhoon", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 102793, name = "Ursol's Vortex", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 20484, name = "Rebirth", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 102342, name = "Ironbark", providers = { { class = "DRUID", specs = Specs(105) } } },
  { category = "Druid", spellID = 29166, name = "Innervate", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 77761, name = "Stampeding Roar", providers = { { class = "DRUID" } } },

  { category = "Evoker", spellID = 381748, name = "Blessing of the Bronze", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 395152, name = "Ebon Might", providers = { { class = "EVOKER", specs = Specs(1473) } } },
  { category = "Evoker", spellID = 351338, name = "Quell", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 360806, name = "Sleep Walk", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 358385, name = "Landslide", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 357214, name = "Wing Buffet", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 368970, name = "Tail Swipe", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 357170, name = "Time Dilation", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 370665, name = "Rescue", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 374227, name = "Zephyr", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 363534, name = "Rewind", providers = { { class = "EVOKER", specs = Specs(1468) } } },

  { category = "Mage", spellID = 1459, name = "Arcane Intellect", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 2139, name = "Counterspell", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 118, name = "Polymorph", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 31661, name = "Dragon's Breath", providers = { { class = "MAGE", specs = Specs(63) } } },
  { category = "Mage", spellID = 122, name = "Frost Nova", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 113724, name = "Ring of Frost", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 414660, name = "Mass Barrier", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 80353, name = "Time Warp", providers = { { class = "MAGE" } } },

  { category = "Monk", spellID = 113746, name = "Mystic Touch", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 116705, name = "Spear Hand Strike", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 119381, name = "Leg Sweep", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 115078, name = "Paralysis", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 116844, name = "Ring of Peace", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 116849, name = "Life Cocoon", providers = { { class = "MONK", specs = Specs(270) } } },
  { category = "Monk", spellID = 115310, name = "Revival", providers = { { class = "MONK", specs = Specs(270) } } },
  { category = "Monk", spellID = 116841, name = "Tiger's Lust", providers = { { class = "MONK" } } },

  { category = "Paladin", spellID = 465, name = "Devotion Aura", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 183435, name = "Retribution Aura", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 96231, name = "Rebuke", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 853, name = "Hammer of Justice", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 20066, name = "Repentance", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 115750, name = "Blinding Light", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 6940, name = "Blessing of Sacrifice", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 1022, name = "Blessing of Protection", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 1044, name = "Blessing of Freedom", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 633, name = "Lay on Hands", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 31821, name = "Aura Mastery", providers = { { class = "PALADIN", specs = Specs(65) } } },

  { category = "Hunter", spellID = 264667, name = "Primal Rage", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 147362, name = "Counter Shot", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 187707, name = "Muzzle", providers = { { class = "HUNTER", specs = Specs(255) } } },
  { category = "Hunter", spellID = 187650, name = "Freezing Trap", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 187698, name = "Tar Trap", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 19577, name = "Intimidation", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 109248, name = "Binding Shot", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 34477, name = "Misdirection", providers = { { class = "HUNTER" } } },

  { category = "Priest", spellID = 21562, name = "Power Word: Fortitude", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 15487, name = "Silence", providers = { { class = "PRIEST", specs = Specs(258) } } },
  { category = "Priest", spellID = 8122, name = "Psychic Scream", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 605, name = "Mind Control", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 9484, name = "Shackle Undead", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 64044, name = "Psychic Horror", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 10060, name = "Power Infusion", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 33206, name = "Pain Suppression", providers = { { class = "PRIEST", specs = Specs(256) } } },
  { category = "Priest", spellID = 47788, name = "Guardian Spirit", providers = { { class = "PRIEST", specs = Specs(257) } } },
  { category = "Priest", spellID = 73325, name = "Leap of Faith", providers = { { class = "PRIEST" } } },

  { category = "Rogue", spellID = 1766, name = "Kick", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 6770, name = "Sap", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 2094, name = "Blind", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 1833, name = "Cheap Shot", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 408, name = "Kidney Shot", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 1776, name = "Gouge", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 57934, name = "Tricks of the Trade", providers = { { class = "ROGUE" } } },

  { category = "Shaman", spellID = 2825, name = "Bloodlust", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 32182, name = "Heroism", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 204330, name = "Skyfury", providers = { { class = "SHAMAN", specs = Specs(263) } } },
  { category = "Shaman", spellID = 57994, name = "Wind Shear", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 51514, name = "Hex", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 192058, name = "Capacitor Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 51485, name = "Earthgrab Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 98008, name = "Spirit Link Totem", providers = { { class = "SHAMAN", specs = Specs(264) } } },
  { category = "Shaman", spellID = 207399, name = "Ancestral Protection Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 192077, name = "Wind Rush Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 8143, name = "Tremor Totem", providers = { { class = "SHAMAN" } } },

  { category = "Warlock", spellID = 6201, name = "Healthstone", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 19647, name = "Spell Lock", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 5782, name = "Fear", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 710, name = "Banish", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 30283, name = "Shadowfury", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 6789, name = "Mortal Coil", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 20707, name = "Soulstone", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 111771, name = "Demonic Gateway", providers = { { class = "WARLOCK" } } },

  { category = "Warrior", spellID = 6673, name = "Battle Shout", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 6552, name = "Pummel", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 107570, name = "Storm Bolt", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 46968, name = "Shockwave", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 5246, name = "Intimidating Shout", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 97462, name = "Rallying Cry", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 3411, name = "Intervene", providers = { { class = "WARRIOR" } } },

  { category = "Demon Hunter", spellID = 1490, name = "Chaos Brand", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 183752, name = "Disrupt", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 179057, name = "Chaos Nova", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 217832, name = "Imprison", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 207684, name = "Sigil of Misery", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 202137, name = "Sigil of Silence", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 196718, name = "Darkness", providers = { { class = "DEMONHUNTER" } } },
}

local function GetUnitSpecID(unit)
  if UnitIsUnit(unit, "player") then
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and specIndex > 0 then
      local specID = GetSpecializationInfo(specIndex)
      return tonumber(specID) or 0
    end
  end
  if GetInspectSpecialization and CanInspect and CanInspect(unit) then
    local specID = GetInspectSpecialization(unit)
    return tonumber(specID) or 0
  end
  return 0
end

local function ProviderMatches(member, provider)
  if not member or not provider then
    return false
  end
  if tostring(member.classFile) ~= tostring(provider.class) then
    return false
  end
  if type(provider.specs) ~= "table" then
    return true
  end
  if not member.specID or member.specID <= 0 then
    return false
  end
  for _, sid in ipairs(provider.specs) do
    if member.specID == sid then
      return true
    end
  end
  return false
end

local function BuildRosterMembers()
  local roster = {}
  local units = BuildGroupUnits()
  for _, unit in ipairs(units) do
    if UnitExists(unit) then
      local name = UnitName(unit) or unit
      local className, classFile = UnitClass(unit)
      roster[#roster + 1] = {
        unit = unit,
        name = name,
        className = className or classFile or "",
        classFile = tostring(classFile or ""),
        specID = GetUnitSpecID(unit),
      }
    end
  end
  return roster
end

local function BuildProviderText(providers)
  local out = {}
  for _, p in ipairs(providers or {}) do
    local classLabel = CLASS_LABELS[p.class] or p.class
    if type(p.specs) == "table" and #p.specs > 0 then
      local specNames = {}
      for _, sid in ipairs(p.specs) do
        specNames[#specNames + 1] = SPEC_LABELS[sid] or tostring(sid)
      end
      out[#out + 1] = classLabel .. " (" .. table.concat(specNames, "/") .. ")"
    else
      out[#out + 1] = classLabel
    end
  end
  return table.concat(out, ", ")
end

local function GetUtilityIcon(spellID)
  if C_Spell and C_Spell.GetSpellTexture then
    local tex = C_Spell.GetSpellTexture(spellID)
    if tex then
      return tex
    end
  end
  local _, _, icon = GetSpellInfo(spellID)
  return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local UTILITY_TYPE_ORDER = {
  "Party Buffs",
  "External CDs",
  "Battle Res",
  "Bloodlust/Heroism",
  "Interrupts",
  "Stuns",
  "Slows",
  "Incapacitate",
  "Other",
}

local UTILITY_CRITICAL_TYPES = {
  "Interrupts",
  "Battle Res",
  "Bloodlust/Heroism",
}

local UTILITY_CRITICAL_LOOKUP = {}
for _, typeName in ipairs(UTILITY_CRITICAL_TYPES) do
  UTILITY_CRITICAL_LOOKUP[typeName] = true
end

local UTILITY_TYPE_BY_SPELL = {
  [1126] = "Party Buffs", [381748] = "Party Buffs", [395152] = "Party Buffs",
  [1459] = "Party Buffs", [113746] = "Party Buffs", [465] = "Party Buffs",
  [183435] = "Party Buffs", [21562] = "Party Buffs", [204330] = "Party Buffs",
  [6201] = "Party Buffs", [6673] = "Party Buffs", [1490] = "Party Buffs",

  [33206] = "External CDs", [47788] = "External CDs", [10060] = "External CDs", [73325] = "External CDs",
  [102342] = "External CDs", [29166] = "External CDs", [77761] = "External CDs", [357170] = "External CDs",
  [374227] = "External CDs", [363534] = "External CDs", [116849] = "External CDs", [115310] = "External CDs",
  [116841] = "External CDs", [6940] = "External CDs", [1022] = "External CDs", [1044] = "External CDs",
  [633] = "External CDs", [31821] = "External CDs", [34477] = "External CDs", [57934] = "External CDs",
  [98008] = "External CDs", [207399] = "External CDs", [192077] = "External CDs", [8143] = "External CDs",
  [111771] = "External CDs", [97462] = "External CDs", [3411] = "External CDs", [196718] = "External CDs",
  [51052] = "External CDs", [370665] = "External CDs", [414660] = "External CDs",

  [61999] = "Battle Res", [20484] = "Battle Res", [20707] = "Battle Res",
  [2825] = "Bloodlust/Heroism", [32182] = "Bloodlust/Heroism", [264667] = "Bloodlust/Heroism", [80353] = "Bloodlust/Heroism",

  [47528] = "Interrupts", [106839] = "Interrupts", [78675] = "Interrupts", [351338] = "Interrupts",
  [2139] = "Interrupts", [116705] = "Interrupts", [96231] = "Interrupts", [147362] = "Interrupts",
  [187707] = "Interrupts", [15487] = "Interrupts", [1766] = "Interrupts", [57994] = "Interrupts",
  [19647] = "Interrupts", [6552] = "Interrupts", [183752] = "Interrupts",

  [221562] = "Stuns", [119381] = "Stuns", [853] = "Stuns", [115750] = "Stuns", [19577] = "Stuns",
  [64044] = "Stuns", [1833] = "Stuns", [408] = "Stuns", [192058] = "Stuns", [30283] = "Stuns",
  [107570] = "Stuns", [46968] = "Stuns", [179057] = "Stuns",

  [45524] = "Slows", [187698] = "Slows", [51485] = "Slows", [102793] = "Slows",

  [207167] = "Incapacitate", [339] = "Incapacitate", [102359] = "Incapacitate", [2637] = "Incapacitate",
  [33786] = "Incapacitate", [360806] = "Incapacitate", [358385] = "Incapacitate", [357214] = "Incapacitate",
  [368970] = "Incapacitate", [118] = "Incapacitate", [31661] = "Incapacitate", [122] = "Incapacitate",
  [113724] = "Incapacitate", [115078] = "Incapacitate", [116844] = "Incapacitate", [20066] = "Incapacitate",
  [187650] = "Incapacitate", [8122] = "Incapacitate", [605] = "Incapacitate", [9484] = "Incapacitate",
  [6770] = "Incapacitate", [2094] = "Incapacitate", [1776] = "Incapacitate", [51514] = "Incapacitate",
  [5782] = "Incapacitate", [710] = "Incapacitate", [6789] = "Incapacitate", [5246] = "Incapacitate",
  [217832] = "Incapacitate", [207684] = "Incapacitate", [202137] = "Incapacitate",
}

local function ResolveUtilityType(entry)
  local spellID = tonumber(entry.spellID) or 0
  local t = UTILITY_TYPE_BY_SPELL[spellID]
  if t then
    return t
  end
  return "Other"
end

local function BuildUtilityState()
  local roster = BuildRosterMembers()
  local byType = {}
  local summaryByType = {}

  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    summaryByType[typeName] = {
      typeKey = typeName,
      presentCount = 0,
      totalCount = 0,
    }
  end

  for _, entry in ipairs(UTILITY_ENTRIES) do
    local typeKey = ResolveUtilityType(entry)
    byType[typeKey] = byType[typeKey] or {
      classKey = typeKey,
      entries = {},
    }
    summaryByType[typeKey] = summaryByType[typeKey] or {
      typeKey = typeKey,
      presentCount = 0,
      totalCount = 0,
    }

    local contributors = {}
    for _, m in ipairs(roster) do
      for _, provider in ipairs(entry.providers or {}) do
        if ProviderMatches(m, provider) then
          local specLabel = (m.specID and m.specID > 0 and SPEC_LABELS[m.specID]) and (" - " .. SPEC_LABELS[m.specID]) or ""
          contributors[#contributors + 1] = tostring(m.name) .. " (" .. tostring(m.className) .. specLabel .. ")"
          break
        end
      end
    end

    local present = (#contributors > 0)
    summaryByType[typeKey].totalCount = (summaryByType[typeKey].totalCount or 0) + 1
    if present then
      summaryByType[typeKey].presentCount = (summaryByType[typeKey].presentCount or 0) + 1
    end

    byType[typeKey].entries[#byType[typeKey].entries + 1] = {
      name = entry.name,
      category = entry.category,
      spellID = entry.spellID,
      icon = GetUtilityIcon(entry.spellID),
      providersText = BuildProviderText(entry.providers),
      present = present,
      contributors = contributors,
    }
  end

  for _, group in pairs(byType) do
    table.sort(group.entries, function(a, b)
      if a.present ~= b.present then
        return a.present
      end
      return tostring(a.name or "") < tostring(b.name or "")
    end)
  end

  local groups = {}
  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    if byType[typeName] then
      groups[#groups + 1] = byType[typeName]
      byType[typeName] = nil
    end
  end
  for _, group in pairs(byType) do
    groups[#groups + 1] = group
  end

  local summary = {}
  local seen = {}
  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    summary[#summary + 1] = summaryByType[typeName] or {
      typeKey = typeName,
      presentCount = 0,
      totalCount = 0,
    }
    seen[typeName] = true
  end
  for typeName, item in pairs(summaryByType) do
    if not seen[typeName] then
      summary[#summary + 1] = item
    end
  end

  return {
    groups = groups,
    summary = summary,
    summaryByType = summaryByType,
  }
end

function UI.RefreshUtilityTab()
  if not addon.utilityClassCards or not addon.utilityTab or not addon.utilityTab:IsShown() then
    return
  end

  local state = BuildUtilityState()
  local groups = state.groups or {}
  local summaryByType = state.summaryByType or {}
  local layout = addon.utilityLayout or {}
  local columns = layout.columns or 2
  local gapX = layout.gapX or 6
  local gapY = layout.gapY or 6
  local cardW = layout.cardW or 286
  local iconSize = layout.iconSize or 28
  local iconGap = layout.iconGap or 4
  local iconsPerRow = layout.iconsPerRow or 8
  local cardTop = layout.cardTop or 0

  if addon.utilitySummaryCriticalRows then
    for _, row in ipairs(addon.utilitySummaryCriticalRows) do
      local typeKey = row.typeKey
      local item = summaryByType[typeKey] or { presentCount = 0 }
      local count = tonumber(item.presentCount) or 0
      row:SetText(string.format("%s: %d", tostring(typeKey), count))
      if count > 0 then
        row:SetTextColor(0.95, 0.86, 0.38)
      else
        row:SetTextColor(1.0, 0.55, 0.55)
      end
    end
  end

  if addon.utilitySummaryRows then
    for _, row in ipairs(addon.utilitySummaryRows) do
      local typeKey = row.typeKey
      local item = summaryByType[typeKey] or { presentCount = 0 }
      local count = tonumber(item.presentCount) or 0
      row:SetText(string.format("%s: %d", tostring(typeKey), count))
      if count > 0 then
        row:SetTextColor(0.9, 0.9, 0.9)
      else
        row:SetTextColor(1.0, 0.55, 0.55)
      end
    end
  end

  local colX = {}
  for c = 1, columns do
    colX[c] = (c - 1) * (cardW + gapX)
  end
  local colY = {}
  for c = 1, columns do
    colY[c] = cardTop
  end

  local function PickColumn()
    local best = 1
    for c = 2, columns do
      if colY[c] < colY[best] then
        best = c
      end
    end
    return best
  end

  local maxCards = #addon.utilityClassCards
  for i = 1, maxCards do
    local card = addon.utilityClassCards[i]
    local group = groups[i]
    if not group then
      card:Hide()
    else
      card:Show()
      local s = summaryByType[group.classKey] or {}
      local presentCount = tonumber(s.presentCount) or 0
      local totalCount = tonumber(s.totalCount) or #group.entries
      card.title:SetText(string.format("%s (%d/%d)", tostring(group.classKey), presentCount, totalCount))

      local totalEntries = #group.entries
      local maxIcons = #card.icons
      local visibleCount = math.min(totalEntries, maxIcons)
      local rowsNeeded = math.max(1, math.ceil(visibleCount / iconsPerRow))
      local cardH = 36 + (rowsNeeded * (iconSize + iconGap)) + 10

      local col = PickColumn()
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", card:GetParent(), "TOPLEFT", colX[col], -colY[col])
      card:SetHeight(cardH)
      colY[col] = colY[col] + cardH + gapY

      for idx = 1, maxIcons do
        local iconButton = card.icons[idx]
        local entry = group.entries[idx]
        if entry then
          iconButton:Show()
          iconButton.icon:SetTexture(entry.icon)
          iconButton.icon:SetDesaturated(not entry.present)
          iconButton.icon:SetVertexColor(1, 1, 1, entry.present and 1 or 0.30)
          iconButton.entry = entry
        else
          iconButton.entry = nil
          iconButton:Hide()
        end
      end
    end
  end
end

function UI.RefreshMythicTab()
  if addon.mythicSummary then
    addon.mythicSummary:SetText(GetMythicSummary())
  end

  if addon.notesListText then
    local keys = NotesStore.Keys()
    addon.notesListText:SetText((#keys > 0) and table.concat(keys, "\n") or "No notes yet")
  end
end
local function BuildMythicTab(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()

  local contentPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  contentPanel:SetPoint("TOPLEFT", tab, "TOPLEFT", 14, -54)
  contentPanel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -14, 14)
  util.ApplyUIFrame(contentPanel, "surface", 1)

  local summaryTitle = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryTitle:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 12, -14)
  summaryTitle:SetText("Current Context")
  summaryTitle:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])

  local summary = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summary:SetPoint("TOPLEFT", summaryTitle, "BOTTOMLEFT", 0, -8)
  summary:SetWidth(840)
  summary:SetJustifyH("LEFT")
  summary:SetJustifyV("TOP")
  summary:SetText("")
  addon.mythicSummary = summary

  local noteTitle = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  noteTitle:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 12, -130)
  noteTitle:SetText("Per-player Notes")
  noteTitle:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])

  local playerKeyBox = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
  playerKeyBox:SetSize(260, 22)
  util.SkinUIEditBox(playerKeyBox)
  playerKeyBox:SetPoint("TOPLEFT", noteTitle, "BOTTOMLEFT", 0, -8)
  playerKeyBox:SetAutoFocus(false)
  playerKeyBox:SetText("")

  local noteBox = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
  noteBox:SetSize(580, 22)
  util.SkinUIEditBox(noteBox)
  noteBox:SetPoint("TOPLEFT", playerKeyBox, "BOTTOMLEFT", 0, -8)
  noteBox:SetAutoFocus(false)
  noteBox:SetText("")

  local loadBtn = CreateFrame("Button", nil, tab, "BackdropTemplate")
  loadBtn:SetSize(52, 20)
  loadBtn:SetPoint("LEFT", playerKeyBox, "RIGHT", 8, 0)
  loadBtn:SetText("Load")
  util.SkinUIButton(loadBtn, "elevated")
  loadBtn:SetScript("OnClick", function()
    local key = priv.data.NormalizePlayerKey(playerKeyBox:GetText())
    local note = NotesStore.Get(key) or ""
    noteBox:SetText(note)
  end)

  local saveBtn = CreateFrame("Button", nil, tab, "BackdropTemplate")
  saveBtn:SetSize(52, 20)
  saveBtn:SetPoint("LEFT", loadBtn, "RIGHT", 6, 0)
  saveBtn:SetText("Save")
  util.SkinUIButton(saveBtn, "elevated")
  saveBtn:SetScript("OnClick", function()
    local key = priv.data.NormalizePlayerKey(playerKeyBox:GetText())
    if key == "" then
      Print("Enter player-realm key first.")
      return
    end
    NotesStore.Set(key, noteBox:GetText())
    Print("Saved note for " .. key)
    UI.RefreshApplicants()
    UI.RefreshMythicTab()
  end)

  local delBtn = CreateFrame("Button", nil, tab, "BackdropTemplate")
  delBtn:SetSize(60, 20)
  delBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
  delBtn:SetText("Delete")
  util.SkinUIButton(delBtn, "elevated")
  delBtn:SetScript("OnClick", function()
    local key = priv.data.NormalizePlayerKey(playerKeyBox:GetText())
    if key == "" then
      return
    end
    NotesStore.Set(key, "")
    noteBox:SetText("")
    Print("Deleted note for " .. key)
    UI.RefreshApplicants()
    UI.RefreshMythicTab()
  end)

  local notesLabel = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  notesLabel:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", 0, -12)
  notesLabel:SetText("Saved players")

  local notesList = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  notesList:SetPoint("TOPLEFT", notesLabel, "BOTTOMLEFT", 0, -6)
  notesList:SetWidth(840)
  notesList:SetJustifyH("LEFT")
  notesList:SetText("")
  addon.notesListText = notesList

  addon.mythicTab = tab
end

local function BuildUtilityTab(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()

  local contentPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  contentPanel:SetPoint("TOPLEFT", tab, "TOPLEFT", 14, -54)
  contentPanel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -14, 14)
  util.ApplyUIFrame(contentPanel, "surface", 1)

  local title = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 12, -14)
  title:SetText("Party Utility")
  title:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])

  local subtitle = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetText("Left: coverage summary. Right: grouped utility icons. Dark icon = missing.")
  subtitle:SetTextColor(0.86, 0.86, 0.86)

  local split = CreateFrame("Frame", nil, contentPanel)
  split:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
  split:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -8, 8)

  local summaryWidth = 248
  local splitGap = 8

  local summaryPanel = CreateFrame("Frame", nil, split, "BackdropTemplate")
  summaryPanel:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
  summaryPanel:SetPoint("BOTTOMLEFT", split, "BOTTOMLEFT", 0, 0)
  summaryPanel:SetWidth(summaryWidth)
  util.ApplyUIFrame(summaryPanel, "elevated", 1)

  local iconsGrid = CreateFrame("Frame", nil, split)
  iconsGrid:SetPoint("TOPLEFT", summaryPanel, "TOPRIGHT", splitGap, 0)
  iconsGrid:SetPoint("BOTTOMRIGHT", split, "BOTTOMRIGHT", 0, 0)

  local summaryTitle = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryTitle:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", 10, -10)
  summaryTitle:SetText("Coverage Summary")
  summaryTitle:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])

  local criticalTitle = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  criticalTitle:SetPoint("TOPLEFT", summaryTitle, "BOTTOMLEFT", 0, -12)
  criticalTitle:SetText("Critical Utility")
  criticalTitle:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])

  addon.utilitySummaryCriticalRows = {}
  local previous = criticalTitle
  for _, typeName in ipairs(UTILITY_CRITICAL_TYPES) do
    local line = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
    line:SetWidth(summaryWidth - 20)
    line:SetJustifyH("LEFT")
    line:SetText(typeName .. ": 0")
    line.typeKey = typeName
    addon.utilitySummaryCriticalRows[#addon.utilitySummaryCriticalRows + 1] = line
    previous = line
  end

  local otherTitle = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  otherTitle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -14)
  otherTitle:SetText("Other Coverage")
  otherTitle:SetTextColor(0.9, 0.9, 0.9)

  addon.utilitySummaryRows = {}
  previous = otherTitle
  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    if not UTILITY_CRITICAL_LOOKUP[typeName] then
      local line = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
      line:SetWidth(summaryWidth - 20)
      line:SetJustifyH("LEFT")
      line:SetText(typeName .. ": 0")
      line.typeKey = typeName
      addon.utilitySummaryRows[#addon.utilitySummaryRows + 1] = line
      previous = line
    end
  end

  local columns = 2
  local rows = 5
  local cardW = 286
  local cardH = 110
  local gapX = 6
  local gapY = 6
  local iconsPerRow = 8
  local iconSize = 28
  local iconGap = 4

  addon.utilityLayout = {
    columns = columns,
    cardW = cardW,
    gapX = gapX,
    gapY = gapY,
    iconsPerRow = iconsPerRow,
    iconSize = iconSize,
    iconGap = iconGap,
    cardTop = 0,
  }

  addon.utilityClassCards = {}
  for rowIndex = 1, rows do
    for colIndex = 1, columns do
      local idx = ((rowIndex - 1) * columns) + colIndex
      local card = CreateFrame("Frame", nil, iconsGrid, "BackdropTemplate")
      card:SetSize(cardW, cardH)
      card:SetPoint("TOPLEFT", iconsGrid, "TOPLEFT", (colIndex - 1) * (cardW + gapX), -((rowIndex - 1) * (cardH + gapY)))
      util.ApplyUIFrame(card, "elevated", 1)

      card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
      card.title:SetTextColor(UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3])
      card.title:SetJustifyH("LEFT")
      card.title:SetText("")

      card.icons = {}
      local iconStartX = 8
      local iconStartY = -34
      local iconRows = 6
      for ir = 1, iconRows do
        for ic = 1, iconsPerRow do
          local iconIndex = ((ir - 1) * iconsPerRow) + ic
          local btn = CreateFrame("Button", nil, card)
          btn:SetSize(iconSize, iconSize)
          btn:SetPoint("TOPLEFT", card, "TOPLEFT", iconStartX + ((ic - 1) * (iconSize + iconGap)), iconStartY - ((ir - 1) * (iconSize + iconGap)))

          btn.icon = btn:CreateTexture(nil, "ARTWORK")
          btn.icon:SetAllPoints()
          btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

          btn:SetScript("OnEnter", function(self)
            if not self.entry then
              return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry.name)
            GameTooltip:AddLine("Class: " .. tostring(self.entry.category or "Other"), 0.85, 0.85, 0.85)
            GameTooltip:AddLine("Class/Spec: " .. tostring(self.entry.providersText or "-"), 1, 1, 1, true)
            if self.entry.present then
              GameTooltip:AddLine("Present: " .. table.concat(self.entry.contributors or {}, ", "), 0.4, 0.95, 0.4, true)
            else
              GameTooltip:AddLine("Missing in current group", 1, 0.35, 0.35)
            end
            GameTooltip:Show()
          end)
          btn:SetScript("OnLeave", function(self)
            GameTooltip_Hide()
          end)

          card.icons[iconIndex] = btn
        end
      end

      addon.utilityClassCards[idx] = card
    end
  end

  addon.utilityTab = tab
end

priv.ui2.BuildMythicTab = BuildMythicTab
priv.ui2.BuildUtilityTab = BuildUtilityTab
