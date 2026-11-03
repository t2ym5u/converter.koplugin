local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("units", function()
    local Units = require("units")

    local function conv(cat, from, to, v)
        local us = Units.CATEGORIES[cat].units
        return Units.convert(Units.find(us, from), Units.find(us, to), v)
    end
    local function near(expected, got, rel)
        rel = rel or 1e-12
        assert.is_true(math.abs(got - expected) <= rel * math.max(1, math.abs(expected)),
            ("expected %.15g, got %.15g"):format(expected, got))
    end

    it("round-trips every unit of every category", function()
        for cat, def in pairs(Units.CATEGORIES) do
            for _, a in ipairs(def.units) do
                for _, b in ipairs(def.units) do
                    for _, v in ipairs({ 1, 37.5, 1234.5678 }) do
                        near(v, conv(cat, b, a, conv(cat, a, b, v)), 1e-11)
                    end
                end
            end
        end
    end)

    it("has unique ids, a valid default pair and a symbol for each unit", function()
        for cat, def in pairs(Units.CATEGORIES) do
            local seen = {}
            for _, u in ipairs(def.units) do
                assert.is_nil(seen[u.id], cat .. "." .. u.id); seen[u.id] = true
                assert.is_string(u.name); assert.is_string(u.sym)
                assert.is_true(u.f ~= nil or (u.to ~= nil and u.from ~= nil))
            end
            assert.is_true(seen[def.default_from] and seen[def.default_to], cat)
        end
    end)

    it("uses the exact definitions", function()
        near(25.4, conv("length", "in", "mm", 1))
        near(12, conv("length", "ft", "in", 1))
        near(1609.344, conv("length", "mi", "m", 1))
        near(0.45359237, conv("mass", "lb", "kg", 1))
        near(16, conv("mass", "lb", "oz", 1))
        near(14, conv("mass", "st", "lb", 1))
        near(3.785411784, conv("volume", "galus", "L", 1))
        near(231, conv("volume", "galus", "in3", 1))
        near(4.54609, conv("volume", "galuk", "L", 1))
        near(20, conv("volume", "ptuk", "flozuk", 1))
        near(1.609344, conv("speed", "mph", "kmh", 1))
        near(640, conv("area", "mi2", "acre", 1))
        near(3.6, conv("energy", "kWh", "MJ", 1))
        near(4.184, conv("energy", "kcal", "kJ", 1))
        near(1.01325, conv("pressure", "atm", "bar", 1))
        near(14.503773773, conv("pressure", "bar", "psi", 1), 1e-9)
        near(760, conv("pressure", "atm", "torr", 1))
        near(1073741824, conv("data", "GiB", "B", 1))
        near(0.931322574615, conv("data", "GB", "GiB", 1), 1e-11)
        near(1000, conv("data", "Gbit", "Mbit", 1))
        near(math.pi, conv("angle", "deg", "rad", 180))
        near(400, conv("angle", "turn", "grad", 1))
        near(1440, conv("time", "d", "min", 1))
    end)

    it("converts temperatures", function()
        near(32, conv("temperature", "C", "F", 0))
        near(212, conv("temperature", "C", "F", 100))
        near(-40, conv("temperature", "F", "C", -40))
        near(273.15, conv("temperature", "C", "K", 0))
        near(0, conv("temperature", "K", "F", 255.3722222222222), 1e-9)
        near(491.67, conv("temperature", "C", "R", 0))
        near(37, conv("temperature", "F", "C", 98.6), 1e-12)
    end)

    it("inverts fuel consumption", function()
        near(20, conv("fuel", "l100", "kml", 5))
        near(5, conv("fuel", "kml", "l100", 20))
        near(235.2145833333, conv("fuel", "l100", "mpgus", 1), 1e-9)
        near(282.4809363, conv("fuel", "l100", "mpguk", 1), 1e-9)
        near(4.7, conv("fuel", "mpgus", "l100", conv("fuel", "l100", "mpgus", 4.7)))
        -- 0 L/100 km is infinitely efficient, not an error
        assert.equal(math.huge, conv("fuel", "l100", "kml", 0))
        assert.equal(0, conv("fuel", "kml", "l100", math.huge))
    end)
end)
