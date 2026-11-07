-- StartAttack Macros
-- Blizzard erlaubt Addons nicht, StartAttack() selbst aufzurufen (geschützte Funktion).
-- Deshalb erzeugt dieses Addon Makros der Form:
--   #showtooltip Zauber
--   /startattack
--   /cast Zauber
-- und kann sie per Klick auf den Cursor legen oder direkt in die Leisten setzen.

local ADDON_NAME, ns = ...
local L = ns.L
local TITLE = "|cffff8c1aStartAttack|r Macros"
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "?"
if VERSION:find("^@") then VERSION = "dev" end
local ADDON_ICON = "Interface\\Icons\\Ability_DualWield"
local PREFIX = "+"          -- Makronamen: "+Finsterer Stoß" (max. 16 Zeichen)
local MAX_NAME = 16
local MACRO_ICON = "INV_MISC_QUESTIONMARK" -- #showtooltip zeigt automatisch das Zaubersymbol

-- Fähigkeiten, die selbst schon Autoangriff/Fernkampf sind
local SKIP = { [6603] = true, [75] = true, [5019] = true, [3018] = true }

local COMMANDS = {
    { "/sam", L.CMD_OPEN },
    { "/sam convert", L.CMD_CONVERT },
    { "/sam " .. L.CMD_SPELL, L.CMD_SPELL_DESC },
    { "/sam options", L.CMD_OPTIONS },
    { "/sam minimap", L.CMD_MINIMAP },
}

local DEFAULTS = { minimap = { hide = false, angle = 215 } }
local db

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8c1aStartAttack|r: " .. msg)
end

------------------------------------------------------------------------
-- API-Kompatibilität (alter Classic-Client vs. moderner Client)
------------------------------------------------------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture(id)
end

local function IsHarmful(id, name)
    if C_Spell and C_Spell.IsSpellHarmful then
        return C_Spell.IsSpellHarmful(id)
    end
    if IsHarmfulSpell then
        return IsHarmfulSpell(name) and true or false
    end
    return false
end

-- Liefert alle aktiven (nicht passiven) Zauber im Zauberbuch, Ränge zusammengefasst
local function GetSpellBookSpells()
    local list, seen = {}, {}
    local function add(id, name, icon)
        if not id or not name or SKIP[id] or seen[name] then return end
        seen[name] = true
        list[#list + 1] = {
            id = id, name = name, icon = icon or SpellIcon(id),
            harmful = IsHarmful(id, name),
        }
    end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum.SpellBookSpellBank.Player
        for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(tab)
            if info and not info.offSpecID then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.itemType == Enum.SpellBookItemType.Spell
                        and not item.isPassive and not item.isOffSpec then
                        add(item.spellID or item.actionID, item.name, item.iconID)
                    end
                end
            end
        end
    else
        local book = BOOKTYPE_SPELL or "spell"
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(i, book)
                if kind == "SPELL" and not IsPassiveSpell(i, book) then
                    add(id, SpellName(id) or GetSpellBookItemName(i, book))
                end
            end
        end
    end

    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

------------------------------------------------------------------------
-- Makros
------------------------------------------------------------------------
local function MacroName(spell)
    return (PREFIX .. spell):sub(1, MAX_NAME)
end

local function MacroBody(spell)
    return "#showtooltip " .. spell .. "\n/startattack\n/cast " .. spell
end

local function HasMacro(spell)
    local idx = GetMacroIndexByName(MacroName(spell))
    return idx and idx > 0
end

-- Erstellt oder aktualisiert das Makro. Gibt den Makronamen zurück (Index ändert sich beim Sortieren!)
local function EnsureMacro(spell)
    if InCombatLockdown() then
        Print(L.MSG_COMBAT_MACRO)
        return nil
    end
    local name, body = MacroName(spell), MacroBody(spell)
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        EditMacro(idx, name, MACRO_ICON, body)
        return name
    end

    local numGlobal, numChar = GetNumMacros()
    local maxGlobal = MAX_ACCOUNT_MACROS or 120
    local maxChar = MAX_CHARACTER_MACROS or 18
    local perChar
    if numChar < maxChar then
        perChar = true            -- bevorzugt charakterspezifisch
    elseif numGlobal < maxGlobal then
        perChar = false
    else
        Print(L.MSG_SLOTS_FULL)
        return nil
    end
    CreateMacro(name, MACRO_ICON, body, perChar)
    return name
