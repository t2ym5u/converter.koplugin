-- timezones.lua -- "what time is it in ...": city offsets and DST rules.
--
-- Pure Lua (no os.time/os.date: those depend on the device's own zone,
-- which is exactly what is not known), specced in test_timezones_spec.lua.
--
-- Lua has no tz database, so the rules in force in 2026 are embedded here
-- (from the IANA tz database, "europe", "northamerica", "australasia",
-- "africa" files). Past rule changes are not modelled: dates before the
-- current rules came into force can be an hour off.
--
--   EU  last Sunday of March 01:00 UTC -> last Sunday of October 01:00 UTC
--       (Directive 2000/84/EC; also the UK, Ireland, Portugal, Ukraine...)
--   US  2nd Sunday of March 02:00 local -> 1st Sunday of November 02:00
--       local (Energy Policy Act 2005; Canada follows it)
--   AU  1st Sunday of October 02:00 standard -> 1st Sunday of April 03:00
--       daylight (NSW, Victoria, Tasmania, South Australia, ACT)
--   NZ  last Sunday of September 02:00 standard -> 1st Sunday of April
--       03:00 daylight
--   EG  last Friday of April 00:00 -> last Thursday of October 24:00
--       (Egypt, reinstated 2023)
--   nil no daylight saving time (most of Asia, Africa and South America,
--       Arizona, Queensland, Mexico since 2022, Brazil since 2019, Iran
--       since 2022, Turkey and Russia since 2016/2014).

local TZ = {}

-- Days since 1970-01-01 of a proleptic Gregorian date (H. Hinnant's
-- days_from_civil). Integer arithmetic only, works for any year >= 1.
function TZ.daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

function TZ.civilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
                           - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- 0 = Sunday ... 6 = Saturday. 1970-01-01 was a Thursday.
function TZ.weekday(days)
    return (days + 4) % 7
end

-- Seconds since the epoch of y-m-d h:mi in UTC.
function TZ.epoch(y, m, d, h, mi)
    return TZ.daysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (mi or 0) * 60
end

-- Day number of the n-th `wday` of a month (n = -1: the last one).
function TZ.nthWeekday(y, m, wday, n)
    if n > 0 then
        local first = TZ.daysFromCivil(y, m, 1)
        return first + (wday - TZ.weekday(first)) % 7 + (n - 1) * 7
    end
    local ny, nm = y, m + 1
    if nm > 12 then ny, nm = y + 1, 1 end
    local last = TZ.daysFromCivil(ny, nm, 1) - 1
    return last - (TZ.weekday(last) - wday) % 7
end

local SUN, THU, FRI = 0, 4, 5
local H = 3600

-- Each rule: function(year, std_seconds) -> dst_start_utc, dst_end_utc.
-- Southern rules start late in the year and end early in it.
TZ.RULES = {
    EU = function(y)
        return TZ.nthWeekday(y, 3, SUN, -1) * 86400 + 1 * H,
               TZ.nthWeekday(y, 10, SUN, -1) * 86400 + 1 * H
    end,
    US = function(y, std)
        return TZ.nthWeekday(y, 3, SUN, 2) * 86400 + 2 * H - std,
               TZ.nthWeekday(y, 11, SUN, 1) * 86400 + 2 * H - (std + H)
    end,
    AU = function(y, std)
        return TZ.nthWeekday(y, 10, SUN, 1) * 86400 + 2 * H - std,
               TZ.nthWeekday(y, 4, SUN, 1) * 86400 + 3 * H - (std + H)
    end,
    NZ = function(y, std)
        return TZ.nthWeekday(y, 9, SUN, -1) * 86400 + 2 * H - std,
               TZ.nthWeekday(y, 4, SUN, 1) * 86400 + 3 * H - (std + H)
    end,
    EG = function(y, std)
        return TZ.nthWeekday(y, 4, FRI, -1) * 86400 - std,
               (TZ.nthWeekday(y, 10, THU, -1) + 1) * 86400 - (std + H)
    end,
}
TZ.SOUTHERN = { AU = true, NZ = true }

