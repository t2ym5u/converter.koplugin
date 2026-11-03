-- units.lua -- physical units: factors to one base unit per category.
--
-- Pure data plus two conversion helpers; no KOReader dependency (specced in
-- test_units_spec.lua). Names are English and translated at display time
-- (i18n_fr.lua); symbols are left as they are.
--
-- Every factor is EXACT by definition unless marked otherwise. Sources:
--   * SI Brochure, 9th edition (BIPM, 2019) -- SI prefixes, the litre,
--     the electronvolt (e = 1.602 176 634 e-19 C exactly since 2019),
--     the standard atmosphere (101 325 Pa) and the bar (100 000 Pa).
--   * NIST Special Publication 811 (2008 ed.), Appendix B.8/B.9 -- US
--     customary and imperial units: international yard and pound (1959:
--     1 yd = 0.9144 m, 1 lb = 0.453 592 37 kg), US gallon = 231 in³,
--     imperial gallon = 4.546 09 L (UK Weights and Measures Act 1985),
--     nautical mile = 1852 m, thermochemical calorie = 4.184 J,
--     IT British thermal unit = 1055.055 852 62 J, lbf = 4.448 221 615 260 5 N.
--   * IEC 80000-13 -- binary prefixes (KiB = 1024 B ...).
-- Units marked "conventional" (mmHg, inHg) use NIST SP 811's values.
--
-- A unit is { id, name, sym, f } with base = value * f, or { id, name, sym,
-- to, from } when the relation is not a plain factor (temperature, fuel).

local Units = {}

local US_GAL   = 3.785411784          -- L (231 in³)
local UK_GAL   = 4.54609              -- L
local MILE     = 1.609344             -- km
local LBF      = 4.4482216152605      -- N
local INCH     = 0.0254               -- m

