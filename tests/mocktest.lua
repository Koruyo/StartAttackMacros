-- Minimal WoW API mock to exercise the macro-condition logic outside the game.
local dir = arg[1]
local created, combat, chat = {}, false, {}

local function newWidget(kind)
    local w = { kind = kind, scripts = {}, text = "", checked = false, shown = true }
    return setmetatable(w, { __index = function(_, k)
        if k == "SetScript" then return function(s, n, f) s.scripts[n] = { f } end end
        if k == "HookScript" then return function(s, n, f) s.scripts[n] = s.scripts[n] or {}; table.insert(s.scripts[n], f) end end
        if k == "Fire" then return function(s, n, ...) for _, f in ipairs(s.scripts[n] or {}) do f(s, ...) end end end
        if k == "SetText" then return function(s, t) s.text = t end end
        if k == "GetText" then return function(s) return s.text end end
        if k == "SetChecked" then return function(s, v) s.checked = v end end
        if k == "GetChecked" then return function(s) return s.checked end end
        if k == "Show" then return function(s) s.shown = true; s:Fire("OnShow") end end
        if k == "Hide" then return function(s) s.shown = false end end
        if k == "IsShown" then return function(s) return s.shown end end
        if k == "SetShown" then return function(s, v) s.shown = v end end
        if k == "GetWidth" then return function() return 422 end end
        if k == "GetStringWidth" then return function() return 100 end end
        if k == "state" or k == "spell" or k == "spellID" then return nil end   -- plain data fields
        if k:find("^Create") then return function() return newWidget("region") end end
        return function() end
    end })
end

function CreateFrame(kind, _, parent)
    local w = newWidget(kind); rawset(w, "parent", parent or false); created[#created + 1] = w; return w
end
UIParent, Minimap, GameTooltip = newWidget("f"), newWidget("f"), newWidget("f")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
UISpecialFrames, SlashCmdList = {}, {}
tinsert = table.insert
function GetAddOnMetadata() return "test" end
function GetLocale() return "enUS" end
function InCombatLockdown() return combat end
function GetNumSpellTabs() return 0 end
function PlaySound() end
local cursor, slots = nil, {}
function ClearCursor() cursor = nil end
function PickupMacro(i) cursor = i end
function PlaceAction(slot) slots[slot] = { "macro", cursor }; cursor = nil end
function GetActionInfo(slot) local a = slots[slot]; if a then return a[1], a[2] end end
function IsHarmfulSpell() return true end
function GetSpellInfo(id) return "Spell" .. id end

-- macro store: account macros at 1..120, character macros at 121..138
local acct, char = {}, {}
local function slot(i) if i > 120 then return char[i - 120] else return acct[i] end end
function GetNumMacros() return #acct, #char end
function GetMacroIndexByName(n)
    for i, m in ipairs(acct) do if m.name == n then return i end end
    for i, m in ipairs(char) do if m.name == n then return 120 + i end end
    return 0
end
function CreateMacro(n, _, b, perChar) table.insert(perChar and char or acct, { name = n, body = b }) end
function EditMacro(i, n, _, b) local m = slot(i); m.name = n or m.name; m.body = b or m.body end
function GetMacroInfo(i) local m = slot(i); return m and m.name end
function GetMacroBody(i) local m = slot(i); return m and m.body end

local ns = {}
assert(loadfile(dir .. "/Locales.lua"))("StartAttackMacros", ns)
assert(loadfile(dir .. "/StartAttackMacros.lua"))("StartAttackMacros", ns)

local ev
for _, w in ipairs(created) do if w.scripts.OnEvent then ev = w end end
ev:Fire("OnEvent", "ADDON_LOADED", "StartAttackMacros")
ev:Fire("OnEvent", "PLAYER_LOGIN")                 -- no LibStub around: must not error
ev:Fire("OnEvent", "ADDON_LOADED", "SomeOtherAddon")

local sam = SlashCmdList.STARTATTACKMACROS
local function body(spell) return GetMacroBody(GetMacroIndexByName(("+" .. spell):sub(1, 16))) end
local function plain(s) return "#showtooltip " .. s .. "\n/startattack\n/cast " .. s end
local function with(c, s) return "#showtooltip " .. s .. "\n/startattack\n/cast " .. c .. " " .. s end
local pass, fail = 0, 0
local function check(label, got, want)
    if got == want then pass = pass + 1 else
        fail = fail + 1
        print("FAIL " .. label .. "\n  got:  " .. tostring(got):gsub("\n", "\\n") .. "\n  want: " .. tostring(want):gsub("\n", "\\n"))
    end
end

-- 1) default: nothing configured -> unchanged macro format
sam("Sinister Strike")
check("default body", body("Sinister Strike"), plain("Sinister Strike"))