-- id, English name, standard offset in minutes, DST rule.
TZ.CITIES = {
    { id = "honolulu",     name = "Honolulu",      off = -600 },
    { id = "anchorage",    name = "Anchorage",     off = -540, dst = "US" },
    { id = "losangeles",   name = "Los Angeles",   off = -480, dst = "US" },
    { id = "vancouver",    name = "Vancouver",     off = -480, dst = "US" },
    { id = "denver",       name = "Denver",        off = -420, dst = "US" },
    { id = "phoenix",      name = "Phoenix",       off = -420 },
    { id = "chicago",      name = "Chicago",       off = -360, dst = "US" },
    { id = "mexico",       name = "Mexico City",   off = -360 },
    { id = "newyork",      name = "New York",      off = -300, dst = "US" },
    { id = "montreal",     name = "Montreal",      off = -300, dst = "US" },
    { id = "bogota",       name = "Bogotá",        off = -300 },
    { id = "lima",         name = "Lima",          off = -300 },
    { id = "halifax",      name = "Halifax",       off = -240, dst = "US" },
    { id = "pointeapitre", name = "Pointe-à-Pitre", off = -240 },
    { id = "stjohns",      name = "St. John's",    off = -210, dst = "US" },
    { id = "saopaulo",     name = "São Paulo",     off = -180 },
    { id = "buenosaires",  name = "Buenos Aires",  off = -180 },
    { id = "reykjavik",    name = "Reykjavik",     off = 0 },
    { id = "dakar",        name = "Dakar",         off = 0 },
    { id = "london",       name = "London",        off = 0,   dst = "EU" },
    { id = "lisbon",       name = "Lisbon",        off = 0,   dst = "EU" },
    { id = "paris",        name = "Paris",         off = 60,  dst = "EU" },
    { id = "brussels",     name = "Brussels",      off = 60,  dst = "EU" },
    { id = "berlin",       name = "Berlin",        off = 60,  dst = "EU" },
    { id = "madrid",       name = "Madrid",        off = 60,  dst = "EU" },
    { id = "rome",         name = "Rome",          off = 60,  dst = "EU" },
    { id = "geneva",       name = "Geneva",        off = 60,  dst = "EU" },
    { id = "algiers",      name = "Algiers",       off = 60 },
    { id = "lagos",        name = "Lagos",         off = 60 },
    { id = "athens",       name = "Athens",        off = 120, dst = "EU" },
    { id = "kyiv",         name = "Kyiv",          off = 120, dst = "EU" },
    { id = "cairo",        name = "Cairo",         off = 120, dst = "EG" },
    { id = "johannesburg", name = "Johannesburg",  off = 120 },
    { id = "istanbul",     name = "Istanbul",      off = 180 },
    { id = "moscow",       name = "Moscow",        off = 180 },
    { id = "nairobi",      name = "Nairobi",       off = 180 },
    { id = "tehran",       name = "Tehran",        off = 210 },
    { id = "dubai",        name = "Dubai",         off = 240 },
    { id = "reunion",      name = "Réunion",       off = 240 },
    { id = "karachi",      name = "Karachi",       off = 300 },
    { id = "delhi",        name = "New Delhi",     off = 330 },
    { id = "kathmandu",    name = "Kathmandu",     off = 345 },
    { id = "dhaka",        name = "Dhaka",         off = 360 },
    { id = "bangkok",      name = "Bangkok",       off = 420 },
    { id = "singapore",    name = "Singapore",     off = 480 },
    { id = "beijing",      name = "Beijing",       off = 480 },
    { id = "hongkong",     name = "Hong Kong",     off = 480 },
    { id = "perth",        name = "Perth",         off = 480 },
    { id = "tokyo",        name = "Tokyo",         off = 540 },
    { id = "seoul",        name = "Seoul",         off = 540 },
    { id = "adelaide",     name = "Adelaide",      off = 570, dst = "AU" },
    { id = "brisbane",     name = "Brisbane",      off = 600 },
    { id = "sydney",       name = "Sydney",        off = 600, dst = "AU" },
    { id = "noumea",       name = "Nouméa",        off = 660 },
    { id = "auckland",     name = "Auckland",      off = 720, dst = "NZ" },
}

