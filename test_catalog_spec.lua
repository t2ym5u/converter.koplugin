local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("catalog", function()
    local Catalog = require("catalog")
    local cat = Catalog.new(require)

    it("builds every category with valid defaults", function()
        for _, id in ipairs(Catalog.ORDER) do
            local c = assert(cat:get(id), id)
            assert.is_string(Catalog.LABELS[id])
            assert.is_true(#c.units >= 2, id)
            assert.equal(c.default_from, Catalog.validUnit(c, c.default_from), id)
            assert.equal(c.default_to, Catalog.validUnit(c, c.default_to), id)
            assert.is_string(c.keyset(c.default_from))
        end
        assert.is_nil(cat:get("nope"))
    end)

    it("loads a category once", function()
        assert.equal(cat:get("length"), cat:get("length"))
    end)

    it("converts and formats numbers", function()
        local c = cat:get("length")
        local x = c.parse("10")
        assert.equal("32.80839895", c.format(c.convert(x, "m", "ft"), "ft", {}))
        local ck = cat:get("cooking")
        assert.equal("120", ck.format(ck.convert(1, "cupus", "g", { ingredient = "flour" }), "g", {}))
    end)

    it("rounds oven temperatures to what an oven offers", function()
        local o = cat:get("oven")
        assert.equal("6", o.format(o.convert(180, "C", "th"), "th", {}))
        assert.equal("6,5", o.format(o.convert(195, "C", "th"), "th", { dec = "," }))
        assert.equal("4", o.format(o.convert(180, "C", "gas"), "gas", {}))
        assert.equal("177", o.format(o.convert(350, "F", "C"), "C", {}))
    end)

    it("formats money with two decimals", function()
        local c = cat:get("currency")
        assert.equal("111.79", c.format(c.convert(100, "EUR", "USD"), "USD", {}))
        assert.equal("0.0000493", c.format(c.convert(1, "IDR", "EUR"), "EUR", {}))
        assert.equal(30, #c.units)
        c.setRates({ USD = 1.1 })
        assert.same({ "EUR", "USD" }, { c.units[1].id, c.units[2].id })
        assert.equal("USD", Catalog.validUnit(c, "GBP", "USD"))
        c.setRates(require("currency").SNAPSHOT.rates)
    end)

    it("handles Roman numerals both ways", function()
        local c = cat:get("roman")
        local b = ""
        for _, k in ipairs({ "1", "9", "8", "4" }) do b = c.press(b, k, "arabic") end
        assert.equal("MCMLXXXIV", c.format(c.parse(b, "arabic"), "roman"))
        assert.equal("3999", c.press("399", "9", "arabic"))
        assert.equal("400", c.press("400", "0", "arabic"))   -- 4000 is too big
        assert.equal("4", c.press("", "4", "arabic"))
        assert.equal("", c.press("", "0", "arabic"))
        assert.equal("XI", c.press("XI", "M", "roman"))      -- XIM is not a numeral
        assert.equal(1984, c.parse("MCMLXXXIV", "roman"))
        assert.is_nil(c.parse("IIII", "roman"))
        assert.equal("roman", c.keyset("roman"))
    end)

    it("handles number bases", function()
        local c = cat:get("bases")
        assert.equal("1111 1111", c.format(c.parse("255", "dec"), "bin", {}))
        assert.equal("FF", c.format(c.parse("11111111", "bin"), "hex", {}))
        assert.equal("1", c.press("1", "2", "bin"))
        assert.equal("A", c.press("0", "A", "hex"))
        assert.equal("base16", c.keyset("hex"))
    end)

    it("reads typed times", function()
        assert.equal(9 * 60, Catalog.parseClock("9"))
        assert.equal(9 * 60 + 30, Catalog.parseClock("930"))
        assert.equal(23 * 60 + 59, Catalog.parseClock("2359"))
        assert.equal(1 * 60 + 27, Catalog.parseClock("127"))  -- H:MM first
        assert.equal(18 * 60 + 7, Catalog.parseClock("187"))  -- 1:87 impossible, so 18:07
        assert.is_nil(Catalog.parseClock("2460"))
        assert.is_nil(Catalog.parseClock(""))
        assert.equal("09:30", Catalog.displayClock("930"))
        assert.equal("2", Catalog.pressClock("2", "9"))       -- no hour 29, no 2:9x
        assert.equal("23", Catalog.pressClock("2", "3"))
        assert.equal("1234", Catalog.pressClock("123", "4"))
        assert.equal("1234", Catalog.pressClock("1234", "5"))
    end)
end)
