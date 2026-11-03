-- cooking.lua -- kitchen measures per ingredient, and oven temperatures.
--
-- Pure Lua, specced in test_cooking_spec.lua.
--
-- Volumes: the US customary cup, tablespoon, teaspoon and fluid ounce are
-- exact fractions of the US gallon (231 in³ = 3.785 411 784 L, NIST SP 811
-- App. B): cup = 1/16 gal, fl oz = 1/128, tbsp = 1/256, tsp = 1/768. The
-- metric spoons used in French and most European recipes are 15 ml (cuillère
-- à soupe) and 5 ml (cuillère à café); the metric cup is 250 ml.
--
-- Ingredient densities are grams per US cup, from the King Arthur Baking
-- "Ingredient Weight Chart" (kingarthurbaking.com/learn/ingredient-weight-
-- chart, read 2026-11-03), except where marked "USDA": liquids, which that
-- chart rounds to 8 oz a cup, use USDA FoodData Central (SR Legacy)
-- household weights instead (whole milk 244 g, heavy cream 238 g, plain
-- yogurt 245 g, vegetable oil 218 g, maple syrup 315 g); water is 1 g/ml.
-- Weighing dry goods by volume is approximate by nature (how the cup is
-- filled matters more than the third digit), the help text says so.


local Cooking = {}

local CUP_US = 3.785411784 / 16 * 1000    -- ml, 236.5882365

-- id, English name, grams per US cup
Cooking.INGREDIENTS = {
    { id = "flour",      name = "Flour (all-purpose)",   g = 120 },
    { id = "wwflour",    name = "Whole wheat flour",     g = 113 },
    { id = "almond",     name = "Ground almonds",        g = 96 },
    { id = "cornstarch", name = "Cornstarch",            g = 112 },   -- 1/4 cup = 28 g
    { id = "semolina",   name = "Semolina",              g = 163 },
    { id = "polenta",    name = "Polenta",               g = 163 },
    { id = "sugar",      name = "Sugar (granulated)",    g = 198 },
    { id = "caster",     name = "Caster sugar",          g = 190 },
    { id = "brown",      name = "Brown sugar (packed)",  g = 213 },
    { id = "icing",      name = "Icing sugar",           g = 113 },
    { id = "honey",      name = "Honey",                 g = 336 },   -- 1 tbsp = 21 g
    { id = "maple",      name = "Maple syrup",           g = 315 },   -- USDA
    { id = "butter",     name = "Butter",                g = 226 },   -- 1/2 cup = 113 g
    { id = "oil",        name = "Vegetable oil",         g = 218 },   -- USDA
    { id = "milk",       name = "Milk",                  g = 244 },   -- USDA
    { id = "cream",      name = "Cream",                 g = 238 },   -- USDA
    { id = "yogurt",     name = "Yogurt",                g = 245 },   -- USDA
    { id = "water",      name = "Water",                 g = CUP_US },
    { id = "cocoa",      name = "Cocoa powder",          g = 84 },    -- 1/2 cup = 42 g
    { id = "oats",       name = "Rolled oats",           g = 89 },
    { id = "rice",       name = "Rice (uncooked)",       g = 198 },   -- 1/2 cup = 99 g
    { id = "salt",       name = "Salt (table)",          g = 288 },   -- 1 tbsp = 18 g
    { id = "chocchips",  name = "Chocolate chips",       g = 170 },
    { id = "raisins",    name = "Raisins",               g = 149 },
    { id = "walnuts",    name = "Walnuts (chopped)",     g = 113 },
}

function Cooking.ingredient(id)
    for _i, ing in ipairs(Cooking.INGREDIENTS) do
        if ing.id == id then return ing end
    end
    return Cooking.INGREDIENTS[1]
end

-- g/ml
function Cooking.density(id)
    return Cooking.ingredient(id).g / CUP_US
end

