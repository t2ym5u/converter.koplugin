-- numtools.lua -- Roman numerals and number bases. Pure Lua, specced in
-- test_numtools_spec.lua.

local NumTools = {}

-- ---------------------------------------------------------------------------
-- Roman numerals, 1..3999, standard subtractive notation
-- ---------------------------------------------------------------------------

local ROMAN = {
    { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" },
    { 100, "C" },  { 90, "XC" },  { 50, "L" },  { 40, "XL" },
    { 10, "X" },   { 9, "IX" },   { 5, "V" },   { 4, "IV" }, { 1, "I" },
}
local ROMAN_VAL = { I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000 }

NumTools.ROMAN_MAX = 3999

function NumTools.toRoman(n)
    if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > NumTools.ROMAN_MAX then
        return nil
    end
    local out = {}
    for _i, p in ipairs(ROMAN) do
        while n >= p[1] do
            out[#out + 1] = p[2]
            n = n - p[1]
        end
    end
    return table.concat(out)
end

-- Only well-formed numerals are accepted: "IIII", "VX" or "IC" are not
-- numbers (the round trip through toRoman must give the same string back).
function NumTools.fromRoman(s)
    if type(s) ~= "string" then return nil end
    s = s:upper()
    if s == "" or s:find("[^IVXLCDM]") then return nil end
    local total, prev = 0, 0
    for i = #s, 1, -1 do
        local v = ROMAN_VAL[s:sub(i, i)]
        if v < prev then total = total - v else total = total + v; prev = v end
    end
    if NumTools.toRoman(total) ~= s then return nil end
    return total
end

-- Can `s` still become a valid numeral by typing more letters at the end?
-- Used to refuse impossible keys early. Cheap approximation: s is a prefix of
-- some valid numeral if some numeral up to 3999 starts with it.
local prefixes
function NumTools.isRomanPrefix(s)
    if s == "" then return true end
    if not prefixes then
        prefixes = {}
        for n = 1, NumTools.ROMAN_MAX do
            local r = NumTools.toRoman(n)
            for k = 1, #r do prefixes[r:sub(1, k)] = true end
        end
    end
    return prefixes[s] == true
end

-- ---------------------------------------------------------------------------
-- Bases 2, 8, 10, 16 -- non-negative integers up to 2^53 (exact in a double)
-- ---------------------------------------------------------------------------

NumTools.MAX_INT = 2 ^ 53
local DIGITS = "0123456789ABCDEF"

function NumTools.parseBase(s, base)
    if type(s) ~= "string" or s == "" then return nil end
    s = s:upper()
    local n = 0
    for i = 1, #s do
        local d = DIGITS:find(s:sub(i, i), 1, true)
        if not d or d > base then return nil end
        n = n * base + (d - 1)
        if n > NumTools.MAX_INT then return nil end
    end
    return n
end

function NumTools.toBase(n, base)
    if type(n) ~= "number" or n < 0 or n ~= math.floor(n) or n > NumTools.MAX_INT then
        return nil
    end
    if n == 0 then return "0" end
    local out = {}
    while n > 0 do
        local d = n % base
        out[#out + 1] = DIGITS:sub(d + 1, d + 1)
        n = (n - d) / base
    end
    return table.concat(out):reverse()
end

-- Digits grouped for reading: binary by 4, hex by 4, decimal by 3, octal by 3.
function NumTools.groupDigits(s, base, sep)
    local size = (base == 2 or base == 16) and 4 or 3
    if #s <= size + (base == 10 and 1 or 0) then return s end
    local out = {}
    local first = #s % size
    if first > 0 then out[1] = s:sub(1, first) end
    for i = first + 1, #s, size do out[#out + 1] = s:sub(i, i + size - 1) end
    return table.concat(out, sep or " ")
end

-- The keys valid in each base.
function NumTools.baseKeys(base)
    local keys = {}
    for d = 1, base do keys[d] = DIGITS:sub(d, d) end
    return keys
end

return NumTools
