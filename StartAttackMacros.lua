-- StartAttack Macros
-- Blizzard erlaubt Addons nicht, StartAttack() selbst aufzurufen (geschützte Funktion).
-- Deshalb erzeugt dieses Addon Makros der Form:
--   #showtooltip Zauber
--   /startattack
--   /cast Zauber
-- (optional mit eigenen Bedingungen hinter /startattack und /cast,
--  z. B. [harm,nodead] bzw. [@mouseover,harm,nodead][], und mit eigenen
--  Zeilen zwischen #showtooltip und /startattack, z. B. /petattack)
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
local MAX_BODY = 255        -- maximale Makrolänge
local COND_EXAMPLE = "[@mouseover,harm,nodead][]"
local ATK_EXAMPLE = "[harm,nodead]"
local PRE_EXAMPLE = "/petattack"
local BROKER_NAME = "StartAttack Macros"

-- Fähigkeiten, die selbst schon Autoangriff/Fernkampf sind
local SKIP = { [6603] = true, [75] = true, [5019] = true, [3018] = true }

local COMMANDS = {
    { "/sam", L.CMD_OPEN },
    { "/sam convert", L.CMD_CONVERT },
    { "/sam " .. L.CMD_SPELL, L.CMD_SPELL_DESC },
    { "/sam options", L.CMD_OPTIONS },
    { "/sam minimap", L.CMD_MINIMAP },
}

local DEFAULTS = {
    minimap = { hide = false, angle = 215 },
    conditions = "",              -- Text, der hinter /cast eingefügt wird
    useConditions = true,         -- Haken im Fenster: Text in neue Makros einfügen?
    attackConditions = "",        -- dasselbe für die Zeile /startattack
    useAttackConditions = true,
}
-- Pro Charakter gespeichert: /petattack & Co. passen nur zu bestimmten Klassen
local CHAR_DEFAULTS = {
    extraLines = "",              -- Zeilen zwischen #showtooltip und /startattack
    useExtraLines = true,
}
local db, cdb

local function Store(key)
    return CHAR_DEFAULTS[key] ~= nil and cdb or db
end

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

local function CleanConditions(text)
    return ((text or ""):gsub("%s+", " "):match("^ ?(.-) ?$"))
end

-- Eigene Makrozeilen: je Zeile getrimmt, Leerzeilen entfernt
local function CleanLines(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then out[#out + 1] = trimmed end
    end
    return table.concat(out, "\n")
end

-- cond = Text hinter /cast, atk = Text hinter /startattack,
-- extra = eigene Zeilen vor /startattack ("" = nichts)
local function BuildBody(spell, cond, atk, extra)
    return "#showtooltip " .. spell
        .. (extra ~= "" and "\n" .. extra or "")
        .. "\n/startattack" .. (atk ~= "" and " " .. atk or "")
        .. "\n/cast " .. (cond ~= "" and cond .. " " or "") .. spell
end

-- Zerlegt ein vom Addon erzeugtes Makro wieder in Zauber, die beiden Texte und die Zusatzzeilen:
-- erste Zeile #showtooltip, letzte Zeile /cast, davor /startattack, alles dazwischen sind Zusatzzeilen
-- (tolerant gegenüber Handarbeit: Leerzeichen am Ende, fehlendes Leerzeichen vor dem Zauber)
local function ParseBody(body)
    local lines = {}
    for line in (body:gsub("%s+$", "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    local n = #lines
    if n < 3 then return end
    local spell = lines[1]:match("^#showtooltip (.+)$")
    local atk = lines[n - 1]:match("^/startattack(.*)$")
    local cast = lines[n]:match("^/cast (.+)$")
    if not spell or not atk or not cast or cast:sub(-#spell) ~= spell then return end
    local cond = cast:sub(1, -#spell - 1)
    if cond ~= "" and not cond:find("[%s%]]$") then return end
    if atk ~= "" and atk:sub(1, 1) ~= " " then return end
    return spell, CleanConditions(atk), CleanConditions(cond), CleanLines(table.concat(lines, "\n", 2, n - 2))
end

-- Ohne "cond"/"atk"/"extra" gilt die aktuelle Einstellung (Text + Haken im Fenster).
-- Zweiter Rückgabewert: true, wenn die Texte wegen der Längengrenze weggelassen wurden.
local function ComputeBody(spell, cond, atk, extra)
    cond = cond or (db.useConditions and db.conditions) or ""
    atk = atk or (db.useAttackConditions and db.attackConditions) or ""
    extra = extra or (cdb.useExtraLines and cdb.extraLines) or ""
    local body = BuildBody(spell, cond, atk, extra)
    if #body > MAX_BODY then return BuildBody(spell, "", "", ""), true end
    return body, false
end

local function MacroBody(spell, cond, atk, extra)
    local body, tooLong = ComputeBody(spell, cond, atk, extra)
    if tooLong then Print(L.MSG_TOO_LONG:format(spell)) end
    return body
end

-- nil = kein Makro, "current" = entspricht den aktuellen Einstellungen,
-- "outdated" = Makro vorhanden, ein Klick würde es aber ändern
local function MacroState(spell)
    local idx = GetMacroIndexByName(MacroName(spell))
    if not idx or idx == 0 then return nil end
    local body = (GetMacroBody(idx) or ""):gsub("%s+$", "")
    return body == ComputeBody(spell) and "current" or "outdated"
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

-- Ruft fn(idx, body, spell, atk, cond, extra) für jedes vom Addon erzeugte Makro auf
local function ForEachAddonMacro(fn)
    local function visit(idx)
        local name = GetMacroInfo(idx)
        local body = name and name:sub(1, #PREFIX) == PREFIX and GetMacroBody(idx)
        if not body then return end
        local spell, atk, cond, extra = ParseBody(body)
        if spell and MacroName(spell) == name then fn(idx, body, spell, atk, cond, extra) end
    end
    local numGlobal, numChar = GetNumMacros()
    local firstChar = (MAX_ACCOUNT_MACROS or 120) + 1
    for i = 1, numGlobal do visit(i) end
    for i = firstChar, firstChar + numChar - 1 do visit(i) end
end

-- Nach einer Textänderung: Makros, die den alten Text enthalten, bekommen den neuen.
-- Makros ohne den Text (oder von Hand geänderte) bleiben unberührt.
-- key = "conditions" (hinter /cast), "attackConditions" (hinter /startattack)
-- oder "extraLines" (Zeilen vor /startattack)
local pending = {}

local function UpdateExistingMacros(key, old)
    local new = Store(key)[key]
    if old == "" or old == new then return end
    if InCombatLockdown() then
        pending[key] = pending[key] or old
        Print(L.MSG_COND_COMBAT)
        return
    end
    local count = 0
    ForEachAddonMacro(function(idx, _, spell, atk, cond, extra)
        if key == "conditions" and cond == old then
            cond = new
        elseif key == "attackConditions" and atk == old then
            atk = new
        elseif key == "extraLines" and extra == old then
            extra = new
        else
            return
        end
        EditMacro(idx, nil, nil, MacroBody(spell, cond, atk, extra))
        count = count + 1
    end)
    if count > 0 then Print(L.MSG_COND_UPDATED:format(count)) end
end

-- Bringt alle Addon-Makros auf den Stand der aktuellen Einstellungen (Texte + Haken).
-- Gibt zurück, wie viele sich geändert haben.
local function RefreshAllMacros()
    local count = 0
    ForEachAddonMacro(function(idx, body, spell)
        local new, tooLong = ComputeBody(spell)
        if new ~= body then
            if tooLong then Print(L.MSG_TOO_LONG:format(spell)) end
            EditMacro(idx, nil, nil, new)
            count = count + 1
        end
    end)
    return count
end

local function SetConditions(key, text)
    local store = Store(key)
    local old = store[key]
    store[key] = (key == "extraLines" and CleanLines or CleanConditions)(text)
    UpdateExistingMacros(key, old)
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
    -- 0) Vorhandene Makros an die aktuellen Texte/Haken anpassen
    --    (liegen schon als Makro in der Leiste und würden sonst übersprungen)
    local updated = RefreshAllMacros()

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
        Print(updated > 0 and L.MSG_COND_UPDATED:format(updated) or L.MSG_NOTHING_FOUND)
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
    if updated > 0 then Print(L.MSG_COND_UPDATED:format(updated)) end
end

------------------------------------------------------------------------
-- Hauptfenster
------------------------------------------------------------------------
local frame, scrollChild, buttons, showAll = nil, nil, {}, false
local COLS, SIZE, GAP = 8, 38, 8
local EXTRA_H = 44          -- Höhe des mehrzeiligen Felds für eigene Makrozeilen
local fieldBoxes = {}

-- Übernimmt ein Textfeld, in dem gerade noch getippt wird (löst OnEditFocusLost aus)
local function CommitFields()
    for _, box in ipairs(fieldBoxes) do
        if box:HasFocus() then box:ClearFocus() end
    end
end

local function UpdateFooter()
    if not frame then return end
    local numGlobal, numChar = GetNumMacros()
    frame.footer:SetFormattedText(L.MACRO_SLOTS,
        numChar, MAX_CHARACTER_MACROS or 18, numGlobal, MAX_ACCOUNT_MACROS or 120)
end

-- Grüner Haken = Makro aktuell, gelbes Fragezeichen = Makro vorhanden, aber nicht aktuell
local CHECK_TEXTURE = {
    current = "Interface\\RaidFrame\\ReadyCheck-Ready",
    outdated = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local function UpdateCheck(b)
    local state = MacroState(b.spell)
    b.state = state
    b.check:SetTexture(CHECK_TEXTURE[state or "current"])
    b.check:SetShown(state ~= nil)
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
        CommitFields()
        PickupSpellMacro(self.spell)
        UpdateCheck(self)
        UpdateFooter()
    end
    b:SetScript("OnClick", grab)
    b:SetScript("OnDragStart", grab)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine(" ")
        if self.state == "current" then
            GameTooltip:AddLine(L.TT_HAS_MACRO, 0.25, 1, 0.25)
        elseif self.state == "outdated" then
            GameTooltip:AddLine(L.TT_OUTDATED, 1, 0.82, 0)
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
        UpdateCheck(b)
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
    frame:SetSize(COLS * (SIZE + GAP) + 54, 564)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnMouseDown", CommitFields)   -- Klick ins Fenster übernimmt die Textfelder
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
    scroll:SetPoint("BOTTOMRIGHT", -32, 200)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(COLS * (SIZE + GAP) + 6, 1)
    scroll:SetScrollChild(scrollChild)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("CENTER", scroll, "CENTER")
    frame.empty:SetText(L.EMPTY)

    local sep2 = frame:CreateTexture(nil, "ARTWORK")
    sep2:SetColorTexture(1, 1, 1, 0.12)
    sep2:SetHeight(1)
    sep2:SetPoint("BOTTOMLEFT", 12, 194)
    sep2:SetPoint("BOTTOMRIGHT", -12, 194)

    -- Unterer Bereich
    -- Eigene Texte in der Reihenfolge des Makros: je ein Haken (einfügen ja/nein) + Textfeld
    local rows = {
        { y = 140, label = L.PRE_LABEL, key = "extraLines", use = "useExtraLines",
          title = L.PRE_TT_TITLE, tip = L.PRE_TT_TEXT, example = PRE_EXAMPLE, multi = true },
        { y = 114, label = L.ATK_LABEL, key = "attackConditions", use = "useAttackConditions",
          title = L.COND_TT_TITLE, tip = L.ATK_TT_TEXT, example = ATK_EXAMPLE },
        { y = 88, label = L.COND_LABEL, key = "conditions", use = "useConditions",
          title = L.COND_TT_TITLE, tip = L.COND_TT_TEXT, example = COND_EXAMPLE },
    }
    local labelWidth = 0
    for _, r in ipairs(rows) do
        local store = Store(r.use)
        r.check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        r.check:SetPoint("BOTTOMLEFT", 12, r.multi and r.y + EXTRA_H - 24 or r.y)   -- oben am Feld
        r.check:SetSize(24, 24)
        r.check:SetChecked(store[r.use])
        local text = r.check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", r.check, "RIGHT", 2, 1)
        text:SetText(r.label)
        labelWidth = math.max(labelWidth, text:GetStringWidth())
        r.check:SetScript("OnClick", function(self)
            CommitFields()
            store[r.use] = self:GetChecked() and true or false
            Refresh()   -- Markierungen: welche Makros sind noch aktuell?
        end)
    end

    local fieldWidth = math.max(120, frame:GetWidth() - 68 - labelWidth)
    local function Preview()
        return BuildBody(L.CMD_SPELL, CleanConditions(rows[3].box:GetText()),
            CleanConditions(rows[2].box:GetText()), CleanLines(rows[1].box:GetText()))
    end

    for _, r in ipairs(rows) do
        local store = Store(r.key)
        local box, area
        if r.multi then
            -- Mehrzeilig: eigener Rahmen + ScrollFrame, damit lange Eingaben nicht überlaufen
            local holder = CreateFrame("Frame", nil, frame)
            holder:SetPoint("TOPLEFT", r.check, "TOPRIGHT", labelWidth + 9, 0)
            holder:SetSize(fieldWidth + 5, EXTRA_H)
            local edge = holder:CreateTexture(nil, "BACKGROUND")
            edge:SetAllPoints()
            edge:SetColorTexture(0.5, 0.5, 0.5, 0.7)
            local bg = holder:CreateTexture(nil, "BORDER")
            bg:SetPoint("TOPLEFT", 1, -1)
            bg:SetPoint("BOTTOMRIGHT", -1, 1)
            bg:SetColorTexture(0.03, 0.03, 0.03, 1)

            area = CreateFrame("ScrollFrame", nil, holder)
            area:SetPoint("TOPLEFT", 5, -4)
            area:SetPoint("BOTTOMRIGHT", -5, 4)
            box = CreateFrame("EditBox", nil, area)
            box:SetMultiLine(true)
            box:SetFontObject(ChatFontNormal)
            box:SetWidth(fieldWidth - 5)
            box:SetHeight(EXTRA_H - 8)
            area:SetScrollChild(box)
            area:EnableMouse(true)
            area:SetScript("OnMouseDown", function() box:SetFocus() end)
            area:EnableMouseWheel(true)
            area:SetScript("OnMouseWheel", function(self, delta)
                local max = self:GetVerticalScrollRange() or 0
                self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 14)))
            end)
            -- Sichtbaren Ausschnitt der Schreibmarke folgen lassen
            box:SetScript("OnCursorChanged", function(_, _, y, _, h)
                local top, view = area:GetVerticalScroll(), area:GetHeight()
                y = -y
                if y < top then
                    area:SetVerticalScroll(y)
                elseif y + h > top + view then
                    area:SetVerticalScroll(y + h - view)
                end
            end)
        else
            box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            box:SetPoint("LEFT", r.check, "RIGHT", labelWidth + 14, 0)   -- alle Felder bündig
            box:SetSize(fieldWidth, 20)
            box:SetScript("OnEnterPressed", box.ClearFocus)
        end
        r.box = box
        fieldBoxes[#fieldBoxes + 1] = box
        box:SetAutoFocus(false)
        box:SetMaxLetters(r.multi and 200 or 120)
        box:SetText(store[r.key])
        box:SetCursorPosition(0)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(store[r.key])
            self:ClearFocus()
        end)
        box:HookScript("OnEditFocusLost", function(self)
            SetConditions(r.key, self:GetText())
            Refresh()
            self:SetText(store[r.key])
            self:SetCursorPosition(0)
        end)

        local function tooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(r.title)
            GameTooltip:AddLine(r.tip:format("|cffff8c1a" .. r.example .. "|r"), 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Preview(), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
        for _, w in ipairs({ r.check, box, area }) do
            w:SetScript("OnEnter", tooltip)
            w:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

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
    convert:SetScript("OnClick", function() CommitFields(); ConvertActionBars(false); Refresh() end)
    convert:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.CONVERT_TT_TITLE)
        GameTooltip:AddLine(L.CONVERT_TT_TEXT, 1, 1, 1, true)
        GameTooltip:AddLine(L.CONVERT_TT_UPDATE, 1, 1, 1, true)
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
-- Broker-Eintrag (Titan Panel, ChocolateBar, Bazooka, ElvUI-Datentexte ...)
-- Nur wenn LibDataBroker schon durch ein anderes Addon geladen ist;
-- das Addon selbst bringt weiterhin keine Bibliotheken mit.
------------------------------------------------------------------------
local function RegisterBroker()
    local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb then return false end
    if not ldb:GetDataObjectByName(BROKER_NAME) then
        ldb:NewDataObject(BROKER_NAME, {
            type = "launcher",
            label = BROKER_NAME,
            text = BROKER_NAME,
            icon = ADDON_ICON,
            tocname = ADDON_NAME,
            OnClick = function(_, button)
                if button == "RightButton" then OpenOptions() else Toggle() end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine(TITLE)
                tt:AddLine(" ")
                tt:AddDoubleLine("|cffffffff" .. L.MM_LEFT .. "|r", L.MM_OPEN, nil, nil, nil, 1, 0.82, 0)
                tt:AddDoubleLine("|cffffffff" .. L.MM_RIGHT .. "|r", L.MM_OPTIONS, nil, nil, nil, 1, 0.82, 0)
            end,
        })
    end
    return true
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
local loggedIn = false
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UPDATE_MACROS")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            -- Broker-Bibliothek kam erst mit einem nachgeladenen Addon
            if loggedIn and RegisterBroker() then self:UnregisterEvent("ADDON_LOADED") end
            return
        end
        StartAttackMacrosDB = StartAttackMacrosDB or {}
        db = StartAttackMacrosDB
        db.minimap = db.minimap or {}
        for k, v in pairs(DEFAULTS.minimap) do
            if db.minimap[k] == nil then db.minimap[k] = v end
        end
        for _, k in ipairs({ "conditions", "attackConditions" }) do
            if type(db[k]) ~= "string" then db[k] = DEFAULTS[k] end
        end
        for _, k in ipairs({ "useConditions", "useAttackConditions" }) do
            if db[k] == nil then db[k] = DEFAULTS[k] end
        end
        StartAttackMacrosCharDB = StartAttackMacrosCharDB or {}
        cdb = StartAttackMacrosCharDB
        if type(cdb.extraLines) ~= "string" then cdb.extraLines = CHAR_DEFAULTS.extraLines end
        if cdb.useExtraLines == nil then cdb.useExtraLines = CHAR_DEFAULTS.useExtraLines end
        CreateMinimapButton()
        CreateOptionsPanel()
    elseif event == "PLAYER_LOGIN" then
        loggedIn = true   -- jetzt sind alle Addons geladen
        if RegisterBroker() then self:UnregisterEvent("ADDON_LOADED") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        for key, old in pairs(pending) do
            pending[key] = nil
            UpdateExistingMacros(key, old)
        end
    elseif frame and frame:IsShown() then
        Refresh()
    end
end)
