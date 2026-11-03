-- currency.lua -- euro foreign exchange reference rates of the ECB.
--
-- Pure Lua, specced in test_currency_spec.lua. Downloading is main.lua's job
-- (it needs KOReader's network stack); this module parses, stores and
-- converts.
--
-- Source: European Central Bank, euro foreign exchange reference rates,
-- https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml -- one
-- rate per currency = units of that currency for 1 EUR, published around
-- 16:00 CET on TARGET working days. The ECB states they are "for
-- information purposes only" -- so does the help text.

local Currency = {}

Currency.URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"

-- Bundled snapshot, so the converter works offline from day one. The ECB
-- feed of 2026-11-03, verbatim.
Currency.SNAPSHOT = {
    date  = "2026-11-03",
    rates = {
        USD = 1.1179, JPY = 176.95, CZK = 24.343, DKK = 7.4735, GBP = 0.83358,
        HUF = 364.40, PLN = 4.4190, RON = 5.3428, SEK = 10.9515, CHF = 0.9166,
        ISK = 136.20, NOK = 10.3185, TRY = 55.8921, AUD = 1.6007, BRL = 6.1411,
        CAD = 1.5623, CNY = 7.4590, HKD = 8.7710, IDR = 20275.02, ILS = 3.5292,
        INR = 105.9155, KRW = 1503.12, MXN = 20.7896, MYR = 4.5577, NZD = 1.9876,
        PHP = 70.943, SGD = 1.4322, THB = 37.735, ZAR = 18.5995,
    },
}

-- English names (translated through i18n_fr.lua). A code the ECB adds later
-- and that is missing here is shown by its code alone.
Currency.NAMES = {
    EUR = "Euro", USD = "US dollar", JPY = "Japanese yen", CZK = "Czech koruna",
    DKK = "Danish krone", GBP = "Pound sterling", HUF = "Hungarian forint",
    PLN = "Polish zloty", RON = "Romanian leu", SEK = "Swedish krona",
    CHF = "Swiss franc", ISK = "Icelandic krona", NOK = "Norwegian krone",
    TRY = "Turkish lira", AUD = "Australian dollar", BRL = "Brazilian real",
    CAD = "Canadian dollar", CNY = "Chinese yuan", HKD = "Hong Kong dollar",
    IDR = "Indonesian rupiah", ILS = "Israeli shekel", INR = "Indian rupee",
    KRW = "South Korean won", MXN = "Mexican peso", MYR = "Malaysian ringgit",
    NZD = "New Zealand dollar", PHP = "Philippine peso", SGD = "Singapore dollar",
    THB = "Thai baht", ZAR = "South African rand", BGN = "Bulgarian lev",
}

-- Shown first in the unit lists, the rest follow alphabetically by code.
Currency.MAJOR = { "EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "CNY" }

-- Parses the ECB daily XML. Returns { date = "YYYY-MM-DD", rates = { CODE =
-- number } } or nil, reason ("empty", "no date", "no rates").
-- Attribute quotes may be ' or " and attributes in any order; anything that
-- is not a <Cube currency rate> element is ignored.
function Currency.parse(xml)
    if type(xml) ~= "string" or xml == "" then return nil, "empty" end
    local date = xml:match("<Cube%s+time%s*=%s*['\"](%d%d%d%d%-%d%d%-%d%d)['\"]")
    if not date then return nil, "no date" end
    local rates, n = {}, 0
    for attrs in xml:gmatch("<Cube%s+([^>]-)/?>") do
        local code = attrs:match("currency%s*=%s*['\"](%u%u%u)['\"]")
        local rate = tonumber(attrs:match("rate%s*=%s*['\"]([%d%.]+)['\"]") or "")
        if code and rate and rate > 0 and code ~= "EUR" then
            if not rates[code] then n = n + 1 end
            rates[code] = rate
        end
    end
    if n < 5 then return nil, "no rates" end
    return { date = date, rates = rates }
end

-- A stored table is usable if it has a date and some rates (settings files
-- can be hand-edited or truncated).
function Currency.valid(t)
    if type(t) ~= "table" or type(t.date) ~= "string" or type(t.rates) ~= "table" then
        return false
    end
    local n = 0
    for _k, v in pairs(t.rates) do
        if type(v) ~= "number" or v <= 0 then return false end
        n = n + 1
    end
    return n >= 5
end

-- The rates to use: the stored ones if valid and not older than the
-- snapshot, otherwise the snapshot. (Dates compare as strings.)
function Currency.pick(stored)
    if Currency.valid(stored) and stored.date >= Currency.SNAPSHOT.date then
        return stored
    end
    return Currency.SNAPSHOT
end

local function rate(rates, code)
    if code == "EUR" then return 1 end
    return rates[code]
end

-- v units of `from` in `to`. nil when either code has no rate.
function Currency.convert(v, from, to, rates)
    local rf, rt = rate(rates, from), rate(rates, to)
    if not rf or not rt then return nil end
    return v / rf * rt
end

-- The currency codes of a rate table, in display order.
function Currency.codes(rates)
    local out, seen = {}, {}
    for _i, c in ipairs(Currency.MAJOR) do
        if c == "EUR" or rates[c] then out[#out + 1] = c; seen[c] = true end
    end
    local rest = {}
    for c in pairs(rates) do if not seen[c] then rest[#rest + 1] = c end end
    table.sort(rest)
    for _i, c in ipairs(rest) do out[#out + 1] = c end
    return out
end

return Currency