Units.CATEGORIES = {
    length = {
        base = "m", default_from = "m", default_to = "ft",
        units = {
            { id = "mm",  name = "Millimetre",     sym = "mm",  f = 1e-3 },
            { id = "cm",  name = "Centimetre",     sym = "cm",  f = 1e-2 },
            { id = "m",   name = "Metre",          sym = "m",   f = 1 },
            { id = "km",  name = "Kilometre",      sym = "km",  f = 1e3 },
            { id = "in",  name = "Inch",           sym = "in",  f = INCH },
            { id = "ft",  name = "Foot",           sym = "ft",  f = 0.3048 },
            { id = "yd",  name = "Yard",           sym = "yd",  f = 0.9144 },
            { id = "mi",  name = "Mile",           sym = "mi",  f = 1609.344 },
            { id = "nmi", name = "Nautical mile",  sym = "NM",  f = 1852 },
        },
    },
    mass = {
        base = "kg", default_from = "kg", default_to = "lb",
        units = {
            { id = "mg",  name = "Milligram",      sym = "mg",  f = 1e-6 },
            { id = "g",   name = "Gram",           sym = "g",   f = 1e-3 },
            { id = "kg",  name = "Kilogram",       sym = "kg",  f = 1 },
            { id = "t",   name = "Tonne",          sym = "t",   f = 1e3 },
            { id = "ct",  name = "Carat",          sym = "ct",  f = 2e-4 },
            { id = "oz",  name = "Ounce",          sym = "oz",  f = 0.028349523125 },
            { id = "lb",  name = "Pound",          sym = "lb",  f = 0.45359237 },
            { id = "st",  name = "Stone",          sym = "st",  f = 6.35029318 },
            { id = "ston", name = "Short ton (US)", sym = "sh tn", f = 907.18474 },
            { id = "lton", name = "Long ton (UK)",  sym = "LT",    f = 1016.0469088 },
        },
    },
    volume = {
        base = "L", default_from = "L", default_to = "galus",
        units = {
            { id = "ml",    name = "Millilitre",       sym = "ml",  f = 1e-3 },
            { id = "cl",    name = "Centilitre",       sym = "cl",  f = 1e-2 },
            { id = "dl",    name = "Decilitre",        sym = "dl",  f = 1e-1 },
            { id = "L",     name = "Litre",            sym = "L",   f = 1 },
            { id = "m3",    name = "Cubic metre",      sym = "m³",  f = 1e3 },
            { id = "in3",   name = "Cubic inch",       sym = "in³", f = 0.016387064 },
            { id = "ft3",   name = "Cubic foot",       sym = "ft³", f = 28.316846592 },
            { id = "flozus", name = "Fluid ounce (US)", sym = "fl oz US", f = US_GAL / 128 },
            { id = "ptus",  name = "Pint (US)",        sym = "pt US",  f = US_GAL / 8 },
            { id = "qtus",  name = "Quart (US)",       sym = "qt US",  f = US_GAL / 4 },
            { id = "galus", name = "Gallon (US)",      sym = "gal US", f = US_GAL },
            { id = "flozuk", name = "Fluid ounce (UK)", sym = "fl oz UK", f = UK_GAL / 160 },
            { id = "ptuk",  name = "Pint (UK)",        sym = "pt UK",  f = UK_GAL / 8 },
            { id = "galuk", name = "Gallon (UK)",      sym = "gal UK", f = UK_GAL },
        },
    },
    temperature = {
        base = "K", default_from = "C", default_to = "F",
        units = {
            { id = "C", name = "Celsius",    sym = "°C",
              to = function(v) return v + 273.15 end, from = function(k) return k - 273.15 end },
            { id = "F", name = "Fahrenheit", sym = "°F",
              to = function(v) return (v + 459.67) * 5 / 9 end, from = function(k) return k * 9 / 5 - 459.67 end },
            { id = "K", name = "Kelvin",     sym = "K",   f = 1 },
            { id = "R", name = "Rankine",    sym = "°R",  f = 5 / 9 },
        },
    },
    area = {
        base = "m2", default_from = "m2", default_to = "ft2",
        units = {
            { id = "cm2",  name = "Square centimetre", sym = "cm²", f = 1e-4 },
            { id = "m2",   name = "Square metre",      sym = "m²",  f = 1 },
            { id = "a",    name = "Are",               sym = "a",   f = 100 },
            { id = "ha",   name = "Hectare",           sym = "ha",  f = 1e4 },
            { id = "km2",  name = "Square kilometre",  sym = "km²", f = 1e6 },
            { id = "in2",  name = "Square inch",       sym = "in²", f = INCH * INCH },
            { id = "ft2",  name = "Square foot",       sym = "ft²", f = 0.3048 * 0.3048 },
            { id = "yd2",  name = "Square yard",       sym = "yd²", f = 0.9144 * 0.9144 },
            { id = "acre", name = "Acre",              sym = "ac",  f = 4046.8564224 },
            { id = "mi2",  name = "Square mile",       sym = "mi²", f = 1609.344 * 1609.344 },
        },
    },
    speed = {
        base = "ms", default_from = "kmh", default_to = "mph",
        units = {
            { id = "ms",  name = "Metre per second",  sym = "m/s",  f = 1 },
            { id = "kmh", name = "Kilometre per hour", sym = "km/h", f = 1 / 3.6 },
            { id = "mph", name = "Mile per hour",     sym = "mph",  f = 0.44704 },
            { id = "kn",  name = "Knot",              sym = "kn",   f = 1852 / 3600 },
            { id = "fts", name = "Foot per second",   sym = "ft/s", f = 0.3048 },
        },
    },
    time = {
        -- Month and year are averages of the Gregorian calendar
        -- (365.2425 days a year), not exact durations.
        base = "s", default_from = "h", default_to = "min",
        units = {
            { id = "ms",  name = "Millisecond", sym = "ms",  f = 1e-3 },
            { id = "s",   name = "Second",      sym = "s",   f = 1 },
            { id = "min", name = "Minute",      sym = "min", f = 60 },
            { id = "h",   name = "Hour",        sym = "h",   f = 3600 },
            { id = "d",   name = "Day",         sym = "d",   f = 86400 },
            { id = "wk",  name = "Week",        sym = "wk",  f = 604800 },
            { id = "mo",  name = "Month (average)", sym = "mo", f = 365.2425 * 86400 / 12 },
            { id = "yr",  name = "Year (average)",  sym = "yr", f = 365.2425 * 86400 },
        },
    },
    fuel = {
        -- Base: kilometres per litre. L/100 km is its inverse, hence the
        -- to/from pairs; 0 converts to "—" (infinite).
        base = "kml", default_from = "l100", default_to = "mpgus",
        units = {
            { id = "l100",  name = "Litres per 100 km", sym = "L/100 km",
              to = function(v) return 100 / v end, from = function(b) return 100 / b end },
            { id = "kml",   name = "Kilometres per litre", sym = "km/L", f = 1 },
            { id = "mpgus", name = "Miles per gallon (US)", sym = "mpg US", f = MILE / US_GAL },
            { id = "mpguk", name = "Miles per gallon (UK)", sym = "mpg UK", f = MILE / UK_GAL },
        },
    },
    energy = {
        base = "J", default_from = "kcal", default_to = "kJ",
        units = {
            { id = "J",    name = "Joule",          sym = "J",   f = 1 },
            { id = "kJ",   name = "Kilojoule",      sym = "kJ",  f = 1e3 },
            { id = "MJ",   name = "Megajoule",      sym = "MJ",  f = 1e6 },
            { id = "cal",  name = "Calorie",        sym = "cal", f = 4.184 },
            { id = "kcal", name = "Kilocalorie",    sym = "kcal", f = 4184 },
            { id = "Wh",   name = "Watt-hour",      sym = "Wh",  f = 3600 },
            { id = "kWh",  name = "Kilowatt-hour",  sym = "kWh", f = 3.6e6 },
            { id = "BTU",  name = "British thermal unit", sym = "BTU", f = 1055.05585262 },
            { id = "ftlbf", name = "Foot-pound",    sym = "ft·lbf", f = 0.3048 * LBF },
            { id = "eV",   name = "Electronvolt",   sym = "eV",  f = 1.602176634e-19 },
        },
    },
    pressure = {
        base = "Pa", default_from = "bar", default_to = "psi",
        units = {
            { id = "Pa",   name = "Pascal",       sym = "Pa",   f = 1 },
            { id = "hPa",  name = "Hectopascal",  sym = "hPa",  f = 100 },
            { id = "kPa",  name = "Kilopascal",   sym = "kPa",  f = 1e3 },
            { id = "MPa",  name = "Megapascal",   sym = "MPa",  f = 1e6 },
            { id = "bar",  name = "Bar",          sym = "bar",  f = 1e5 },
            { id = "mbar", name = "Millibar",     sym = "mbar", f = 100 },
            { id = "atm",  name = "Atmosphere",   sym = "atm",  f = 101325 },
            { id = "torr", name = "Torr",         sym = "Torr", f = 101325 / 760 },
            { id = "mmHg", name = "Millimetre of mercury", sym = "mmHg", f = 133.322387415 }, -- conventional
            { id = "inHg", name = "Inch of mercury", sym = "inHg", f = 3386.389 },          -- conventional
            { id = "psi",  name = "Pound per square inch", sym = "psi", f = LBF / (INCH * INCH) },
        },
    },
    data = {
        base = "B", default_from = "GB", default_to = "GiB",
        units = {
            { id = "bit",  name = "Bit",       sym = "bit",  f = 1 / 8 },
            { id = "B",    name = "Byte",      sym = "B",    f = 1 },
            { id = "kB",   name = "Kilobyte",  sym = "kB",   f = 1e3 },
            { id = "MB",   name = "Megabyte",  sym = "MB",   f = 1e6 },
            { id = "GB",   name = "Gigabyte",  sym = "GB",   f = 1e9 },
            { id = "TB",   name = "Terabyte",  sym = "TB",   f = 1e12 },
            { id = "KiB",  name = "Kibibyte",  sym = "KiB",  f = 1024 },
            { id = "MiB",  name = "Mebibyte",  sym = "MiB",  f = 1024 ^ 2 },
            { id = "GiB",  name = "Gibibyte",  sym = "GiB",  f = 1024 ^ 3 },
            { id = "TiB",  name = "Tebibyte",  sym = "TiB",  f = 1024 ^ 4 },
            { id = "Mbit", name = "Megabit",   sym = "Mbit", f = 1e6 / 8 },
            { id = "Gbit", name = "Gigabit",   sym = "Gbit", f = 1e9 / 8 },
        },
    },
    angle = {
        base = "deg", default_from = "deg", default_to = "rad",
        units = {
            { id = "deg",    name = "Degree",       sym = "°",   f = 1 },
            { id = "rad",    name = "Radian",       sym = "rad", f = 180 / math.pi },
            { id = "grad",   name = "Gradian",      sym = "gon", f = 0.9 },
            { id = "arcmin", name = "Minute of arc", sym = "′",  f = 1 / 60 },
            { id = "arcsec", name = "Second of arc", sym = "″",  f = 1 / 3600 },
            { id = "turn",   name = "Turn",         sym = "tr",  f = 360 },
            { id = "mil",    name = "Mil (NATO)",   sym = "mil", f = 360 / 6400 },
        },
    },
}

-- unit -> base unit
function Units.toBase(u, v)
    if u.to then return u.to(v) end
    return v * u.f
end

-- base unit -> unit
function Units.fromBase(u, b)
    if u.from then return u.from(b) end
    return b / u.f
end

function Units.convert(from_u, to_u, v)
    if from_u == to_u then return v end
    return Units.fromBase(to_u, Units.toBase(from_u, v))
end

function Units.find(units, id)
    for _i, u in ipairs(units) do
        if u.id == id then return u end
    end
    return nil
end

return Units