-- Units: kind "v" (volume, f = ml) or "m" (mass, f = g).
Cooking.UNITS = {
    { id = "tsp",    name = "Teaspoon (5 ml)",    sym = "tsp",       kind = "v", f = 5 },
    { id = "tbsp",   name = "Tablespoon (15 ml)", sym = "tbsp",      kind = "v", f = 15 },
    { id = "tspus",  name = "Teaspoon (US)",      sym = "tsp US",    kind = "v", f = CUP_US / 48 },
    { id = "tbspus", name = "Tablespoon (US)",    sym = "tbsp US",   kind = "v", f = CUP_US / 16 },
    { id = "flozus", name = "Fluid ounce (US)",   sym = "fl oz US",  kind = "v", f = CUP_US / 8 },
    { id = "cupus",  name = "Cup (US)",           sym = "cup US",    kind = "v", f = CUP_US },
    { id = "cupm",   name = "Cup (metric)",       sym = "cup",       kind = "v", f = 250 },
    { id = "ml",     name = "Millilitre",         sym = "ml",        kind = "v", f = 1 },
    { id = "cl",     name = "Centilitre",         sym = "cl",        kind = "v", f = 10 },
    { id = "dl",     name = "Decilitre",          sym = "dl",        kind = "v", f = 100 },
    { id = "L",      name = "Litre",              sym = "L",         kind = "v", f = 1000 },
    { id = "g",      name = "Gram",               sym = "g",         kind = "m", f = 1 },
    { id = "kg",     name = "Kilogram",           sym = "kg",        kind = "m", f = 1000 },
    { id = "oz",     name = "Ounce",              sym = "oz",        kind = "m", f = 28.349523125 },
    { id = "lb",     name = "Pound",              sym = "lb",        kind = "m", f = 453.59237 },
}

-- Converts between any two kitchen units; volume <-> mass goes through the
-- ingredient's density.
function Cooking.convert(v, from_u, to_u, ingredient_id)
    local x = v * from_u.f                      -- ml or g
    if from_u.kind ~= to_u.kind then
        local d = Cooking.density(ingredient_id)
        x = from_u.kind == "v" and x * d or x / d
    end
    return x / to_u.f
end

-- ---------------------------------------------------------------------------
-- Oven temperatures
--
-- Gas mark (UK): mark 1 = 275 °F and each mark adds 25 °F (mark 9 = 475 °F);
-- below 1 the scale is ¼ = 225 °F and ½ = 250 °F (Delia Smith / BBC Good
-- Food tables, the usual reference). Converted piecewise linearly between
-- those points, so mark 3.5 is 337.5 °F.
-- French "thermostat": th. n = 30·n °C (th. 6 = 180 °C), the scale printed
-- on French ovens and in French recipes.
-- ---------------------------------------------------------------------------

local GAS = { { 0.25, 225 }, { 0.5, 250 }, { 1, 275 }, { 10, 500 } }

local function interp(x, pts, a, b)
    -- pts sorted on field a; linear through the segment containing x,
    -- extended past both ends.
    local n = #pts
    local i = 1
    while i < n - 1 and x > pts[i + 1][a] do i = i + 1 end
    local p, q = pts[i], pts[i + 1]
    return p[b] + (x - p[a]) * (q[b] - p[b]) / (q[a] - p[a])
end

local function f2c(f) return (f - 32) * 5 / 9 end
local function c2f(c) return c * 9 / 5 + 32 end

Cooking.OVEN_UNITS = {
    { id = "C",   name = "Celsius",    sym = "°C",
      to = function(v) return v end, from = function(c) return c end },
    { id = "F",   name = "Fahrenheit", sym = "°F",
      to = f2c, from = c2f },
    { id = "gas", name = "Gas mark",   sym = "gas",
      to = function(g) return f2c(interp(g, GAS, 1, 2)) end,
      from = function(c) return interp(c2f(c), GAS, 2, 1) end },
    { id = "th",  name = "Thermostat", sym = "th.",
      to = function(t) return t * 30 end, from = function(c) return c / 30 end },
}

function Cooking.ovenConvert(v, from_u, to_u)
    return to_u.from(from_u.to(v))
end

-- Gas marks as an oven dial offers them: ¼, ½, then whole marks (180 °C
-- is mark 4, not 4.24).
function Cooking.formatGas(g)
    if g ~= g or g == math.huge or g == -math.huge then return "—" end
    if g < 0.375 then return "¼" end
    if g < 0.75 then return "½" end
    return string.format("%d", math.floor(g + 0.5))
end

return Cooking