-- 2) open the window, find the new widgets
local before = #created
sam("")
local checks, boxes = {}, {}
for i = before + 1, #created do
    local w = created[i]
    if w.kind == "CheckButton" then checks[#checks + 1] = w end
    if w.kind == "EditBox" then boxes[#boxes + 1] = w end
end
assert(#checks == 8 and #boxes == 7, "widgets not created")   -- 6 attack rows, 1 help row, "show all"
local postCheck, postBox = checks[6], boxes[6]
local midCheck, midBox, sufCheck, sufBox = checks[3], boxes[3], checks[5], boxes[5]
check("end-lines checkbox defaults to unticked", postCheck.checked, false)
local preCheck, atkCheck, condCheck, preBox, atkBox, condBox = checks[1], checks[2], checks[4], boxes[1], boxes[2], boxes[4]
check("lines checkbox defaults to unticked", preCheck.checked, false)
-- fields are only shown while their box is ticked
local function holderOf(box) return box.parent.parent end
for i = 1, 6 do check("field " .. i .. " hidden while unticked", holderOf(boxes[i]).shown, false) end
check("unticked by default in the saved settings",
    StartAttackMacrosDB.useConditions == false and StartAttackMacrosCharDB.useLinesAfter == false, true)
condBox:SetText("[ignored]"); condBox:Fire("OnEditFocusLost")
sam("Sinister Strike")
check("unticked text is kept but not used", body("Sinister Strike"), plain("Sinister Strike"))
check("unticked text is kept", StartAttackMacrosDB.conditions, "[ignored]")
condBox:SetText(""); condBox:Fire("OnEditFocusLost")
for i = 1, 6 do
    checks[i]:SetChecked(true); checks[i]:Fire("OnClick")
    check("field " .. i .. " shown once ticked", holderOf(boxes[i]).shown, true)
end
checks[3]:SetChecked(false); checks[3]:Fire("OnClick")
check("field hidden again when unticked", holderOf(boxes[3]).shown, false)
checks[3]:SetChecked(true); checks[3]:Fire("OnClick")

local function typeText(t) condBox:SetText(t); condBox:Fire("OnEditFocusLost") end
local A, B = "[@mouseover,harm,nodead][]", "[@focus,harm][]"

-- 3) set text: existing plain macro is left alone, new/re-clicked macros get it
typeText("  " .. A .. "  ")
check("text is trimmed", StartAttackMacrosDB.conditions, A)
check("plain macro untouched on first set", body("Sinister Strike"), plain("Sinister Strike"))
sam("Sinister Strike"); sam("Eviscerate")
check("re-click adds text", body("Sinister Strike"), with(A, "Sinister Strike"))
check("new macro has text", body("Eviscerate"), with(A, "Eviscerate"))

-- 4) untick -> macro without the text
condCheck:SetChecked(false); condCheck:Fire("OnClick")
sam("Backstab")
check("unticked -> plain", body("Backstab"), plain("Backstab"))
condCheck:SetChecked(true); condCheck:Fire("OnClick")

-- 5) hand-edited macro with other conditions must survive a text change
sam("Gouge")
EditMacro(GetMacroIndexByName("+Gouge"), nil, nil, with("[mod:shift,@player]", "Gouge"))

-- 6) change text -> only macros containing the old text follow
typeText(B)
check("follows text change", body("Sinister Strike"), with(B, "Sinister Strike"))
check("follows text change 2", body("Eviscerate"), with(B, "Eviscerate"))
check("excluded macro stays plain", body("Backstab"), plain("Backstab"))
check("hand-edited macro untouched", body("Gouge"), with("[mod:shift,@player]", "Gouge"))
check("update message printed", chat[#chat]:find("2|r existing macros updated", 1, true) ~= nil, true)

-- 7) change during combat -> deferred until combat ends
combat = true
typeText(A)
check("no edit in combat", body("Eviscerate"), with(B, "Eviscerate"))
combat = false
ev:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
check("updated after combat", body("Eviscerate"), with(A, "Eviscerate"))

-- 8) Escape reverts the field
condBox:SetText("garbage"); condBox:Fire("OnEscapePressed"); condBox:Fire("OnEditFocusLost")
check("escape reverts", StartAttackMacrosDB.conditions, A)

-- 9) too long -> falls back to the plain macro with a warning
local long = string.rep("x", 110)
sam(long)
check("over 255 falls back", GetMacroBody(GetMacroIndexByName(("+" .. long):sub(1, 16))), plain(long))
check("warning printed", chat[#chat]:find("255", 1, true) ~= nil, true)

-- 10) clearing the text strips it from macros that had it
typeText("")
check("cleared", body("Sinister Strike"), plain("Sinister Strike"))

-- 11) tooltip preview runs without error
condBox:Fire("OnEnter"); atkBox:Fire("OnEnter")

-- 12) /startattack field
local function full(a, c, s2)
    return "#showtooltip " .. s2 .. "\n/startattack" .. (a ~= "" and " " .. a or "")
        .. "\n/cast " .. (c ~= "" and c .. " " or "") .. s2
end
local function typeAtk(t) atkBox:SetText(t); atkBox:Fire("OnEditFocusLost") end
local H = "[harm,nodead]"
typeAtk(H)
check("attack text saved", StartAttackMacrosDB.attackConditions, H)
check("plain macro untouched on first set", body("Sinister Strike"), plain("Sinister Strike"))
sam("Sinister Strike")
check("attack only", body("Sinister Strike"), full(H, "", "Sinister Strike"))
typeText(A)
sam("Eviscerate")
check("both texts", body("Eviscerate"), full(H, A, "Eviscerate"))
check("cast change leaves attack-only macro alone", body("Sinister Strike"), full(H, "", "Sinister Strike"))
atkCheck:SetChecked(false); atkCheck:Fire("OnClick")
sam("Backstab")
check("attack unticked, cast ticked", body("Backstab"), full("", A, "Backstab"))
atkCheck:SetChecked(true); atkCheck:Fire("OnClick")
typeAtk("[harm]")
check("attack change keeps cast text", body("Eviscerate"), full("[harm]", A, "Eviscerate"))
check("attack change, attack-only macro", body("Sinister Strike"), full("[harm]", "", "Sinister Strike"))
check("macro without attack text untouched", body("Backstab"), full("", A, "Backstab"))
check("hand-edited macro still untouched", body("Gouge"), with("[mod:shift,@player]", "Gouge"))
typeText(B)
check("cast change keeps attack text", body("Eviscerate"), full("[harm]", B, "Eviscerate"))
combat = true
typeAtk(H); typeText(A)
check("nothing edited in combat", body("Eviscerate"), full("[harm]", B, "Eviscerate"))
combat = false
ev:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
check("both applied after combat", body("Eviscerate"), full(H, A, "Eviscerate"))
typeAtk("")
check("attack text cleared", body("Eviscerate"), full("", A, "Eviscerate"))