end

local function PickupSpellMacro(spell)
    local name = EnsureMacro(spell)
    if not name then return end
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        ClearCursor()
        PickupMacro(idx)
    end
end

------------------------------------------------------------------------
-- Aktionsleisten automatisch umwandeln
------------------------------------------------------------------------
local function ConvertActionBars(includeAll)
    if InCombatLockdown() then
        Print(L.MSG_COMBAT)
        return
    end
    -- 1) Welche Slots enthalten Angriffszauber?
    local todo = {}
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id and not SKIP[id] then
            local name = SpellName(id)
            if name and (includeAll or IsHarmful(id, name)) then
                todo[#todo + 1] = { slot = slot, spell = name }
            end
        end
    end
    if #todo == 0 then
        Print(L.MSG_NOTHING_FOUND)
        return
    end

    -- 2) Makros anlegen (erst alle, weil sich Indizes beim Anlegen verschieben)
    local made = {}
    for _, t in ipairs(todo) do
        if made[t.spell] == nil then
            made[t.spell] = EnsureMacro(t.spell) or false
        end
    end

    -- 3) Makros in die Slots setzen
    local count = 0
    for _, t in ipairs(todo) do
        local name = made[t.spell]
        local idx = name and GetMacroIndexByName(name)
        if idx and idx > 0 then
            ClearCursor()
            PickupMacro(idx)
            PlaceAction(t.slot)
            ClearCursor()   -- der alte Zauber landet auf dem Cursor -> verwerfen
            count = count + 1
        end
    end
    Print(L.MSG_CONVERTED:format(count))
end

------------------------------------------------------------------------
-- Hauptfenster
------------------------------------------------------------------------
local frame, scrollChild, buttons, showAll = nil, nil, {}, false
local COLS, SIZE, GAP = 8, 38, 8

local function UpdateFooter()
    if not frame then return end
    local numGlobal, numChar = GetNumMacros()
    frame.footer:SetFormattedText(L.MACRO_SLOTS,
        numChar, MAX_CHARACTER_MACROS or 18, numGlobal, MAX_ACCOUNT_MACROS or 120)
end

