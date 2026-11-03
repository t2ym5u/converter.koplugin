local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("currency", function()
    local C = require("currency")
    local function read(name)
        local f = assert(io.open(DIR .. name)); local s = f:read("*a"); f:close(); return s
    end

    it("parses the ECB daily feed", function()
        local t = assert(C.parse(read("test_ecb_sample.xml")))
        assert.equal("2026-11-03", t.date)
        assert.equal(1.1179, t.rates.USD)
        assert.equal(20275.02, t.rates.IDR)
        local n = 0; for _ in pairs(t.rates) do n = n + 1 end
        assert.equal(29, n)
        assert.is_true(C.valid(t))
    end)

    it("matches the bundled snapshot", function()
        local t = C.parse(read("test_ecb_sample.xml"))
        assert.same(t.rates, C.SNAPSHOT.rates)
        assert.equal(t.date, C.SNAPSHOT.date)
    end)

    it("accepts double quotes and attributes in any order", function()
        local xml = [[<Cube><Cube time="2027-01-04">
            <Cube rate="1.05" currency="USD"/><Cube currency="GBP" rate="0.85" />
            <Cube currency="JPY" rate="160"/><Cube currency="CHF" rate="0.95"/>
            <Cube currency="SEK" rate="11.2"/></Cube></Cube>]]
        local t = assert(C.parse(xml))
        assert.equal("2027-01-04", t.date)
        assert.equal(1.05, t.rates.USD)
        assert.equal(0.85, t.rates.GBP)
    end)

    it("rejects what is not a rate feed", function()
        assert.same({ nil, "empty" }, { C.parse("") })
        assert.same({ nil, "empty" }, { C.parse(nil) })
        assert.same({ nil, "no date" }, { C.parse("<html><body>Service unavailable</body></html>") })
        assert.same({ nil, "no rates" }, { C.parse("<Cube time='2026-01-01'><Cube currency='USD' rate='x'/></Cube>") })
    end)

    it("converts through the euro", function()
        local r = C.SNAPSHOT.rates
        assert.equal(1.1179, C.convert(1, "EUR", "USD", r))
        assert.is_true(math.abs(C.convert(1.1179, "USD", "EUR", r) - 1) < 1e-12)
        assert.is_true(math.abs(C.convert(1, "GBP", "USD", r) - 1.1179 / 0.83358) < 1e-12)
        assert.equal(5, C.convert(5, "CHF", "CHF", r))
        assert.is_nil(C.convert(1, "EUR", "XXX", r))
    end)

    it("prefers stored rates unless they are invalid or older than the snapshot", function()
        local newer = { date = "2027-02-01", rates = { USD = 1, GBP = 1, JPY = 1, CHF = 1, SEK = 1 } }
        assert.equal(newer, C.pick(newer))
        assert.equal(C.SNAPSHOT, C.pick({ date = "2025-01-01", rates = newer.rates }))
        assert.equal(C.SNAPSHOT, C.pick({ date = "2027-01-01", rates = { USD = -1 } }))
        assert.equal(C.SNAPSHOT, C.pick(nil))
        assert.equal(C.SNAPSHOT, C.pick("garbage"))
    end)

    it("lists the major currencies first", function()
        local codes = C.codes(C.SNAPSHOT.rates)
        assert.same({ "EUR", "USD", "GBP", "CHF", "JPY" }, { codes[1], codes[2], codes[3], codes[4], codes[5] })
        assert.equal(30, #codes)
        for _, c in ipairs(codes) do assert.is_string(C.NAMES[c], c) end
    end)
end)
