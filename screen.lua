-- ---------------------------------------------------------------------------
-- ConverterScreen -- the one screen of the unit converter
--
--   title bar (☰ menu, ✕)
--   [ Category ▾ ][ ingredient / rates / my time zone ]
--   [ From unit ▾ ][ ⇄ ][ To unit ▾ ]
--   ┌ typed value ─────────────────────┐
--   │ result (big, bold)               │
--   └──────────────────────────────────┘
--   one info line (1 ft = 0.3048 m, rate date, offsets...)
--   the value in every unit of the category (tap one: it becomes "To")
--   keypad (digits, Roman letters, hex digits or a clock, per unit)
--
-- Landscape puts the table in a column of its own on the right.
-- A key press repaints the display, the info line and the table only.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonDialog    = require("ui/widget/buttondialog")
local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local RenderText      = require("ui/rendertext")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")

local Catalog = lrequire("catalog")
local NumFmt  = lrequire("numfmt")

local DeviceScreen = Device.screen
-- Font:getFace() scales its size by the screen DPI; pixel-derived sizes are
-- divided by this so they come out at the intended pixel size.
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local MAX_RECENT = 12

-- ---------------------------------------------------------------------------
-- FitText -- one line of text in a fixed box, shrunk until it fits
-- ---------------------------------------------------------------------------

local FitText = Widget:extend{
    width    = 100,
    height   = 40,
    text     = "",
    max_size = 30,    -- points, as for Font:getFace
    min_size = 10,
    bold     = false,
    align    = "right",
    font     = "cfont",
}

function FitText:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function FitText:setText(text)
    if text ~= self.text then
        self.text = text
        self._face = nil
    end
end

function FitText:_fit()
    if self._face then return self._face, self._m end
    local size = self.max_size
    local face, m
    while true do
        face = Font:getFace(self.font, size)
        m = RenderText:sizeUtf8Text(0, self.width * 10, face, self.text, true, self.bold)
        if size <= self.min_size or (m.x <= self.width and m.y_top + m.y_bottom <= self.height) then
            break
        end
        size = size - 1
    end
    self._face, self._m = face, m
    return face, m
end

