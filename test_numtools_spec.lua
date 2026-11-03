local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("numtools", function()
    local N = require("numtools")

    it("writes Roman numerals", function()
        assert.equal("I", N.toRoman(1))
        assert.equal("IV", N.toRoman(4))
        assert.equal("XLII", N.toRoman(42))
        assert.equal("MCMLXXXIV", N.toRoman(1984))
        assert.equal("MMXXVI", N.toRoman(2026))
        assert.equal("MMMCMXCIX", N.toRoman(3999))
        assert.is_nil(N.toRoman(0)); assert.is_nil(N.toRoman(4000)); assert.is_nil(N.toRoman(2.5))
    end)

    it("reads Roman numerals, strictly", function()
        assert.equal(1984, N.fromRoman("MCMLXXXIV"))
        assert.equal(14, N.fromRoman("xiv"))
        for _, bad in ipairs({ "IIII", "VX", "IC", "MMMM", "", "ABC", "IXI", "VV" }) do
            assert.is_nil(N.fromRoman(bad), bad)
        end
    end)

    it("round-trips 1..3999", function()
        for n = 1, 3999 do assert.equal(n, N.fromRoman(N.toRoman(n))) end
    end)

    it("knows Roman prefixes", function()
        assert.is_true(N.isRomanPrefix("MC"))
        assert.is_true(N.isRomanPrefix("XI"))
        assert.is_false(N.isRomanPrefix("IIII"))
        assert.is_false(N.isRomanPrefix("VX"))
    end)

    it("converts bases", function()
        assert.equal(255, N.parseBase("FF", 16))
        assert.equal(255, N.parseBase("ff", 16))
        assert.equal(10, N.parseBase("1010", 2))
        assert.equal(511, N.parseBase("777", 8))
        assert.is_nil(N.parseBase("2", 2)); assert.is_nil(N.parseBase("G", 16)); assert.is_nil(N.parseBase("", 10))
        assert.equal("11111111", N.toBase(255, 2))
        assert.equal("FF", N.toBase(255, 16))
        assert.equal("0", N.toBase(0, 8))
        assert.equal("20000000000000", N.toBase(2 ^ 53, 16))
        assert.is_nil(N.parseBase("20000000000001", 16))
        for _, n in ipairs({ 1, 7, 100, 65535, 123456789, 2 ^ 40 + 3 }) do
            for _, b in ipairs({ 2, 8, 10, 16 }) do assert.equal(n, N.parseBase(N.toBase(n, b), b)) end
        end
    end)

    it("groups digits", function()
        assert.equal("1111 1111", N.groupDigits("11111111", 2))
        assert.equal("10 1010", N.groupDigits("101010", 2))
        assert.equal("1 234 567", N.groupDigits("1234567", 10))
        assert.equal("1234", N.groupDigits("1234", 10))
        assert.equal("DEAD BEEF", N.groupDigits("DEADBEEF", 16))
    end)
end)