-- 13) convert button brings existing macros in line with the current fields
typeAtk(""); typeText("")
sam("Sinister Strike"); sam("Eviscerate"); sam("Backstab")
check("reset to plain", body("Eviscerate"), plain("Eviscerate"))
typeText(A); typeAtk(H)          -- first set: nothing is touched automatically
check("still plain before convert", body("Eviscerate"), plain("Eviscerate"))
EditMacro(GetMacroIndexByName("+Backstab"), nil, nil, plain("Backstab") .. "\n")           -- trailing newline
EditMacro(GetMacroIndexByName("+Sinister Strike"), nil, nil,
    "#showtooltip Sinister Strike\n/startattack\n/cast [@mouseover,harm,nodead]Sinister Strike") -- hand edit, no space
local foreign = "#showtooltip\n/cast Something else"
CreateMacro("+Other", nil, foreign, true)
CreateMacro("MyMacro", nil, plain("Eviscerate"), true)
sam("convert")
check("convert updates plain macro", body("Eviscerate"), full(H, A, "Eviscerate"))
check("convert handles trailing newline", body("Backstab"), full(H, A, "Backstab"))
check("convert normalises hand edit", body("Sinister Strike"), full(H, A, "Sinister Strike"))
check("foreign '+' macro untouched", GetMacroBody(GetMacroIndexByName("+Other")), foreign)
check("macro without prefix untouched", GetMacroBody(GetMacroIndexByName("MyMacro")), plain("Eviscerate"))
check("convert reports updates", chat[#chat]:find("existing macros updated", 1, true) ~= nil, true)
local n = #chat
sam("convert")
check("second convert changes nothing", chat[#chat]:find("No attack abilities", 1, true) ~= nil and #chat == n + 1, true)
slots[1] = { "spell", 100 }
sam("convert")
local a = { GetActionInfo(1) }
check("spell slot converted", a[1] == "macro" and GetMacroInfo(a[2]) == "+Spell100", true)
check("converted macro has both texts", body("Spell100"), full(H, A, "Spell100"))

-- 14) marker on the spell buttons: current / outdated / none
local names = { [301] = "Eviscerate", [302] = "Kick" }
local oldInfo = GetSpellInfo
GetSpellInfo = function(id) return names[id] or oldInfo(id) end
GetSpellTexture = function() end
GetNumSpellTabs = function() return 1 end
GetSpellTabInfo = function() return "tab", nil, 0, 2 end
GetSpellBookItemInfo = function(i) return "SPELL", 300 + i end
IsPassiveSpell = function() return false end
ev:Fire("OnEvent", "SPELLS_CHANGED")
local function btn(spell)
    for _, w in ipairs(created) do
        if w.kind == "Button" and rawget(w, "spell") == spell then return w end
    end
end
assert(btn("Eviscerate") and btn("Kick"), "spell buttons not created")
check("up-to-date macro -> current", btn("Eviscerate").state, "current")
check("no macro -> no marker", btn("Kick").state, nil)
check("no marker hidden", btn("Kick").check.shown, false)
atkCheck:SetChecked(false); atkCheck:Fire("OnClick")
check("tick box change -> outdated", btn("Eviscerate").state, "outdated")
check("outdated marker shown", btn("Eviscerate").check.shown, true)
btn("Eviscerate"):Fire("OnEnter")
btn("Eviscerate"):Fire("OnClick")
check("click updates macro", body("Eviscerate"), full("", A, "Eviscerate"))
check("click -> current", btn("Eviscerate").state, "current")
atkCheck:SetChecked(true); atkCheck:Fire("OnClick")
check("re-tick -> outdated again", btn("Eviscerate").state, "outdated")
typeText(B)   -- macros containing A follow automatically, but the /startattack part still differs
check("still outdated after cast text change", btn("Eviscerate").state, "outdated")
sam("convert"); ev:Fire("OnEvent", "UPDATE_MACROS")
check("convert -> current", btn("Eviscerate").state, "current")
check("convert result", body("Eviscerate"), full(H, B, "Eviscerate"))
typeText(""); typeAtk("")
sam("Eviscerate"); ev:Fire("OnEvent", "UPDATE_MACROS")
check("plain + empty fields -> current", btn("Eviscerate").state, "current")
typeAtk(H)    -- first entry of a text: existing macros are not touched, but marked
check("first text entry -> outdated", btn("Eviscerate").state, "outdated")
btn("Kick"):Fire("OnClick")
check("new macro -> current", btn("Kick").state, "current")

-- 15) extra lines between #showtooltip and /startattack (saved per character)
local function lines4(x, a, c, s2)
    return "#showtooltip " .. s2 .. (x ~= "" and "\n" .. x or "") .. "\n/startattack" .. (a ~= "" and " " .. a or "")
        .. "\n/cast " .. (c ~= "" and c .. " " or "") .. s2
end
local function typePre(t) preBox:SetText(t); preBox:Fire("OnEditFocusLost") end
typeText(""); typeAtk("")
sam("Eviscerate"); sam("Kick"); sam("Backstab")
check("reset to plain again", body("Eviscerate"), plain("Eviscerate"))
local P, P2 = "/petattack\n/ssf delete", "/petattack"
typePre("  /petattack \n\n   /ssf delete\r\n\n")
check("lines trimmed, blank lines dropped", StartAttackMacrosCharDB.extraLines, P)
check("lines not stored account-wide", StartAttackMacrosDB.extraLines, nil)
check("field shows cleaned lines", preBox:GetText(), P)
check("plain macro untouched on first set of lines", body("Eviscerate"), plain("Eviscerate"))
check("lines set -> outdated", btn("Eviscerate").state, "outdated")
sam("Eviscerate")
check("re-click adds lines", body("Eviscerate"), lines4(P, "", "", "Eviscerate"))
typeAtk(H); typeText(A)
sam("Kick")
check("lines + both texts", body("Kick"), lines4(P, H, A, "Kick"))
typeText(B)
check("cast change keeps lines", body("Kick"), lines4(P, H, B, "Kick"))
check("cast change leaves macro without cast text alone", body("Eviscerate"), lines4(P, "", "", "Eviscerate"))
typePre(P2)
check("lines change follows", body("Eviscerate"), lines4(P2, "", "", "Eviscerate"))
check("lines change keeps texts", body("Kick"), lines4(P2, H, B, "Kick"))
check("macro without lines untouched", body("Backstab"), plain("Backstab"))
preCheck:SetChecked(false); preCheck:Fire("OnClick")
check("lines unticked -> saved per character", StartAttackMacrosCharDB.useExtraLines, false)
sam("Gouge")
check("lines unticked -> no lines", body("Gouge"), lines4("", H, B, "Gouge"))
preCheck:SetChecked(true); preCheck:Fire("OnClick")
-- hand-edited macro with other lines: recognised, left alone by a text change, normalised by convert
EditMacro(GetMacroIndexByName("+Gouge"), nil, nil, lines4("/cleartarget [dead]", H, B, "Gouge"))
typePre(P)
check("other hand-written lines untouched by change", body("Gouge"), lines4("/cleartarget [dead]", H, B, "Gouge"))
combat = true
typePre(P2)
check("lines not edited in combat", body("Kick"), lines4(P, H, B, "Kick"))
combat = false
ev:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
check("lines applied after combat", body("Kick"), lines4(P2, H, B, "Kick"))
sam("convert")
check("convert applies lines everywhere", body("Backstab"), lines4(P2, H, B, "Backstab"))
check("convert normalises hand-written lines", body("Gouge"), lines4(P2, H, B, "Gouge"))
check("foreign '+' macro still untouched", GetMacroBody(GetMacroIndexByName("+Other")), foreign)
check("macro without prefix still untouched", GetMacroBody(GetMacroIndexByName("MyMacro")), plain("Eviscerate"))
ev:Fire("OnEvent", "UPDATE_MACROS")
check("after convert -> current", btn("Eviscerate").state, "current")
preBox:SetText("garbage"); preBox:Fire("OnEscapePressed"); preBox:Fire("OnEditFocusLost")
check("escape reverts lines", StartAttackMacrosCharDB.extraLines, P2)
typePre(string.rep("/script DoSomethingVeryLong()\n", 8))
local n2 = #chat
sam("Kick")
check("lines over 255 fall back to plain", body("Kick"), plain("Kick"))
check("warning printed for lines", #chat == n2 + 1 and chat[#chat]:find("255", 1, true) ~= nil, true)
preBox:Fire("OnEnter"); preCheck:Fire("OnEnter")
typePre("")
check("lines cleared", StartAttackMacrosCharDB.extraLines, "")

-- 15b) lines after /cast (end of the macro), saved per character
local function lines5(x, a, c, s2, z)
    return lines4(x, a, c, s2) .. (z ~= "" and "\n" .. z or "")
end
local function typePost(t) postBox:SetText(t); postBox:Fire("OnEditFocusLost") end
typePre(""); typeAtk(""); typeText("")
sam("Eviscerate"); sam("Kick"); sam("Backstab"); sam("Gouge")
check("reset to plain before end lines", body("Kick"), plain("Kick"))
local Z, Z2 = "/script UIErrorsFrame:Clear()", "/petattack\n/script UIErrorsFrame:Clear()"
typePost("  " .. Z .. "  \n\n")
check("end lines cleaned", StartAttackMacrosCharDB.linesAfter, Z)
check("end lines not stored account-wide", StartAttackMacrosDB.linesAfter, nil)
check("plain macro untouched on first set of end lines", body("Kick"), plain("Kick"))
check("end lines set -> outdated", btn("Eviscerate").state, "outdated")
sam("Kick")
check("re-click adds end lines", body("Kick"), lines5("", "", "", "Kick", Z))
typePre(P2); typeAtk(H); typeText(A)
sam("Eviscerate")
check("all four texts", body("Eviscerate"), lines5(P2, H, A, "Eviscerate", Z))
check("other changes leave end-lines-only macro alone", body("Kick"), lines5("", "", "", "Kick", Z))
typePost(Z2)
check("end lines change follows", body("Kick"), lines5("", "", "", "Kick", Z2))
check("end lines change keeps the rest", body("Eviscerate"), lines5(P2, H, A, "Eviscerate", Z2))
check("macro without end lines untouched", body("Backstab"), plain("Backstab"))
typePre(P)
check("pre change keeps end lines", body("Eviscerate"), lines5(P, H, A, "Eviscerate", Z2))
typeText(B)
check("cast change keeps end lines", body("Eviscerate"), lines5(P, H, B, "Eviscerate", Z2))
postCheck:SetChecked(false); postCheck:Fire("OnClick")
check("end lines unticked -> saved per character", StartAttackMacrosCharDB.useLinesAfter, false)
sam("Gouge")
check("end lines unticked -> none", body("Gouge"), lines5(P, H, B, "Gouge", ""))
postCheck:SetChecked(true); postCheck:Fire("OnClick")
EditMacro(GetMacroIndexByName("+Gouge"), nil, nil, lines5("/cleartarget [dead]", H, B, "Gouge", "/say hand-written"))
typePost(Z)
check("hand-written end lines untouched by change", body("Gouge"), lines5("/cleartarget [dead]", H, B, "Gouge", "/say hand-written"))
sam("convert")
check("convert applies end lines everywhere", body("Backstab"), lines5(P, H, B, "Backstab", Z))
check("convert normalises hand-written end lines", body("Gouge"), lines5(P, H, B, "Gouge", Z))
check("foreign '+' macro untouched by end lines", GetMacroBody(GetMacroIndexByName("+Other")), foreign)
ev:Fire("OnEvent", "UPDATE_MACROS")
check("after convert with end lines -> current", btn("Eviscerate").state, "current")
postBox:SetText("garbage"); postBox:Fire("OnEscapePressed"); postBox:Fire("OnEditFocusLost")
check("escape reverts end lines", StartAttackMacrosCharDB.linesAfter, Z)
-- conditions pasted with line breaks end up on one line
typeText("[@mouseover,harm]\n[]")
check("line breaks in conditions collapse", StartAttackMacrosDB.conditions, "[@mouseover,harm] []")
check("enter applies in condition fields", condBox.scripts.OnEnterPressed ~= nil and atkBox.scripts.OnEnterPressed ~= nil, true)
check("enter is a new line in line fields", preBox.scripts.OnEnterPressed == nil and postBox.scripts.OnEnterPressed == nil, true)
postBox:Fire("OnEnter"); postCheck:Fire("OnEnter")
typePost(string.rep("/script DoSomethingVeryLong()\n", 8))
sam("Kick")
check("end lines over 255 fall back to plain", body("Kick"), plain("Kick"))
typePost(""); typePre(""); typeAtk(""); typeText("")
check("end lines cleared", StartAttackMacrosCharDB.linesAfter, "")

-- 15c) lines between /startattack and /cast, and text right after the spell name
local function all6(x, a, m, c, s2, suf, z)
    return "#showtooltip " .. s2 .. (x ~= "" and "\n" .. x or "") .. "\n/startattack" .. (a ~= "" and " " .. a or "")
        .. (m ~= "" and "\n" .. m or "") .. "\n/cast " .. (c ~= "" and c .. " " or "") .. s2 .. suf
        .. (z ~= "" and "\n" .. z or "")
end
local function typeMid(t) midBox:SetText(t); midBox:Fire("OnEditFocusLost") end
local function typeSuf(t) sufBox:SetText(t); sufBox:Fire("OnEditFocusLost") end
sam("Eviscerate"); sam("Kick"); sam("Backstab"); sam("Gouge")
check("reset to plain before mid/suffix", body("Kick"), plain("Kick"))
local M, M2, S, S2 = "/use 13", "/use 13\n/use 14", "(Rank 1)", "; [mod:shift] Kick"
typeMid("  " .. M .. " \n\n")
check("mid lines cleaned, per character", StartAttackMacrosCharDB.linesBetween == M and StartAttackMacrosDB.linesBetween == nil, true)
check("plain macro untouched on first set of mid lines", body("Kick"), plain("Kick"))
check("mid lines set -> outdated", btn("Eviscerate").state, "outdated")
sam("Kick")
check("re-click adds mid lines", body("Kick"), all6("", "", M, "", "Kick", "", ""))
typeSuf("  " .. S .. " ")
check("suffix cleaned, per character", StartAttackMacrosCharDB.castSuffix == S and StartAttackMacrosDB.castSuffix == nil, true)
check("suffix: macro without it untouched on first set", body("Kick"), all6("", "", M, "", "Kick", "", ""))
sam("Eviscerate")
check("suffix attached without a space", body("Eviscerate"), all6("", "", M, "", "Eviscerate", S, ""))
typePre(P2); typeAtk(H); typeText(A); typePost(Z)
sam("Backstab")
check("all six positions", body("Backstab"), all6(P2, H, M, A, "Backstab", S, Z))
check("all six, literal", body("Backstab"),
    "#showtooltip Backstab\n/petattack\n/startattack [harm,nodead]\n/use 13\n/cast [@mouseover,harm,nodead][] Backstab(Rank 1)\n/script UIErrorsFrame:Clear()")
typeMid(M2)
check("mid change follows", body("Backstab"), all6(P2, H, M2, A, "Backstab", S, Z))
check("mid change follows, mid-only macro", body("Kick"), all6("", "", M2, "", "Kick", "", ""))
typeSuf(S2)
check("suffix change follows", body("Backstab"), all6(P2, H, M2, A, "Backstab", S2, Z))
check("suffix change follows 2", body("Eviscerate"), all6("", "", M2, "", "Eviscerate", S2, ""))
check("suffix change leaves macro without suffix alone", body("Kick"), all6("", "", M2, "", "Kick", "", ""))
typeText(B)
check("cast condition change keeps mid and suffix", body("Backstab"), all6(P2, H, M2, B, "Backstab", S2, Z))
typeAtk("[harm]")
check("attack change keeps mid and suffix", body("Backstab"), all6(P2, "[harm]", M2, B, "Backstab", S2, Z))
typePost("")
check("clearing end lines keeps mid and suffix", body("Backstab"), all6(P2, "[harm]", M2, B, "Backstab", S2, ""))
midCheck:SetChecked(false); midCheck:Fire("OnClick"); sufCheck:SetChecked(false); sufCheck:Fire("OnClick")
check("unticked saved per character", StartAttackMacrosCharDB.useLinesBetween == false and StartAttackMacrosCharDB.useCastSuffix == false, true)
sam("Gouge")
check("unticked -> neither mid nor suffix", body("Gouge"), all6(P2, "[harm]", "", B, "Gouge", "", ""))
midCheck:SetChecked(true); midCheck:Fire("OnClick"); sufCheck:SetChecked(true); sufCheck:Fire("OnClick")
check("re-ticked -> outdated", btn("Eviscerate").state, "outdated")
-- hand-written mid line with another /cast and a hand-written suffix: recognised, kept by text changes
EditMacro(GetMacroIndexByName("+Gouge"), nil, nil, all6(P2, "[harm]", "/cast Blood Fury", B, "Gouge", "; Kick", ""))
typeMid(M)
check("hand-written mid/suffix untouched by change", body("Gouge"), all6(P2, "[harm]", "/cast Blood Fury", B, "Gouge", "; Kick", ""))
check("mid change applied elsewhere", body("Backstab"), all6(P2, "[harm]", M, B, "Backstab", S2, ""))
typePre("")
check("pre cleared in hand-written macro, rest kept", body("Gouge"), all6("", "[harm]", "/cast Blood Fury", B, "Gouge", "; Kick", ""))
combat = true
typeMid(M2); typeSuf(S)
check("mid/suffix not edited in combat", body("Backstab"), all6("", "[harm]", M, B, "Backstab", S2, ""))
combat = false
ev:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
check("mid/suffix applied after combat", body("Backstab"), all6("", "[harm]", M2, B, "Backstab", S, ""))
sam("convert")
check("convert applies all positions", body("Kick"), all6("", "[harm]", M2, B, "Kick", S, ""))
check("convert normalises hand-written mid/suffix", body("Gouge"), all6("", "[harm]", M2, B, "Gouge", S, ""))
check("foreign '+' macro untouched by mid/suffix", GetMacroBody(GetMacroIndexByName("+Other")), foreign)
check("macro without prefix untouched by mid/suffix", GetMacroBody(GetMacroIndexByName("MyMacro")), plain("Eviscerate"))
ev:Fire("OnEvent", "UPDATE_MACROS")
check("after convert with all positions -> current", btn("Eviscerate").state, "current")
midBox:SetText("garbage"); midBox:Fire("OnEscapePressed"); midBox:Fire("OnEditFocusLost")
sufBox:SetText("garbage"); sufBox:Fire("OnEscapePressed"); sufBox:Fire("OnEditFocusLost")
check("escape reverts mid and suffix", StartAttackMacrosCharDB.linesBetween == M2 and StartAttackMacrosCharDB.castSuffix == S, true)
check("enter applies in the suffix field", sufBox.scripts.OnEnterPressed ~= nil, true)
check("enter is a new line in the mid field", midBox.scripts.OnEnterPressed == nil, true)
midBox:Fire("OnEnter"); sufBox:Fire("OnEnter"); midCheck:Fire("OnEnter"); sufCheck:Fire("OnEnter")
typeMid(string.rep("/script DoSomethingVeryLong()\n", 8))
sam("Kick")
check("mid lines over 255 fall back to plain", body("Kick"), plain("Kick"))
typeMid(""); typeSuf(""); typePre(""); typeAtk(""); typeText(""); typePost("")
check("mid and suffix cleared", StartAttackMacrosCharDB.linesBetween == "" and StartAttackMacrosCharDB.castSuffix == "", true)
sam("Eviscerate"); sam("Kick"); sam("Backstab"); sam("Gouge")
check("everything plain again", body("Gouge"), plain("Gouge"))

-- 16) broker entry: registered once LibDataBroker shows up, never twice
local objects, made = {}, 0
local ldb = {
    GetDataObjectByName = function(_, n) return objects[n] end,
    NewDataObject = function(_, n, o) objects[n] = o; made = made + 1; return o end,
}
LibStub = { GetLibrary = function(_, n, silent) assert(silent); return n == "LibDataBroker-1.1" and ldb or nil end }
ev:Fire("OnEvent", "ADDON_LOADED", "SomeBrokerDisplay")
ev:Fire("OnEvent", "ADDON_LOADED", "AnotherAddon")
ev:Fire("OnEvent", "PLAYER_LOGIN")
local obj = objects["StartAttack Macros"]
check("broker object registered once", obj ~= nil and made == 1, true)
check("broker object is a launcher with icon", obj.type == "launcher" and obj.icon ~= nil, true)
local win
for _, w in ipairs(created) do if w.scripts.OnShow and w.scripts.OnHide then win = w end end
local shownBefore = win.shown
obj.OnClick(nil, "LeftButton")
check("broker left-click toggles the window", win.shown, not shownBefore)
obj.OnClick(nil, "LeftButton")
check("broker left-click toggles back", win.shown, shownBefore)
obj.OnClick(nil, "RightButton")
obj.OnTooltipShow(GameTooltip)