local by_id
function TZ.city(id)
    if not by_id then
        by_id = {}
        for _i, c in ipairs(TZ.CITIES) do by_id[c.id] = c end
    end
    return by_id[id]
end

-- Is daylight saving time in force in `city` at the UTC instant `utc`?
function TZ.isDst(city, utc)
    local rule = city.dst and TZ.RULES[city.dst]
    if not rule then return false end
    local std = city.off * 60
    local y = TZ.civilFromDays(math.floor((utc + std) / 86400))
    local s, e = rule(y, std)
    if TZ.SOUTHERN[city.dst] then
        return utc >= s or utc < e
    end
    return utc >= s and utc < e
end

-- UTC offset of `city` at `utc`, in seconds.
function TZ.offset(city, utc)
    return city.off * 60 + (TZ.isDst(city, utc) and H or 0)
end

-- UTC instant at which the wall clock of `city` reads `wall` (seconds since
-- the epoch, as if the wall clock were UTC). In the hour skipped in spring
-- this picks the later reading; in the repeated autumn hour, the first one.
function TZ.wallToUtc(city, wall)
    local guess = wall - city.off * 60
    local off = TZ.offset(city, guess)
    local utc = wall - off
    if TZ.offset(city, utc) ~= off then
        utc = wall - TZ.offset(city, utc)
    end
    return utc
end

-- y, m, d, h, mi of a wall-clock instant.
function TZ.fields(wall)
    local days = math.floor(wall / 86400)
    local secs = wall - days * 86400
    local y, m, d = TZ.civilFromDays(days)
    return y, m, d, math.floor(secs / 3600), math.floor((secs % 3600) / 60), days
end

-- "+5:30", "−3", "±0" (U+2212 minus) for an offset in seconds.
function TZ.formatOffset(secs)
    local sign = secs > 0 and "+" or (secs < 0 and "−" or "±")
    local a = math.abs(secs)
    local h, mi = math.floor(a / 3600), math.floor((a % 3600) / 60)
    if mi == 0 then return string.format("%s%d", sign, h) end
    return string.format("%s%d:%02d", sign, h, mi)
end

-- Device offset in seconds from os.date's local and UTC fields (the only
-- way Lua exposes the device zone). Returns 0 where they agree.
function TZ.deviceOffset(now, date)
    date = date or os.date
    local l, g = date("*t", now), date("!*t", now)
    local dd = TZ.daysFromCivil(l.year, l.month, l.day) - TZ.daysFromCivil(g.year, g.month, g.day)
    return dd * 86400 + (l.hour - g.hour) * 3600 + (l.min - g.min) * 60
end

-- Converts a time of day typed for `from` into `to`.
--   from, to   city tables; nil = "here", using here_off (seconds)
--   now_utc    the current instant
--   minutes    minutes after midnight typed by the user, or nil for "now"
-- Returns { utc, from_h, from_m, to_h, to_m, day_shift (to date - from
-- date: -1, 0, 1), from_off, to_off }.
function TZ.convert(from, to, now_utc, minutes, here_off)
    local function off(c, utc) return c and TZ.offset(c, utc) or here_off end
    local utc = now_utc
    if minutes then
        local wall_now = now_utc + off(from, now_utc)
        local midnight = math.floor(wall_now / 86400) * 86400
        local wall = midnight + minutes * 60
        utc = from and TZ.wallToUtc(from, wall) or (wall - here_off)
    end
    local fo, to_o = off(from, utc), off(to, utc)
    local _y1, _m1, _d1, fh, fm, fdays = TZ.fields(utc + fo)
    local _y2, _m2, _d2, th, tm, tdays = TZ.fields(utc + to_o)
    return {
        utc = utc, from_h = fh, from_m = fm, to_h = th, to_m = tm,
        day_shift = tdays - fdays, from_off = fo, to_off = to_o,
    }
end

return TZ
