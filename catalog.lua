-- catalog.lua -- the categories of the converter, behind one interface.
--
-- Pure Lua (specced in test_catalog_spec.lua). Each data module is loaded
-- only when its category is first opened, through the `load` function the
-- caller passes to Catalog.new (main.lua's lrequire; plain require in specs).
--
-- A category is:
--   id, kind      "number" | "cooking" | "oven" | "currency" | "roman" |
--                 "bases" | "clock"
--   units         list of { id, name, sym }
--   default_from, default_to
--   keyset(from)  "decimal" | "roman" | "base2" | "base8" | "base10" |
--                 "base16" | "clock" -- which keypad to show
--   press(buf, key, from)   the input buffer after a key
--   parse(buf, from)        the typed value, or nil
--   convert(x, from, to, ctx)  (not for "clock", see screen.lua)
--   format(y, to, fmt)      fmt = { dec, group, sig }
-- ctx = { ingredient = id, rates = { CODE = rate } }.

local Catalog = {}
Catalog.__index = Catalog

Catalog.ORDER = {
    "length", "mass", "volume", "temperature", "area", "speed", "time",
    "cooking", "oven", "currency", "timezone", "fuel", "energy",
    "pressure", "data", "angle", "roman", "bases",
}

Catalog.LABELS = {
    length = "Length", mass = "Mass", volume = "Volume",
    temperature = "Temperature", area = "Area", speed = "Speed",
    time = "Duration", cooking = "Cooking", oven = "Oven temperature",
    currency = "Currency", timezone = "Time zones",
    fuel = "Fuel consumption", energy = "Energy", pressure = "Pressure",
    data = "Data size", angle = "Angle", roman = "Roman numerals",
    bases = "Number bases",
}

function Catalog.new(load)
    return setmetatable({ load = load or require, cache = {} }, Catalog)
end

local function findUnit(units, id)
    for _i, u in ipairs(units) do if u.id == id then return u end end
    return units[1]
end
Catalog.findUnit = findUnit

-- ---------------------------------------------------------------------------
-- Input buffers for the non-decimal keypads
-- ---------------------------------------------------------------------------

-- Clock: up to four digits, read as H, HH, HMM or HHMM.
function Catalog.pressClock(buf, key)
    buf = buf or ""
    if key == "C" then return "" end
    if key == "⌫" then return buf:sub(1, -2) end
    if not key:match("^%d$") or #buf >= 4 then return buf end
    local nb = buf .. key
    -- Refuse a key that cannot lead to a valid time.
    if #nb == 2 and tonumber(nb) > 23 and tonumber(nb:sub(2, 2)) > 5 then return buf end
    if #nb == 3 and Catalog.parseClock(nb) == nil then return buf end
    if #nb == 4 and Catalog.parseClock(nb) == nil then return buf end
    return nb
end

-- Minutes after midnight, or nil (nothing typed or not a time).
function Catalog.parseClock(buf)
    if not buf or buf == "" then return nil end
    local h, m
    if #buf <= 2 then
        h, m = tonumber(buf), 0
    elseif #buf == 3 then
        h, m = tonumber(buf:sub(1, 1)), tonumber(buf:sub(2, 3))
        -- "123" could also be 12:3_ still being typed: prefer HH:M if H:MM
        -- is impossible.
        if m > 59 then h, m = tonumber(buf:sub(1, 2)), tonumber(buf:sub(3, 3)) end
    else
        h, m = tonumber(buf:sub(1, 2)), tonumber(buf:sub(3, 4))
    end
    if not h or not m or h > 23 or m > 59 then return nil end
    return h * 60 + m
end

function Catalog.displayClock(buf)
    local mins = Catalog.parseClock(buf)
    if not mins then return nil end
    return string.format("%02d:%02d", math.floor(mins / 60), mins % 60)
end

local BASES = { bin = 2, oct = 8, dec = 10, hex = 16 }
local BASE_LEN = { [2] = 53, [8] = 18, [10] = 16, [16] = 14 }

-- ---------------------------------------------------------------------------
-- Category builders
-- ---------------------------------------------------------------------------

local function decimalCategory(cat)
    cat.keyset = function() return "decimal" end
    cat.press  = function(buf, key) return cat._NumFmt.press(buf, key) end
    cat.parse  = function(buf) return cat._NumFmt.parse(buf) end
    cat.format = cat.format or function(y, _to, fmt) return cat._NumFmt.format(y, fmt) end
    return cat
end

function Catalog:get(id)
    if self.cache[id] then return self.cache[id] end
    local NumFmt = self.load("numfmt")
    local cat
    if id == "cooking" then
        local Cooking = self.load("cooking")
        cat = decimalCategory{
            kind = "cooking", units = Cooking.UNITS, default_from = "cupus", default_to = "g",
            Cooking = Cooking,
            convert = function(x, from, to, ctx)
                return Cooking.convert(x, findUnit(Cooking.UNITS, from), findUnit(Cooking.UNITS, to),
                                       ctx and ctx.ingredient)
            end,
        }
    elseif id == "oven" then
        local Cooking = self.load("cooking")
        cat = decimalCategory{
            kind = "oven", units = Cooking.OVEN_UNITS, default_from = "C", default_to = "th",
            convert = function(x, from, to)
                return Cooking.ovenConvert(x, findUnit(Cooking.OVEN_UNITS, from),
                                           findUnit(Cooking.OVEN_UNITS, to))
            end,
            format = function(y, to, fmt)
                if to == "gas" then return Cooking.formatGas(y) end
                local f = {}
                for k, v in pairs(fmt or {}) do f[k] = v end
                -- Oven settings are whole degrees or half thermostats.
                if to == "th" then y = math.floor(y * 2 + 0.5) / 2
                else y = math.floor(y + 0.5) end
                return NumFmt.format(y, f)
            end,
        }
    elseif id == "currency" then
        local Currency = self.load("currency")
        cat = decimalCategory{
            kind = "currency", default_from = "EUR", default_to = "USD",
            Currency = Currency, units = {},
            convert = function(x, from, to, ctx)
                return Currency.convert(x, from, to, (ctx and ctx.rates) or Currency.SNAPSHOT.rates)
            end,
            format = function(y, _to, fmt)
                local f = { dec = fmt and fmt.dec, group = fmt and fmt.group, sig = 12 }
                -- Money: two decimals, but keep significant digits for tiny
                -- amounts (1 IDR in EUR).
                if NumFmt.isFinite(y) and math.abs(y) >= 0.01 then
                    y = math.floor(y * 100 + 0.5) / 100
                else
                    f.sig = 3
                end
                return NumFmt.format(y, f)
            end,
        }
        -- Units follow the rate table in use (the ECB may add or drop one).
        cat.setRates = function(rates)
            local units = {}
            for _i, code in ipairs(Currency.codes(rates)) do
                units[#units + 1] = { id = code, name = Currency.NAMES[code] or code, sym = code }
            end
            cat.units = units
        end
        cat.setRates(Currency.SNAPSHOT.rates)
    elseif id == "roman" then
        local NumTools = self.load("numtools")
        cat = {
            kind = "roman", default_from = "arabic", default_to = "roman",
            units = {
                { id = "arabic", name = "Number",        sym = "" },
                { id = "roman",  name = "Roman numeral", sym = "" },
            },
            keyset = function(from) return from == "roman" and "roman" or "base10" end,
            press = function(buf, key, from)
                buf = buf or ""
                if key == "C" then return "" end
                if key == "⌫" then return buf:sub(1, -2) end
                local nb = buf .. key
                if from == "roman" then
                    return NumTools.isRomanPrefix(nb) and nb or buf
                end
                if not key:match("^%d$") or (buf == "" and key == "0") then return buf end
                return tonumber(nb) <= NumTools.ROMAN_MAX and nb or buf
            end,
            parse = function(buf, from)
                if not buf or buf == "" then return nil end
                if from == "roman" then return NumTools.fromRoman(buf) end
                local n = tonumber(buf)
                return n and n >= 1 and n <= NumTools.ROMAN_MAX and n or nil
            end,
            convert = function(x) return x end,
            format = function(y, to)
                if to == "roman" then return NumTools.toRoman(y) or "—" end
                return string.format("%d", y)
            end,
        }
    elseif id == "bases" then
        local NumTools = self.load("numtools")
        cat = {
            kind = "bases", default_from = "dec", default_to = "hex",
            units = {
                { id = "bin", name = "Binary",      sym = "bin" },
                { id = "oct", name = "Octal",       sym = "oct" },
                { id = "dec", name = "Decimal",     sym = "dec" },
                { id = "hex", name = "Hexadecimal", sym = "hex" },
            },
            keyset = function(from) return "base" .. BASES[from] end,
            press = function(buf, key, from)
                buf = buf or ""
                if key == "C" then return "" end
                if key == "⌫" then return buf:sub(1, -2) end
                local base = BASES[from]
                if not NumTools.parseBase(key, base) or #buf >= BASE_LEN[base] then return buf end
                if buf == "0" then buf = "" end
                local nb = buf .. key
                return NumTools.parseBase(nb, base) and nb or buf
            end,
            parse = function(buf, from) return NumTools.parseBase(buf, BASES[from]) end,
            convert = function(x) return x end,
            format = function(y, to, fmt)
                local s = NumTools.toBase(y, BASES[to])
                if not s then return "—" end
                -- Digits are grouped by spaces whatever the language (a comma
                -- would read as a decimal point); group = "" asks for none.
                if fmt and fmt.group == "" then return s end
                return NumTools.groupDigits(s, BASES[to], " ")
            end,
        }
    elseif id == "timezone" then
        local TZ = self.load("timezones")
        local units = { { id = "here", name = "My time", sym = "" } }
        for _i, c in ipairs(TZ.CITIES) do units[#units + 1] = { id = c.id, name = c.name, sym = "" } end
        cat = {
            kind = "clock", units = units, default_from = "here", default_to = "newyork",
            TZ = TZ,
            keyset = function() return "clock" end,
            press = function(buf, key) return Catalog.pressClock(buf, key) end,
            parse = function(buf) return Catalog.parseClock(buf) end,
        }
    else
        local Units = self.load("units")
        local def = Units.CATEGORIES[id]
        if not def then return nil end
        cat = decimalCategory{
            kind = "number", units = def.units,
            default_from = def.default_from, default_to = def.default_to,
            convert = function(x, from, to)
                return Units.convert(findUnit(def.units, from), findUnit(def.units, to), x)
            end,
        }
    end
    cat.id = id
    cat._NumFmt = NumFmt
    self.cache[id] = cat
    return cat
end

-- The units' ids, checked: a stored id that no longer exists (renamed unit,
-- currency the ECB dropped) falls back to the category's default.
function Catalog.validUnit(cat, id, fallback)
    for _i, u in ipairs(cat.units) do if u.id == id then return id end end
    for _i, u in ipairs(cat.units) do if u.id == fallback then return fallback end end
    return cat.units[1].id
end

return Catalog