-- 17) macro names are never cut in the middle of a UTF-8 character
local function validUtf8(str)
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local len = b < 0x80 and 1 or b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 0
        if len == 0 or i + len - 1 > #str then return false end
        for j = i + 1, i + len - 1 do
            local c = str:byte(j)
            if c < 0x80 or c >= 0xC0 then return false end
        end
        i = i + len
    end
    return true
end
local function nameOf(spell)
    sam(spell)
    for i = 1, 138 do
        local nm, b = GetMacroInfo(i), GetMacroBody(i)
        if nm and b and b:find("^#showtooltip " .. spell .. "\n") then return nm end
    end
end
local RU, KO, ZH = "Кровопускание", "피의 소용돌이 강타", "致死打击致死打击"
check("cyrillic name cut at a character", nameOf(RU), "+Кровопу")
check("cyrillic name is valid UTF-8", validUtf8(nameOf(RU)), true)
check("korean name is valid UTF-8", validUtf8(nameOf(KO)), true)
check("korean name within 16 bytes", #nameOf(KO) <= 16, true)
check("chinese name keeps 5 characters", nameOf(ZH), "+致死打击致")
check("short cyrillic name unchanged", nameOf("Удар"), "+Удар")
check("ascii name still cut at 16", nameOf("Sinister Strike of Doom"), "+Sinister Strike")
check("old byte cut was indeed invalid", validUtf8(("+" .. RU):sub(1, 16)), false)
ev:Fire("OnEvent", "UPDATE_MACROS")

-- 18) names broken by v1.3.1 are repaired, the macro itself survives
local RU2 = "Сокрушительный удар"
local brokenName = ("+" .. RU2):sub(1, 16)
check("test name really is broken", validUtf8(brokenName), false)
CreateMacro(brokenName, nil, plain(RU2), true)
local nBefore = select(2, GetNumMacros())
local n3 = #chat
ev:Fire("OnEvent", "UPDATE_MACROS")
check("broken name gone", GetMacroIndexByName(brokenName), 0)
local fixedIdx = GetMacroIndexByName("+Сокруши")
check("renamed to valid name", fixedIdx > 0 and GetMacroBody(fixedIdx) == plain(RU2), true)
check("no macro lost or added", select(2, GetNumMacros()), nBefore)
check("rename reported", chat[n3 + 1] ~= nil and chat[n3 + 1]:find("renamed", 1, true) ~= nil, true)
n3 = #chat
ev:Fire("OnEvent", "UPDATE_MACROS")
check("second pass renames nothing", #chat, n3)
-- not in combat, but afterwards
local RU3 = "Смертельный удар"
local broken3 = ("+" .. RU3):sub(1, 16)
CreateMacro(broken3, nil, plain(RU3), true)
combat = true
ev:Fire("OnEvent", "UPDATE_MACROS")
check("no rename in combat", GetMacroIndexByName(broken3) > 0, true)
combat = false
ev:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
check("renamed after combat", GetMacroIndexByName(broken3) == 0 and GetMacroIndexByName("+Смертел") > 0, true)
-- a foreign '+' macro with a broken-looking name is not touched
CreateMacro("+Чужой\208", nil, "/say hi", true)
ev:Fire("OnEvent", "UPDATE_MACROS")
check("foreign macro name untouched", GetMacroIndexByName("+Чужой\208") > 0, true)

-- 18b) page "Helpful spells": mouseover macros without /startattack
local function widget(kind, text)
    for _, w in ipairs(created) do
        if w.kind == kind and rawget(w, "text") == text then return w end
    end