local function CreateSpellButton(i)
    local b = CreateFrame("Button", nil, scrollChild)
    b:SetSize(SIZE, SIZE)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- Rand des Icons abschneiden

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.border:SetPoint("TOPLEFT", -SIZE * 0.32, SIZE * 0.32)
    b.border:SetPoint("BOTTOMRIGHT", SIZE * 0.32, -SIZE * 0.32)

    b.check = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.check:SetSize(14, 14)
    b.check:SetPoint("BOTTOMRIGHT", 3, -3)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")

    local function grab(self)
        PickupSpellMacro(self.spell)
        self.check:Show()
        UpdateFooter()
    end
    b:SetScript("OnClick", grab)
    b:SetScript("OnDragStart", grab)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine(" ")
        if self.check:IsShown() then
            GameTooltip:AddLine(L.TT_HAS_MACRO, 0.25, 1, 0.25)
        end
        GameTooltip:AddLine(L.TT_GRAB, 1, 0.55, 0.1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Refresh()
    if not frame then return end
    local shown = {}
    for _, s in ipairs(GetSpellBookSpells()) do
        if showAll or s.harmful then shown[#shown + 1] = s end
    end

    for i, s in ipairs(shown) do
        local b = buttons[i] or CreateSpellButton(i)
        buttons[i] = b
        b.spell, b.spellID = s.name, s.id
        b.icon:SetTexture(s.icon)
        b.check:SetShown(HasMacro(s.name))
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6 + col * (SIZE + GAP), -6 - row * (SIZE + GAP))
        b:Show()
    end
    for i = #shown + 1, #buttons do buttons[i]:Hide() end
    scrollChild:SetHeight(math.max(1, math.ceil(#shown / COLS) * (SIZE + GAP) + 6))
    frame.empty:SetShown(#shown == 0)
    UpdateFooter()
end

local function CreateMainFrame()
    frame = CreateFrame("Frame", "StartAttackMacrosFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(COLS * (SIZE + GAP) + 54, 460)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:Hide()
    tinsert(UISpecialFrames, "StartAttackMacrosFrame") -- ESC schließt

    -- Titelleiste mit Addon-Icon
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetTexture(ADDON_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 9, -5)
    frame.title:SetText(TITLE)
    icon:SetPoint("RIGHT", frame.title, "LEFT", -4, 0)

    -- Kopfbereich
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 16, -34)
    header:SetText(L.WINDOW_HEADER)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    hint:SetText(L.WINDOW_HINT)

    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.12)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 12, -66)
    sep:SetPoint("TOPRIGHT", -12, -66)

    -- Zauberliste
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -72)
    scroll:SetPoint("BOTTOMRIGHT", -32, 96)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(COLS * (SIZE + GAP) + 6, 1)
    scroll:SetScrollChild(scrollChild)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("CENTER", scroll, "CENTER")
    frame.empty:SetText(L.EMPTY)

    local sep2 = frame:CreateTexture(nil, "ARTWORK")
    sep2:SetColorTexture(1, 1, 1, 0.12)
    sep2:SetHeight(1)
    sep2:SetPoint("BOTTOMLEFT", 12, 90)
    sep2:SetPoint("BOTTOMRIGHT", -12, 90)

    -- Unterer Bereich
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetPoint("BOTTOMLEFT", 12, 62)
    check:SetSize(24, 24)
    local checkText = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkText:SetPoint("LEFT", check, "RIGHT", 2, 1)
    checkText:SetText(L.SHOW_ALL)
    check:SetScript("OnClick", function(self)
        showAll = self:GetChecked() and true or false
        Refresh()
    end)

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 16, 44)

    local convert = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    convert:SetPoint("BOTTOMLEFT", 12, 12)
    convert:SetPoint("BOTTOMRIGHT", -12, 12)
    convert:SetHeight(26)
    convert:SetText(L.CONVERT_BUTTON)
    convert:SetScript("OnClick", function() ConvertActionBars(false); Refresh() end)
    convert:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.CONVERT_TT_TITLE)
        GameTooltip:AddLine(L.CONVERT_TT_TEXT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    convert:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
        Refresh()
    end)
    frame:SetScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
    end)
end

local function ShowWindow()
    if not frame then CreateMainFrame() end
    frame:Show()
    frame:Raise()
end

local function Toggle()
    if frame and frame:IsShown() then frame:Hide() else ShowWindow() end
end

------------------------------------------------------------------------
-- Minimap-Button (ohne Libraries)
------------------------------------------------------------------------
local minimapButton

local function UpdateMinimapPosition()
    local angle = math.rad(db.minimap.angle)
    local radius = (Minimap:GetWidth() / 2) + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local OpenOptions -- wird weiter unten definiert

