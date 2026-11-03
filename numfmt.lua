-- numfmt.lua -- number formatting and the keypad's input buffer.
--
-- Pure Lua (no KOReader dependency), specced in test_numfmt_spec.lua.
--
-- The input buffer is a plain string in canonical form: an optional leading
-- "-", digits, at most one "." (the decimal separator is only swapped for a
-- comma at display time, so parsing never depends on the UI language).

local NumFmt = {}

NumFmt.MAX_INPUT = 15     -- characters typed into the buffer
NumFmt.SIG       = 10     -- significant digits of a main result
NumFmt.SIG_TABLE = 6      -- significant digits in the all-units table

local NBSP = "\u{00A0}"

local SUPER = {
    ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴",
    ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷", ["8"] = "⁸", ["9"] = "⁹", ["-"] = "⁻",
}

-- Separators for a UI language: French (and es/de) write 1 234,5 / 1.234,5;
-- English writes 1,234.5.
function NumFmt.separators(lang)
    if lang == "fr" then return ",", NBSP end
    if lang == "de" or lang == "es" then return ",", "." end
    return ".", ","
end

local function group(int, sep)
    if not sep or #int <= 4 then return int end
    local out = int:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse())
    out = out:reverse()
    if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
    return out
end

local function isFinite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
NumFmt.isFinite = isFinite

-- Formats v with `sig` significant digits, trailing zeros trimmed.
--   opts.dec    decimal separator (default ".")
--   opts.group  thousands separator, or nil for none
--   opts.sig    significant digits (default NumFmt.SIG)
-- Very large or very small magnitudes use "×10ⁿ". Not a number: "—".
function NumFmt.format(v, opts)
    opts = opts or {}
    local dec, sep, sig = opts.dec or ".", opts.group, opts.sig or NumFmt.SIG
    if not isFinite(v) then return "—" end
    if v == 0 then return "0" end
    local neg = v < 0
    local a = math.abs(v)
    local exp = math.floor(math.log(a) / math.log(10))
    -- log10 can be off by one right at a power of ten.
    if 10 ^ exp > a then exp = exp - 1 elseif 10 ^ (exp + 1) <= a then exp = exp + 1 end
    local s
    if exp >= 15 or exp < -6 then
        local m = a / 10 ^ exp
        local ms = string.format("%." .. (sig - 1) .. "f", m)
        if tonumber(ms) >= 10 then          -- 9.9999 rounded up to 10
            exp = exp + 1
            ms = string.format("%." .. (sig - 1) .. "f", a / 10 ^ exp)
        end
        ms = ms:find("%.") and ms:gsub("0+$", ""):gsub("%.$", "") or ms
        local es = string.format("%d", exp):gsub(".", SUPER)
        s = ms:gsub("%.", dec) .. "×10" .. es
    else
        local decimals = math.max(0, math.min(12, sig - 1 - exp))
        local fs = string.format("%." .. decimals .. "f", a)
        if fs:find("%.") then fs = fs:gsub("0+$", ""):gsub("%.$", "") end
        if fs:match("^[0.]*$") then return "0" end
        local int, frac = fs:match("^(%d+)%.?(%d*)$")
        s = group(int, sep) .. (frac ~= "" and (dec .. frac) or "")
    end
    return (neg and "−" or "") .. s
end

-- The buffer as shown on screen: comma or point, "−" for the sign.
function NumFmt.displayInput(buf, dec)
    if buf == nil or buf == "" then return "0" end
    local s = buf:gsub("%.", dec or ".")
    return (s:gsub("^%-", "−"))
end

-- Value of a buffer ("", "-" and "." count as nothing typed yet).
function NumFmt.parse(buf)
    if buf == nil or buf == "" or buf == "-" or buf == "." or buf == "-." then return nil end
    return tonumber(buf)
end

-- The buffer after pressing `key`:
--   "0".."9", "." (decimal point), "±" (sign), "⌫" (delete last), "C" (clear).
-- Keys that would make it invalid (a second point, too long) are ignored.
function NumFmt.press(buf, key)
    buf = buf or ""
    if key == "C" then return "" end
    if key == "⌫" then return buf:sub(1, -2) end
    if key == "±" then
        if buf:sub(1, 1) == "-" then return buf:sub(2) end
        return "-" .. buf
    end
    local digits = #buf:gsub("^%-", "")
    if digits >= NumFmt.MAX_INPUT then return buf end
    if key == "." then
        if buf:find("%.") then return buf end
        if buf == "" or buf == "-" then return buf .. "0." end
        return buf .. "."
    end
    if key:match("^%d$") then
        -- No leading zeros: "0" then "7" is "7", not "07".
        if buf == "0" then return key end
        if buf == "-0" then return "-" .. key end
        return buf .. key
    end
    return buf
end

-- A number back into a canonical buffer (used when a result becomes the
-- new input, e.g. on swap). Up to 10 significant digits, no exponent.
function NumFmt.toBuffer(v)
    if not isFinite(v) then return "" end
    local s = NumFmt.format(v, { dec = ".", sig = NumFmt.SIG })
    if s:find("×") then return string.format("%.0f", v) end
    s = s:gsub("−", "-")
    if #s:gsub("^%-", "") > NumFmt.MAX_INPUT then
        s = s:sub(1, NumFmt.MAX_INPUT + (s:sub(1, 1) == "-" and 1 or 0)):gsub("%.$", "")
    end
    return s
end

return NumFmt