end
local tabAttack, tabHelp = widget("Button", "Attack abilities"), widget("Button", "Helpful spells")
local convertBtn = widget("Button", "Convert all attacks on your action bars")
assert(tabAttack and tabHelp and convertBtn, "tabs or convert button not found")
local helpCheck, helpBox = checks[7], boxes[7]
local HD = "[@mouseover,help,nodead][]"
check("help condition prefilled", StartAttackMacrosDB.helpConditions, HD)
check("help box ticked by default", helpCheck.checked == true and StartAttackMacrosDB.useHelpConditions == true, true)
check("help field visible by default", holderOf(helpBox).shown, true)
local helpful = { ["Flash Heal"] = true, ["Holy Shock"] = true }
IsHelpfulSpell = function(n) return helpful[n] or false end
IsHarmfulSpell = function(n) return n ~= "Flash Heal" end
names[303], names[304] = "Flash Heal", "Holy Shock"
GetSpellTabInfo = function() return "tab", nil, 0, 4 end
ev:Fire("OnEvent", "SPELLS_CHANGED")
check("attack page does not list pure heals", btn("Flash Heal"), nil)
tabHelp:Fire("OnClick")
check("help page lists helpful spells", btn("Flash Heal") ~= nil and btn("Holy Shock") ~= nil, true)
check("help page hides attacks", btn("Kick") == nil or btn("Kick").shown == false, true)
check("convert button text follows the page", convertBtn.text, "Convert all helpful spells on your action bars")
local function hbody(spell) return GetMacroBody(GetMacroIndexByName(("@" .. spell):sub(1, 16))) end
local function hmac(c, s2) return "#showtooltip " .. s2 .. "\n/cast " .. (c ~= "" and c .. " " or "") .. s2 end
check("no help macro yet -> no marker", btn("Flash Heal").state, nil)
btn("Flash Heal"):Fire("OnClick")
check("mouseover macro created", hbody("Flash Heal"), "#showtooltip Flash Heal\n/cast [@mouseover,help,nodead][] Flash Heal")
check("no /startattack macro for it", GetMacroIndexByName("+Flash Heal"), 0)
check("help macro -> current", btn("Flash Heal").state, "current")
sam("Holy Shock")                         -- attack macro via slash command
btn("Holy Shock"):Fire("OnClick")         -- mouseover macro for the same spell
check("dual spell has both macros", GetMacroIndexByName("+Holy Shock") > 0 and GetMacroIndexByName("@Holy Shock") > 0, true)
check("attack macro of a dual spell untouched", body("Holy Shock"), plain("Holy Shock"))
local function typeHelp(t) helpBox:SetText(t); helpBox:Fire("OnEditFocusLost") end
EditMacro(GetMacroIndexByName("@Holy Shock"), nil, nil, hmac("[@focus,help]", "Holy Shock"))
local HS = "[@mouseover,help,nodead][help,nodead][@player]"
typeHelp("  " .. HS .. " ")
check("help condition saved account-wide", StartAttackMacrosDB.helpConditions == HS and StartAttackMacrosCharDB.helpConditions == nil, true)
check("help condition change follows", hbody("Flash Heal"), hmac(HS, "Flash Heal"))
check("hand-edited help macro untouched", hbody("Holy Shock"), hmac("[@focus,help]", "Holy Shock"))
check("hand-edited help macro -> outdated", btn("Holy Shock").state, "outdated")
check("attack macros untouched by help change", body("Holy Shock"), plain("Holy Shock"))
slots[5] = { "spell", 303 }; slots[6] = { "spell", 302 }   -- Flash Heal, Kick
convertBtn:Fire("OnClick")
local a5, a6 = { GetActionInfo(5) }, { GetActionInfo(6) }
check("helpful spell slot converted", a5[1] == "macro" and GetMacroInfo(a5[2]) == "@Flash Heal", true)
check("attack slot left alone on the help page", a6[1], "spell")
check("help convert normalises hand edit", hbody("Holy Shock"), hmac(HS, "Holy Shock"))
check("help convert message", chat[#chat - 1]:find("mouseover macros", 1, true) ~= nil, true)
check("help convert leaves attack macros alone", body("Holy Shock"), plain("Holy Shock"))
helpCheck:SetChecked(false); helpCheck:Fire("OnClick")
check("help field hidden when unticked", holderOf(helpBox).shown, false)
btn("Flash Heal"):Fire("OnClick")
check("unticked help -> plain cast", hbody("Flash Heal"), hmac("", "Flash Heal"))
helpCheck:SetChecked(true); helpCheck:Fire("OnClick")
check("re-ticked help -> outdated", btn("Flash Heal").state, "outdated")
combat = true
typeHelp(HD)
check("help macros not edited in combat", hbody("Holy Shock"), hmac(HS, "Holy Shock"))
combat = false
ev:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
check("help macros updated after combat", hbody("Holy Shock"), hmac(HD, "Holy Shock"))
local mine = "#showtooltip\n/cast [@mouseover] Whatever"
CreateMacro("@Mine", nil, mine, true)
CreateMacro("@Flash", nil, "#showtooltip Flash Heal\n/startattack\n/cast Flash Heal", true)   -- wrong shape/name
convertBtn:Fire("OnClick")
check("foreign '@' macro untouched", GetMacroBody(GetMacroIndexByName("@Mine")), mine)
check("'@' macro with another name untouched", GetMacroBody(GetMacroIndexByName("@Flash")),
    "#showtooltip Flash Heal\n/startattack\n/cast Flash Heal")
check("help convert updates plain help macro", hbody("Flash Heal"), hmac(HD, "Flash Heal"))
helpBox:Fire("OnEnter"); helpCheck:Fire("OnEnter"); convertBtn:Fire("OnEnter")
local long2 = string.rep("y", 60)
helpful[long2] = true
names[305] = long2
slots[7] = { "spell", 305 }
typeHelp("[" .. string.rep("a", 118) .. "]")
convertBtn:Fire("OnClick")
check("help macro over 255 falls back to plain cast",
    GetMacroBody(GetMacroIndexByName(("@" .. long2):sub(1, 16))), hmac("", long2))
typeHelp(HD)
tabAttack:Fire("OnClick")
check("attack page: convert button text", convertBtn.text, "Convert all attacks on your action bars")
check("attack page lists attacks again", btn("Kick") ~= nil and btn("Kick").shown ~= false, true)
check("attack page marker uses the attack macro", btn("Holy Shock").state, "current")
check("help macros survive the page switch", hbody("Holy Shock"), hmac(HD, "Holy Shock"))

-- 19) on load: a box stays ticked only where there is text
StartAttackMacrosDB.conditions, StartAttackMacrosDB.useConditions = "", true
StartAttackMacrosDB.attackConditions, StartAttackMacrosDB.useAttackConditions = "[harm]", true
StartAttackMacrosCharDB.extraLines, StartAttackMacrosCharDB.useExtraLines = "/petattack", false
StartAttackMacrosCharDB.linesAfter, StartAttackMacrosCharDB.useLinesAfter = nil, nil
ev:Fire("OnEvent", "ADDON_LOADED", "StartAttackMacros")
check("empty field is unticked on load", StartAttackMacrosDB.useConditions, false)
check("field with text stays ticked on load", StartAttackMacrosDB.useAttackConditions, true)
check("unticked field with text stays unticked on load", StartAttackMacrosCharDB.useExtraLines, false)
check("missing setting starts empty and unticked",
    StartAttackMacrosCharDB.linesAfter == "" and StartAttackMacrosCharDB.useLinesAfter == false, true)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)

