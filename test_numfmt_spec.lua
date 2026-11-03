local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("numfmt", function()
    local F = require("numfmt")
    local NBSP = "\u{00A0}"

    it("formats with significant digits and trims zeros", function()
        assert.equal("0", F.format(0))
        assert.equal("12", F.format(12.000000000000002))
        assert.equal("0.3048", F.format(0.3048))
        assert.equal("3.280839895", F.format(3.2808398950131))
        assert.equal("3.28084", F.format(3.2808398950131, { sig = 6 }))
        assert.equal("−40", F.format(-40))
        assert.equal("0.000001", F.format(1e-6))
        assert.equal("100", F.format(99.99999999999))
    end)

    it("uses the language's separators", function()
        local dec, grp = F.separators("fr")
        assert.equal("1" .. NBSP .. "234" .. NBSP .. "567,5", F.format(1234567.5, { dec = dec, group = grp }))
        dec, grp = F.separators("en")
        assert.equal("1,234,567.5", F.format(1234567.5, { dec = dec, group = grp }))
        assert.equal("1234.5", F.format(1234.5, { dec = dec, group = grp }))
        assert.equal("12,345", F.format(12345, { dec = dec, group = grp }))
    end)

    it("writes huge and tiny values with a power of ten", function()
        assert.equal("1.602176634×10⁻¹⁹", F.format(1.602176634e-19))
        assert.equal("6,02×10²³", F.format(6.02e23, { dec = "," }))
        assert.equal("1×10¹⁵", F.format(1e15))
        assert.equal("—", F.format(math.huge))
        assert.equal("—", F.format(0 / 0))
    end)

    it("edits the input buffer", function()
        local b = ""
        for _, k in ipairs({ "0", "0", "1", ".", "5", ".", "2" }) do b = F.press(b, k) end
        assert.equal("1.52", b)
        assert.equal("-1.52", F.press(b, "±"))
        assert.equal("1.52", F.press(F.press(b, "±"), "±"))
        assert.equal("1.5", F.press(b, "⌫"))
        assert.equal("", F.press(b, "C"))
        assert.equal("0.", F.press("", "."))
        assert.equal("-0.", F.press("-", "."))
        local long = string.rep("9", F.MAX_INPUT)
        assert.equal(long, F.press(long, "9"))
    end)

    it("parses and shows the buffer", function()
        assert.is_nil(F.parse("")); assert.is_nil(F.parse("-")); assert.is_nil(F.parse("."))
        assert.equal(-2.5, F.parse("-2.5"))
        assert.equal(3, F.parse("3."))
        assert.equal("−2,5", F.displayInput("-2.5", ","))
        assert.equal("0", F.displayInput(""))
    end)

    it("turns a result back into a buffer", function()
        assert.equal("41.01049869", F.toBuffer(41.010498687664))
        assert.equal("-3", F.toBuffer(-3))
        assert.equal("", F.toBuffer(math.huge))
        assert.equal(F.parse(F.toBuffer(0.00012)), 0.00012)
    end)
end)