local function CreateMinimapButton()
    local b = CreateFrame("Button", "StartAttackMacrosMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ADDON_ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnMouseDown", function() icon:SetTexCoord(0, 1, 0, 1) end)
    b:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then OpenOptions() else Toggle() end
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local atan2 = math.atan2 or math.atan
            db.minimap.angle = math.deg(atan2(py - my, px - mx))
            UpdateMinimapPosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(TITLE)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("|cffffffff" .. L.MM_LEFT .. "|r", L.MM_OPEN, nil, nil, nil, 1, 0.82, 0)
        GameTooltip:AddDoubleLine("|cffffffff" .. L.MM_RIGHT .. "|r", L.MM_OPTIONS, nil, nil, nil, 1, 0.82, 0)
        GameTooltip:AddDoubleLine("|cffffffff" .. L.MM_DRAG .. "|r", L.MM_MOVE, nil, nil, nil, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    minimapButton = b
    UpdateMinimapPosition()
    b:SetShown(not db.minimap.hide)
end

------------------------------------------------------------------------
-- Eintrag im Optionsmenü (Esc > Optionen > AddOns)
------------------------------------------------------------------------
local optionsCategory, optionsPanel

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "StartAttack Macros"

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 16, -16)
    logo:SetTexture(ADDON_ICON)
    logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
    title:SetText(TITLE)

    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    version:SetText(L.OPT_VERSION:format(VERSION))

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
    desc:SetWidth(580)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(3)
    desc:SetText(L.OPT_DESC)

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    open:SetSize(220, 26)
    open:SetText(L.OPT_OPEN)
    open:SetScript("OnClick", ShowWindow)

    local convert = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    convert:SetPoint("LEFT", open, "RIGHT", 10, 0)
    convert:SetSize(260, 26)
    convert:SetText(L.OPT_CONVERT)
    convert:SetScript("OnClick", function() ConvertActionBars(false) end)

    local mm = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    mm:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -4, -16)
    local mmText = mm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mmText:SetPoint("LEFT", mm, "RIGHT", 4, 1)
    mmText:SetText(L.OPT_MINIMAP)
    mm:SetScript("OnClick", function(self)
        db.minimap.hide = not self:GetChecked()
        if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
    end)

    local cmdHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cmdHeader:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 4, -20)
    cmdHeader:SetText(L.OPT_COMMANDS)

    local cmds = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cmds:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -6)
    cmds:SetJustifyH("LEFT")
    cmds:SetSpacing(4)
    local lines = {}
    for _, c in ipairs(COMMANDS) do lines[#lines + 1] = "|cffff8c1a" .. c[1] .. "|r  –  " .. c[2] end
    cmds:SetText(table.concat(lines, "\n"))

    panel:SetScript("OnShow", function() mm:SetChecked(not db.minimap.hide) end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(optionsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    optionsPanel = panel
end

OpenOptions = function()
    if optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel) -- alter Blizzard-Bug: zweimal nötig
    end
end

------------------------------------------------------------------------
-- Addon-Kompartiment (Addon-Menü an der Minimap, falls vom Client unterstützt)
------------------------------------------------------------------------
function StartAttackMacros_OnCompartmentClick(_, button)
    if button == "RightButton" then OpenOptions() else Toggle() end
end

function StartAttackMacros_OnCompartmentEnter(_, anchor)
    GameTooltip:SetOwner(type(anchor) == "table" and anchor or UIParent, "ANCHOR_LEFT")
    GameTooltip:AddLine(TITLE)
    GameTooltip:AddLine(L.COMPARTMENT_HINT, 1, 1, 1)
    GameTooltip:Show()
end

function StartAttackMacros_OnCompartmentLeave()
    GameTooltip:Hide()
end

------------------------------------------------------------------------
-- Slash-Befehle
------------------------------------------------------------------------
SLASH_STARTATTACKMACROS1 = "/sam"
SLASH_STARTATTACKMACROS2 = "/startattackmacros"
SlashCmdList.STARTATTACKMACROS = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    local cmd = raw:lower()
    if cmd == "" then
        Toggle()
    elseif cmd == "convert" or cmd == "umwandeln" then
        ConvertActionBars(false)
    elseif cmd == "options" or cmd == "optionen" or cmd == "config" then
        OpenOptions()
    elseif cmd == "minimap" then
        db.minimap.hide = not db.minimap.hide
        minimapButton:SetShown(not db.minimap.hide)
        Print(db.minimap.hide and L.MSG_MINIMAP_HIDDEN or L.MSG_MINIMAP_SHOWN)
    elseif cmd == "help" or cmd == "hilfe" then
        for _, c in ipairs(COMMANDS) do Print("|cffff8c1a" .. c[1] .. "|r – " .. c[2]) end
    else
        PickupSpellMacro(raw)
    end
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UPDATE_MACROS")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        StartAttackMacrosDB = StartAttackMacrosDB or {}
        db = StartAttackMacrosDB
        db.minimap = db.minimap or {}
        for k, v in pairs(DEFAULTS.minimap) do
            if db.minimap[k] == nil then db.minimap[k] = v end
        end
        CreateMinimapButton()
        CreateOptionsPanel()
        self:UnregisterEvent("ADDON_LOADED")
    elseif frame and frame:IsShown() then
        Refresh()
    end
end)
