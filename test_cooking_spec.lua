local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("cooking", function()
    local Cooking = require("cooking")
    local function u(id) for _, x in ipairs(Cooking.UNITS) do if x.id == id then return x end end end
    local function o(id) for _, x in ipairs(Cooking.OVEN_UNITS) do if x.id == id then return x end end end
    local function near(e, g, tol) assert.is_true(math.abs(e - g) <= (tol or 1e-9), ("expected %.10g got %.10g"):format(e, g)) end

    it("gives the chart weights for one US cup", function()
        near(120, Cooking.convert(1, u("cupus"), u("g"), "flour"))
        near(198, Cooking.convert(1, u("cupus"), u("g"), "sugar"))
        near(113, Cooking.convert(0.5, u("cupus"), u("g"), "butter"))
        near(21, Cooking.convert(1, u("tbspus"), u("g"), "honey"))
        near(236.5882365, Cooking.convert(1, u("cupus"), u("g"), "water"))
    end)

    it("converts within volumes and masses without the density", function()
        near(3, Cooking.convert(1, u("tbspus"), u("tspus"), "flour"))
        near(16, Cooking.convert(1, u("cupus"), u("tbspus"), "cocoa"))
        near(3, Cooking.convert(1, u("tbsp"), u("tsp"), "flour"))
        near(1000, Cooking.convert(1, u("kg"), u("g"), "salt"))
        near(16, Cooking.convert(1, u("lb"), u("oz"), "rice"))
    end)

    it("round-trips mass and volume for every ingredient", function()
        local seen = {}
        for _, ing in ipairs(Cooking.INGREDIENTS) do
            assert.is_nil(seen[ing.id]); seen[ing.id] = true
            local g = Cooking.convert(250, u("ml"), u("g"), ing.id)
            near(250, Cooking.convert(g, u("g"), u("ml"), ing.id), 1e-9)
            assert.is_true(ing.g > 50 and ing.g < 400, ing.id)
        end
        assert.is_true(#Cooking.INGREDIENTS >= 20)
    end)

    it("converts oven temperatures", function()
        local function ov(v, a, b) return Cooking.ovenConvert(v, o(a), o(b)) end
        near(6, ov(180, "C", "th"))
        near(210, ov(7, "th", "C"))
        near(350, ov(4, "gas", "F"))
        near(275, ov(1, "gas", "F"))
        near(225, ov(0.25, "gas", "F"))
        near(0.5, ov(250, "F", "gas"))
        near(4, ov(ov(4, "gas", "C"), "C", "gas"))
        near(9, ov(475, "F", "gas"))
        near(356, ov(180, "C", "F"))
    end)

    it("formats gas marks", function()
        assert.equal("¼", Cooking.formatGas(0.25))
        assert.equal("½", Cooking.formatGas(0.51))
        assert.equal("4", Cooking.formatGas(4.02))
        assert.equal("4", Cooking.formatGas(4.24))
        assert.equal("¼", Cooking.formatGas(0.3))
        assert.equal("1", Cooking.formatGas(0.9))
        assert.equal("—", Cooking.formatGas(0 / 0))
    end)
end)