function FitText:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    if self.text == "" then return end
    local face, m = self:_fit()
    local tx = x
    if self.align == "right" then tx = x + self.width - m.x
    elseif self.align == "center" then tx = x + math.floor((self.width - m.x) / 2) end
    local ty = y + math.floor(self.height / 2 + (m.y_top - m.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, math.max(x, tx), ty, face, self.text, true, self.bold,
                              Blitbuffer.COLOR_BLACK, self.width)
end

-- ---------------------------------------------------------------------------
-- UnitTable -- the value in every unit, as many columns as fit
-- ---------------------------------------------------------------------------

local UnitTable = InputContainer:extend{
    width  = 100,
    height = 100,
    cells  = nil,      -- { { id, label, value, bold }, ... }
    on_tap = nil,      -- function(id)
}

function UnitTable:init()
    self.cells = self.cells or {}
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapUnitTable = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function UnitTable:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function UnitTable:setCells(cells)
    self.cells = cells
    self._layout = nil
end

local CELL_PAD = Size.padding.default
local CELL_GAP = Size.padding.large
local MAX_COL_W = DeviceScreen:scaleBySize(260)

-- Largest font at which every cell fits a column: { face, bold_face, line_h,
-- rows, cols, col_w }.
function UnitTable:_computeLayout()
    if self._layout then return self._layout end
    local n = #self.cells
    local best
    local function fitsIn(face, col_w)
        for _i, c in ipairs(self.cells) do
            local lw = RenderText:sizeUtf8Text(0, 9999, face, c.label, true, true).x
            local vw = RenderText:sizeUtf8Text(0, 9999, face, c.value, true, true).x
            if lw + CELL_GAP + vw > col_w - 2 * CELL_PAD then return false end
        end
        return true
    end
    for size = 19, 11, -1 do
        local face = Font:getFace("cfont", size)
        local line_h = math.floor(face.size * 1.55)
        local max_rows = math.max(1, math.floor(self.height / line_h))
        local needed = math.max(1, math.ceil(n / max_rows))
        -- Prefer more columns (a label stays close to its value), down to
        -- the fewest that still hold every row.
        local pref = math.max(needed, math.min(n, math.floor(self.width / MAX_COL_W)))
        for cols = pref, needed, -1 do
            local col_w = math.floor(self.width / cols)
            local L = { face = face, line_h = line_h, rows = math.ceil(n / cols), cols = cols, col_w = col_w }
            best = best or L
            if fitsIn(face, col_w) then best = L; break end
            best = L
        end
        if fitsIn(best.face, best.col_w) then break end
    end
    self._layout = best
    return best
end

function UnitTable:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    if #self.cells == 0 then return end
    local L = self:_computeLayout()
    local face = L.face
    local probe = RenderText:sizeUtf8Text(0, 9999, face, "0Ag", true, false)
    local base_off = math.floor(L.line_h / 2 + (probe.y_top - probe.y_bottom) / 2)
    for i, c in ipairs(self.cells) do
        local col = math.floor((i - 1) / L.rows)
        local row = (i - 1) % L.rows
        local cx = x + col * L.col_w
        local cy = y + row * L.line_h
        if c.bold then
            bb:paintRect(cx + 1, cy + 1, L.col_w - 2, L.line_h - 2, Blitbuffer.COLOR_LIGHT_GRAY)
        end
        local ty = cy + base_off
        local avail = L.col_w - 2 * CELL_PAD
        local vm = RenderText:sizeUtf8Text(0, avail, face, c.value, true, c.bold)
        RenderText:renderUtf8Text(bb, cx + CELL_PAD, ty, face, c.label, true, c.bold,
                                  Blitbuffer.COLOR_BLACK, math.max(0, avail - vm.x - CELL_GAP))
        RenderText:renderUtf8Text(bb, cx + L.col_w - CELL_PAD - vm.x, ty, face, c.value, true, c.bold,
                                  Blitbuffer.COLOR_BLACK, avail)
        if col > 0 and row == 0 then
            bb:paintRect(cx, y, Size.line.thin, math.min(self.height, L.rows * L.line_h),
                         Blitbuffer.COLOR_DARK_GRAY)
        end
    end
end

function UnitTable:onTapUnitTable(_arg, ges)
    if not self.on_tap or #self.cells == 0 then return false end
    local L = self:_computeLayout()
    local col = math.floor((ges.pos.x - self.dimen.x) / L.col_w)
    local row = math.floor((ges.pos.y - self.dimen.y) / L.line_h)
    if row < 0 or row >= L.rows or col < 0 then return true end
    local c = self.cells[col * L.rows + row + 1]
    if c then self.on_tap(c.id) end
    return true
end

-- ---------------------------------------------------------------------------
-- Help
-- ---------------------------------------------------------------------------

local HELP_EN = [[
Unit converter — Help

Pick a category with the top-left button, then the unit to convert from and the unit to convert to. ⇄ swaps them. Type the value on the keypad: the result and the value in every unit of the category update as you type. Tap a line of the table to make that unit the target.

Your category, units and values are remembered. ☰ → Recent conversions brings back the last ones; ☰ → Favourites keeps the pairs you use often.

CATEGORIES
Length, mass, volume, temperature, area, speed, duration, fuel consumption, energy, pressure, data size (SI kB/MB/GB and binary KiB/MiB/GiB) and angle use the exact definitions (SI Brochure, NIST SP 811). Month and year are calendar averages.

Cooking converts spoons, cups and fluid ounces to grams for one ingredient, picked with the second button. Weights per cup come from the King Arthur Baking ingredient weight chart and the USDA; measuring by volume is approximate by nature. "Tablespoon (15 ml)" and "Teaspoon (5 ml)" are the metric spoons of European recipes; the US ones are slightly smaller.

Oven temperature converts °C, °F, gas mark and the French thermostat (th. 6 = 180 °C), rounded as an oven dial shows them.

Currency uses the euro reference rates of the European Central Bank, shown with their date. They come with the plugin and are updated on request: ☰ → Update exchange rates, or tap the rate date (needs Wi-Fi). The ECB publishes them for information only: banks and card payments use other rates.

Time zones shows the time in about fifty cities, daylight saving time included. Type a time to convert it, or leave it empty for now. If your reader's clock does not know its time zone, set ☰ → My time zone to your city.

Roman numerals (1 to 3999) and number bases (binary, octal, decimal, hexadecimal) convert whole numbers.
]]

local HELP_FR = [[
Convertisseur — Aide

Choisissez une catégorie avec le bouton en haut à gauche, puis l'unité de départ et l'unité d'arrivée. ⇄ les échange. Tapez la valeur sur le pavé : le résultat et la valeur dans toutes les unités de la catégorie se mettent à jour au fil de la saisie. Touchez une ligne du tableau pour en faire l'unité d'arrivée.

La catégorie, les unités et les valeurs sont mémorisées. ☰ → Conversions récentes rappelle les dernières ; ☰ → Favoris garde les paires que vous utilisez souvent.

CATÉGORIES
Longueur, masse, volume, température, surface, vitesse, durée, consommation, énergie, pression, taille de données (ko/Mo/Go du SI et Kio/Mio/Gio binaires) et angle utilisent les définitions exactes (Brochure SI, NIST SP 811). Le mois et l'année sont des moyennes du calendrier.

Cuisine convertit cuillères, tasses et onces liquides en grammes pour un ingrédient, choisi avec le deuxième bouton. Les poids par tasse viennent du tableau de King Arthur Baking et de l'USDA ; mesurer au volume reste approximatif. « Cuillère à soupe (15 ml) » et « Cuillère à café (5 ml) » sont les cuillères des recettes françaises ; les cuillères américaines sont un peu plus petites.

Température du four convertit °C, °F, gas mark britannique et thermostat (th. 6 = 180 °C), arrondis comme sur un bouton de four.

Devises utilise les cours de référence de l'euro de la Banque centrale européenne, affichés avec leur date. Ils sont fournis avec l'extension et mis à jour à la demande : ☰ → Mettre à jour les cours, ou touchez la date des cours (Wi-Fi nécessaire). La BCE les publie à titre indicatif : banques et paiements par carte appliquent d'autres cours.

Fuseaux horaires donne l'heure dans une cinquantaine de villes, heure d'été comprise. Tapez une heure pour la convertir, ou laissez vide pour l'heure actuelle. Si l'horloge de la liseuse ne connaît pas son fuseau, réglez ☰ → Mon fuseau horaire sur votre ville.

Chiffres romains (1 à 3999) et bases (binaire, octal, décimal, hexadécimal) convertissent les nombres entiers.
]]

-- ---------------------------------------------------------------------------
-- ConverterScreen
-- ---------------------------------------------------------------------------

local ConverterScreen = ScreenBase:extend{
    vertical_align = "top",
}

function ConverterScreen:init()
    self.catalog = Catalog.new(lrequire)
    local st = self.plugin:loadState()
    self.state = type(st) == "table" and st or {}
    self.state.sel = type(self.state.sel) == "table" and self.state.sel or {}
    if not Catalog.LABELS[self.state.cat or ""] then self.state.cat = "length" end
    self.lang = _.lang and _.lang() or "en"
    self.dec, self.group = NumFmt.separators(self.lang)
    ScreenBase.init(self)
end

function ConverterScreen:serializeState()
    self:pushRecent()
    return self.state
end

-- ---------------------------------------------------------------------------
-- Model helpers
-- ---------------------------------------------------------------------------

function ConverterScreen:getCat()
    local cat = self.catalog:get(self.state.cat)
    if cat.kind == "currency" and not self._rates then
        local Currency = cat.Currency
        self._rates = Currency.pick(self.plugin:getSetting("rates"))
        cat.setRates(self._rates.rates)
    end
    return cat
end

function ConverterScreen:getSel()
    local cat = self:getCat()
    local s = self.state.sel[cat.id]
    if type(s) ~= "table" then
        s = { input = cat.kind == "clock" and "" or "1" }
        self.state.sel[cat.id] = s
    end
    s.from = Catalog.validUnit(cat, s.from, cat.default_from)
    s.to   = Catalog.validUnit(cat, s.to, cat.default_to)
    if type(s.input) ~= "string" then s.input = "" end
    return s, cat
end

function ConverterScreen:ctx()
    return {
        ingredient = self.state.ingredient or "flour",
        rates      = self._rates and self._rates.rates,
    }
end

function ConverterScreen:fmt(sig)
    return { dec = self.dec, group = self.group, sig = sig }
end

function ConverterScreen:unitOf(cat, id)
    return Catalog.findUnit(cat.units, id)
end

function ConverterScreen:homeCity(TZ)
    local id = self.plugin:getSetting("home_tz")
    return id and TZ.city(id) or nil
end

-- Name of a unit as shown on its button and in pickers.
function ConverterScreen:unitName(cat, u)
    if cat.kind == "clock" and u.id == "here" then
        local home = self:homeCity(cat.TZ)
        return home and T(_("My time (%1)"), _(home.name)) or _("My time")
    end
    if cat.kind == "currency" then return u.id .. " · " .. _(u.name) end
    return _(u.name)
end

function ConverterScreen:symOf(cat, id)
    local u = self:unitOf(cat, id)
    return u.sym or ""
end

local function withSym(v, sym)
    if sym == nil or sym == "" then return v end
    if v == "—" then return v end
    -- Degrees and minutes of arc stick to the number.
    if sym == "°" or sym == "′" or sym == "″" then return v .. sym end
    -- Oven settings read "th. 6" and "gas 4".
    if sym == "th." or sym == "gas" then return sym .. "\u{00A0}" .. v end
    return v .. "\u{00A0}" .. sym
end

function ConverterScreen:formatDate(iso)
    local y, m, d = (iso or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    if not y then return iso or "?" end
    if self.lang == "en" then return iso end
    return d .. "/" .. m .. "/" .. y
end

-- The value typed, as a number in the "from" unit (empty decimal input
-- counts as 0; the other keypads need something typed).
function ConverterScreen:inputValue(cat, s)
    local x = cat.parse(s.input, s.from)
    if x == nil and cat.keyset(s.from) == "decimal" then x = 0 end
    return x
end

-- ---------------------------------------------------------------------------
-- What the display shows: { input, result, info, cells }
-- ---------------------------------------------------------------------------

function ConverterScreen:computeClock(cat, s)
    local TZ = cat.TZ
    local now = os.time()
    local dev_off = TZ.deviceOffset(now)
    local home = self:homeCity(TZ)
    local now_utc, here_off = now, dev_off
    if home then now_utc = TZ.wallToUtc(home, now + dev_off) end
    local function city(id)
        if id == "here" then return home end
        return TZ.city(id)
    end
    local function hm(h, m) return string.format("%02d:%02d", h, m) end
    local mins = cat.parse(s.input)
    local fc, tc = city(s.from), city(s.to)
    local r = TZ.convert(fc, tc, now_utc, mins, here_off)
    local out = {}
    if mins then
        out.input = hm(r.from_h, r.from_m)
    else
        out.input = T(_("Now: %1"), hm(r.from_h, r.from_m))
    end
    local shift = ""
    if r.day_shift > 0 then shift = " " .. _("(next day)")
    elseif r.day_shift < 0 then shift = " " .. _("(previous day)") end
    out.result = hm(r.to_h, r.to_m) .. shift
    local diff = (r.to_off - r.from_off)
    out.info = T(_("UTC%1 → UTC%2 · difference %3 h"),
        TZ.formatOffset(r.from_off), TZ.formatOffset(r.to_off), TZ.formatOffset(diff))
    -- Every city at that instant, west to east.
    local cells = {}
    local _y, _m, _d, _h, _mi, from_days = TZ.fields(r.utc + r.from_off)
    for _i, u in ipairs(cat.units) do
        if u.id ~= "here" then
            local c = TZ.city(u.id)
            local off = TZ.offset(c, r.utc)
            local _y2, _m2, _d2, h, mi, days = TZ.fields(r.utc + off)
            local mark = days > from_days and " +1" or (days < from_days and " −1" or "")
            cells[#cells + 1] = { id = u.id, label = _(c.name), value = hm(h, mi) .. mark,
                                  bold = u.id == s.to or u.id == s.from, off = off }
        end
    end
    table.sort(cells, function(a, b)
        if a.off ~= b.off then return a.off < b.off end
        return a.label < b.label
    end)
    out.cells = cells
    return out
end

function ConverterScreen:compute()
    local s, cat = self:getSel()
    if cat.kind == "clock" then return self:computeClock(cat, s) end
    local ctx = self:ctx()
    local out = {}
    local keyset = cat.keyset(s.from)
    local from_sym, to_sym = self:symOf(cat, s.from), self:symOf(cat, s.to)
    if keyset == "decimal" then
        out.input = withSym(NumFmt.displayInput(s.input, self.dec), from_sym)
    else
        local raw = s.input ~= "" and s.input or "…"
        if cat.kind == "bases" and s.input ~= "" then
            raw = lrequire("numtools").groupDigits(s.input, ({ bin = 2, oct = 8, dec = 10, hex = 16 })[s.from], " ")
        end
        out.input = withSym(raw, cat.kind == "bases" and from_sym or "")
    end
    local x = self:inputValue(cat, s)
    local function fmtValue(id, sig)
        if x == nil then return "—" end
        local y = cat.convert(x, s.from, id, ctx)
        if y == nil then return "—" end
        return cat.format(y, id, self:fmt(sig)) or "—"
    end
    out.result = withSym(fmtValue(s.to, NumFmt.SIG), cat.kind == "roman" and "" or to_sym)

    -- Info line
    if cat.kind == "number" or cat.kind == "cooking" or cat.kind == "currency" then
        local one = cat.convert(1, s.to, s.from, ctx)
        local rel = one and T("1 %1 = %2", to_sym,
            withSym(cat.kind == "currency" and NumFmt.format(one, self:fmt(5))
                    or cat.format(one, s.from, self:fmt(7)), from_sym)) or ""
        if cat.kind == "cooking" then
            local Cooking = cat.Cooking
            local ing = Cooking.ingredient(ctx.ingredient)
            local g = Cooking.convert(1, self:unitOf(cat, "cupus"), self:unitOf(cat, "g"), ing.id)
            out.info = T(_("%1: 1 cup US = %2 g"), _(ing.name), NumFmt.format(g, self:fmt(3)))
        elseif cat.kind == "currency" then
            out.info = T(_("ECB rates of %1"), self:formatDate(self._rates.date)) .. " · " .. rel
        elseif s.from ~= s.to and cat.id ~= "temperature" and cat.id ~= "fuel" then
            -- (an offset scale or an inverse makes "1 °F = −17.2 °C" true
            -- but useless, so those two show nothing)
            out.info = rel
        else
            out.info = ""
        end
    elseif cat.kind == "oven" then
        out.info = _("Thermostat × 30 = °C. Rounded as on an oven dial.")
    elseif cat.kind == "roman" then
        if s.input ~= "" and x == nil then out.info = _("Not a complete numeral yet.")
        else out.info = _("Whole numbers from 1 to 3999.") end
    elseif cat.kind == "bases" then
        out.info = _("Whole numbers from 0 to 2⁵³.")
    end

    -- A kitchen needs no more than 3 significant digits (70,9765 tsp → 71).
    local table_sig = cat.kind == "cooking" and 3 or NumFmt.SIG_TABLE
    local cells = {}
    for _i, u in ipairs(cat.units) do
        local label = (u.sym and u.sym ~= "") and u.sym or _(u.name)
        cells[#cells + 1] = { id = u.id, label = label, value = fmtValue(u.id, table_sig),
                              bold = u.id == s.to or u.id == s.from }
    end
    out.cells = cells
    return out
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local KEY_FONT = 24

function ConverterScreen:keyRows(cat, s)
    local h = DeviceScreen:scaleBySize(52)
    local function key(label, k, opts)
        local b = { text = label, font_size = KEY_FONT, font_bold = true, height = h,
                    callback = function() self:onKey(k) end }
        if opts then for kk, v in pairs(opts) do b[kk] = v end end
        return b
    end
    local function keys(list)
        local row = {}
        for _i, k in ipairs(list) do row[#row + 1] = key(k, k) end
        return row
    end
    local clear = key(_("Clear"), "C", { font_size = 18 })
    local back = key("⌫", "⌫")
    local ks = cat.keyset(s.from)
    if ks == "decimal" then
        return {
            keys({ "1", "2", "3", "4", "5" }),
            keys({ "6", "7", "8", "9", "0" }),
            { key(self.dec, "."), key("±", "±"), back, clear },
        }
    elseif ks == "clock" then
        return {
            keys({ "1", "2", "3", "4", "5" }),
            keys({ "6", "7", "8", "9", "0" }),
            { key(_("Now"), "C", { font_size = 18 }), back },
        }
    elseif ks == "roman" then
        return { keys({ "I", "V", "X", "L" }), keys({ "C", "D", "M" }), { back, clear } }
    elseif ks == "base2" then
        return { keys({ "0", "1" }), { back, clear } }
    elseif ks == "base8" then
        return { keys({ "0", "1", "2", "3" }), keys({ "4", "5", "6", "7" }), { back, clear } }
    elseif ks == "base16" then
        return { keys({ "0", "1", "2", "3", "4", "5", "6", "7" }),
                 keys({ "8", "9", "A", "B", "C", "D", "E", "F" }), { back, clear } }
    end
    return {
        keys({ "1", "2", "3", "4", "5" }),
        keys({ "6", "7", "8", "9", "0" }),
        { back, clear },
    }
end

-- Second button of the top row, or nil.
function ConverterScreen:extraButton(cat)
    if cat.kind == "cooking" then
        local ing = cat.Cooking.ingredient(self.state.ingredient)
        return { text = _(ing.name) .. " ▾", callback = function() self:pickIngredient() end }
    elseif cat.kind == "currency" then
        return { text = T(_("Rates: %1"), self:formatDate(self._rates.date)) .. " ⟳",
                 callback = function() self:updateRates() end }
    elseif cat.kind == "clock" then
        return { text = _("My time zone") .. " ▾", callback = function() self:pickHomeZone() end }
    end
    return nil
end

function ConverterScreen:buildLayout()
    local s, cat = self:getSel()
    local land = self:isLandscape()
    local sw, sh = self.dimen.w, self.dimen.h
    local g = self:getGutter()

    local title_bar = self:buildTitleBar(_("Unit converter"), function() return self:menuItems() end)

    local cw = land and math.floor((sw - 3 * g) * 0.5) or (sw - 2 * g)

    -- Selectors
    local row_a = { { text = _(Catalog.LABELS[cat.id]) .. " ▾", callback = function() self:pickCategory() end } }
    local extra = self:extraButton(cat)
    if extra then row_a[2] = extra end
    local swap_w = DeviceScreen:scaleBySize(56)
    local row_b = {
        { text = self:unitName(cat, self:unitOf(cat, s.from)), callback = function() self:pickUnit("from") end },
        { text = "⇄", width = swap_w, font_size = 26, font_bold = true, callback = function() self:onSwap() end },
        { text = self:unitName(cat, self:unitOf(cat, s.to)), callback = function() self:pickUnit("to") end },
    }
    local selectors = ButtonTable:new{ width = cw, buttons = { row_a, row_b } }

    -- Display
    local frame_pad = Size.padding.default
    local inner_w = cw - 2 * (frame_pad + Size.border.window) - 2 * Size.padding.large
    local in_h = DeviceScreen:scaleBySize(36)
    local out_h = DeviceScreen:scaleBySize(48)
    self.in_text = FitText:new{ width = inner_w, height = in_h, max_size = 24, bold = false }
    self.out_text = FitText:new{ width = inner_w, height = out_h, max_size = 34, bold = true }
    local display = FrameContainer:new{
        bordersize = Size.border.window,
        padding = frame_pad,
        padding_left = frame_pad + Size.padding.large,
        padding_right = frame_pad + Size.padding.large,
        radius = Size.radius.window,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "right", self.in_text, self.out_text },
    }
    local info_h = DeviceScreen:scaleBySize(26)
    self.info_text = FitText:new{ width = cw, height = info_h, max_size = 16, min_size = 9,
                                  align = "center", font = "smallinfofont" }

    local keypad = ButtonTable:new{ width = cw, buttons = self:keyRows(cat, s), zero_sep = true }
    local span = VerticalSpan:new{ width = math.floor(g / 2) }

    local tb_h = title_bar:getSize().h
    if land then
        local left = VerticalGroup:new{
            align = "center",
            selectors, span, display, span, self.info_text, span, keypad,
        }
        local table_w = sw - cw - 3 * g
        local table_h = sh - tb_h - 2 * g
        local left_pad = math.max(0, math.floor((table_h - left:getSize().h) / 2))
        left = VerticalGroup:new{ align = "center", VerticalSpan:new{ width = left_pad }, left }
        self.unit_table = UnitTable:new{ width = table_w, height = table_h,
                                         on_tap = function(id) self:onTableTap(id) end }
        self.layout = VerticalGroup:new{
            align = "left",
            title_bar,
            VerticalSpan:new{ width = g },
            HorizontalGroup:new{
                align = "top",
                HorizontalSpan:new{ width = g }, left,
                HorizontalSpan:new{ width = g }, self.unit_table,
            },
        }
    else
        local used = tb_h + selectors:getSize().h + display:getSize().h + info_h
                     + keypad:getSize().h + 5 * math.floor(g / 2) + g
        local table_h = math.max(DeviceScreen:scaleBySize(60), sh - used)
        self.unit_table = UnitTable:new{ width = cw, height = table_h,
                                         on_tap = function(id) self:onTableTap(id) end }
        self.layout = VerticalGroup:new{
            align = "center",
            title_bar, span, selectors, span, display, span, self.info_text, span,
            self.unit_table, span, keypad,
        }
    end
    self[1] = self.layout
    self:fillValues()
end

function ConverterScreen:fillValues()
    local out = self:compute()
    self.in_text:setText(out.input or "")
    self.out_text:setText(out.result or "")
    self.info_text:setText(self._message or out.info or "")
    self._message = nil
    self.unit_table:setCells(out.cells or {})
end

-- Repaint only what a key press changes.
function ConverterScreen:refreshValues()
    self:fillValues()
    UIManager:setDirty(self, function()
        local r
        for _i, w in ipairs({ self.in_text, self.out_text, self.info_text, self.unit_table }) do
            if w.dimen then r = r and r:combine(w.dimen) or w.dimen:copy() end
        end
        return "ui", r or self.dimen
    end)
end

function ConverterScreen:rebuild()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- The info line shows a message until the next change.
function ConverterScreen:updateStatus(msg)
    self._message = msg
    if self.info_text then self:refreshValues() end
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function ConverterScreen:onKey(k)
    local s, cat = self:getSel()
    s.input = cat.press(s.input, k, s.from)
    self:refreshValues()
end

-- The typed value written in another unit of the same category, for the
-- keypads whose input is not a plain decimal (Roman, bases).
function ConverterScreen:reexpress(cat, s, new_from)
    if cat.kind ~= "roman" and cat.kind ~= "bases" then return s.input end
    local x = cat.parse(s.input, s.from)
    if x == nil then return "" end
    local raw = cat.format(x, new_from, { group = "" })
    return (raw and raw ~= "—") and raw or ""
end

function ConverterScreen:onSwap()
    local s, cat = self:getSel()
    s.input = self:reexpress(cat, s, s.to)
    s.from, s.to = s.to, s.from
    self:rebuild()
end

function ConverterScreen:setUnit(which, id)
    local s, cat = self:getSel()
    if which == "from" then
        if id == s.from then return end
        self:pushRecent()
        if id == s.to then s.to = s.from end
        s.input = self:reexpress(cat, s, id)
        s.from = id
    else
        if id == s.to then return end
        self:pushRecent()
        if id == s.from then
            s.input = self:reexpress(cat, s, s.to)
            s.from = s.to
        end
        s.to = id
    end
    self:rebuild()
end

function ConverterScreen:onTableTap(id)
    self:setUnit("to", id)
end

function ConverterScreen:pickUnit(which)
    local s, cat = self:getSel()
    local items = {}
    for _i, u in ipairs(cat.units) do
        local name = self:unitName(cat, u)
        if u.sym and u.sym ~= "" and cat.kind ~= "currency" and cat.kind ~= "bases" then
            name = name .. " (" .. u.sym .. ")"
        end
        if cat.kind == "clock" and u.id ~= "here" then
            name = name .. "  UTC" .. cat.TZ.formatOffset(cat.TZ.offset(cat.TZ.city(u.id), os.time()))
        end
        items[#items + 1] = { id = u.id, text = name }
    end
    MenuHelper.openPickerMenu{
        title = which == "from" and _("Convert from") or _("Convert to"),
        items = items,
        current_id = which == "from" and s.from or s.to,
        width_ratio = 0.9,
        on_select = function(id) self:setUnit(which, id) end,
    }
end

function ConverterScreen:setCategory(id)
    if id == self.state.cat then return end
    self:pushRecent()
    self.state.cat = id
    self:rebuild()
end

function ConverterScreen:pickCategory()
    local dlg
    local rows, row = {}, {}
    for _i, id in ipairs(Catalog.ORDER) do
        local label = _(Catalog.LABELS[id])
        if id == self.state.cat then label = "✓ " .. label end
        row[#row + 1] = { text = label, callback = function()
            UIManager:close(dlg)
            self:setCategory(id)
        end }
        if #row == 2 then rows[#rows + 1] = row; row = {} end
    end
    if #row > 0 then rows[#rows + 1] = row end
    dlg = ButtonDialog:new{ title = _("Category"), buttons = rows,
                            width = math.floor(math.min(self.dimen.w, self.dimen.h) * 0.95) }
    UIManager:show(dlg)
end

function ConverterScreen:pickIngredient()
    local cat = self:getCat()
    local items = {}
    for _i, ing in ipairs(cat.Cooking.INGREDIENTS) do
        items[#items + 1] = { id = ing.id, text = _(ing.name) }
    end
    MenuHelper.openPickerMenu{
        title = _("Ingredient"),
        items = items,
        current_id = self.state.ingredient or "flour",
        width_ratio = 0.9,
        on_select = function(id)
            self.state.ingredient = id
            self:rebuild()
        end,
    }
end

function ConverterScreen:pickHomeZone()
    local TZ = self.catalog:get("timezone").TZ
    local items = { { id = "auto", text = _("Automatic (reader's clock)") } }
    local cities = {}
    for _i, c in ipairs(TZ.CITIES) do cities[#cities + 1] = { id = c.id, text = _(c.name) } end
    table.sort(cities, function(a, b) return a.text < b.text end)
    for _i, c in ipairs(cities) do items[#items + 1] = c end
    MenuHelper.openPickerMenu{
        title = _("My time zone"),
        items = items,
        current_id = self.plugin:getSetting("home_tz") or "auto",
        width_ratio = 0.9,
        on_select = function(id)
            self.plugin:saveSetting("home_tz", id ~= "auto" and id or nil)
            if self.state.cat == "timezone" then self:rebuild() end
        end,
    }
end

function ConverterScreen:homeZoneName()
    local id = self.plugin:getSetting("home_tz")
    local c = id and lrequire("timezones").city(id)
    return c and _(c.name) or _("Automatic")
end

-- ---------------------------------------------------------------------------
-- Recent conversions and favourites
-- ---------------------------------------------------------------------------

function ConverterScreen:describe(e, with_value)
    local cat = self.catalog:get(e.cat)
    if not cat then return "?" end
    if cat.kind == "currency" and not self._rates then self:getCat() end
    local function nm(id)
        local u = Catalog.findUnit(cat.units, id)
        if cat.kind == "clock" then return self:unitName(cat, u) end
        return (u.sym and u.sym ~= "") and u.sym or _(u.name)
    end
    local label = _(Catalog.LABELS[e.cat])
    if not with_value then
        return T(_("%1: %2 → %3"), label, nm(e.from), nm(e.to))
    end
    local v = e.input
    if cat.keyset(e.from) == "decimal" then v = NumFmt.displayInput(v, self.dec)
    elseif cat.kind == "clock" then v = Catalog.displayClock(v) or _("now") end
    return T(_("%1: %2 %3 → %4"), label, v, nm(e.from), nm(e.to))
end

function ConverterScreen:pushRecent()
    local s, cat = self:getSel()
    if s.input == "" and cat.kind ~= "clock" then return end
    local e = { cat = cat.id, from = s.from, to = s.to, input = s.input }
    local list = self.plugin:getSetting("recent", {})
    if type(list) ~= "table" then list = {} end
    local out = { e }
    for _i, r in ipairs(list) do
        if type(r) == "table" and not (r.cat == e.cat and r.from == e.from and r.to == e.to and r.input == e.input)
           and #out < MAX_RECENT then
            out[#out + 1] = r
        end
    end
    local top = list[1]
    if top and top.cat == e.cat and top.from == e.from and top.to == e.to and top.input == e.input then
        return
    end
    self.plugin:saveSetting("recent", out)
end

function ConverterScreen:restore(e)
    if type(e) ~= "table" or not Catalog.LABELS[e.cat or ""] then return end
    self.state.cat = e.cat
    self.state.sel[e.cat] = { from = e.from, to = e.to, input = e.input or "" }
    self:rebuild()
end

function ConverterScreen:showRecent()
    self:pushRecent()
    local list = self.plugin:getSetting("recent", {})
    if type(list) ~= "table" or #list == 0 then
        self:showMessage(_("No recent conversions yet."), 2)
        return
    end
    local items = {}
    for i, e in ipairs(list) do items[#items + 1] = { id = i, text = self:describe(e, true) } end
    MenuHelper.openPickerMenu{
        title = _("Recent conversions"),
        items = items,
        width_ratio = 0.95,
        on_select = function(i) self:restore(list[i]) end,
    }
end

function ConverterScreen:showFavourites()
    local s, cat = self:getSel()
    local favs = self.plugin:getSetting("favourites", {})
    if type(favs) ~= "table" then favs = {} end
    local here
    for i, f in ipairs(favs) do
        if f.cat == cat.id and f.from == s.from and f.to == s.to then here = i end
    end
    local current = { cat = cat.id, from = s.from, to = s.to }
    local items = {}
    if here then
        items[1] = { id = "toggle", text = T(_("Remove %1"), self:describe(current)) }
    else
        items[1] = { id = "toggle", text = T(_("Add %1"), self:describe(current)) }
    end
    for i, f in ipairs(favs) do items[#items + 1] = { id = i, text = "★ " .. self:describe(f) } end
    MenuHelper.openPickerMenu{
        title = _("Favourites"),
        items = items,
        width_ratio = 0.95,
        on_select = function(id)
            if id == "toggle" then
                if here then table.remove(favs, here) else table.insert(favs, 1, current) end
                self.plugin:saveSetting("favourites", favs)
                self:updateStatus(here and _("Removed from favourites.") or _("Added to favourites."))
                return
            end
            local f = favs[id]
            if not f then return end
            local sel = self.state.sel[f.cat]
            self:restore({ cat = f.cat, from = f.from, to = f.to,
                           input = type(sel) == "table" and sel.input or "1" })
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Exchange rates
-- ---------------------------------------------------------------------------

local function fetchUrl(url)
    local ok1, https = pcall(require, "ssl.https")
    local ok2, ltn12 = pcall(require, "ltn12")
    if not ok1 or not ok2 then return nil, "no https" end
    local ok3, su = pcall(require, "socketutil")
    if not ok3 or type(su) ~= "table" or not su.set_timeout then su = nil end
    local chunks = {}
    if su then su:set_timeout(10, 30) end
    local ok, result, status = pcall(https.request, {
        url      = url,
        sink     = su and su.table_sink and su.table_sink(chunks) or ltn12.sink.table(chunks),
        verify   = "none",
        protocol = "tlsv1_2",
    })
    if su then su:reset_timeout() end
    if not ok then return nil, tostring(result) end
    if not result or status ~= 200 then return nil, "HTTP " .. tostring(status or "?") end
    return table.concat(chunks)
end

function ConverterScreen:doUpdateRates()
    local cat = self.catalog:get("currency")
    if not self._rates then
        self._rates = cat.Currency.pick(self.plugin:getSetting("rates"))
        cat.setRates(self._rates.rates)
    end
    local msg = InfoMessage:new{ text = _("Downloading exchange rates…"), dismissable = false }
    UIManager:show(msg)
    UIManager:forceRePaint()
    local body, err = fetchUrl(cat.Currency.URL)
    UIManager:close(msg)
    local t, perr
    if body then t, perr = cat.Currency.parse(body) end
    if not t then
        self:showMessage(T(_("Could not update the exchange rates (%1). Still using those of %2."),
            err or perr or "?", self:formatDate(self._rates.date)), 5)
        return
    end
    self.plugin:saveSetting("rates", { date = t.date, rates = t.rates, fetched = os.time() })
    self._rates = cat.Currency.pick(t)
    cat.setRates(self._rates.rates)
    if self.state.cat == "currency" then self:rebuild() end
    self:showMessage(T(_("Exchange rates of %1 loaded."), self:formatDate(t.date)), 3)
end

function ConverterScreen:updateRates()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and NetworkMgr and NetworkMgr.runWhenOnline then
        -- Turns Wi-Fi on (or asks to) first when it is off, as the fleet's
        -- other network features do.
        NetworkMgr:runWhenOnline(function() self:doUpdateRates() end)
    else
        self:doUpdateRates()
    end
end

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------

function ConverterScreen:menuItems()
    return {
        { text = _("Category"), callback = function() self:pickCategory() end },
        { text = _("Recent conversions"), callback = function() self:showRecent() end },
        { text = _("Favourites"), callback = function() self:showFavourites() end },
        { text = _("Update exchange rates"), callback = function() self:updateRates() end },
        { text = T(_("My time zone: %1"), self:homeZoneName()), callback = function() self:pickHomeZone() end },
        { text = _("Help"), callback = function()
            self:showRules(self.lang == "fr" and HELP_FR or HELP_EN, { title = _("Help") })
        end },
    }
end

return ConverterScreen
