local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("timezones", function()
    local TZ = require("timezones")
    local H = 3600

    local function off(id, utc) return TZ.offset(TZ.city(id), utc) end

    -- Offset just before and just after a transition instant.
    local function flips(id, at, before, after)
        assert.equal(before * H, off(id, at - 1), id .. " before")
        assert.equal(after * H, off(id, at), id .. " at")
    end

    it("computes civil dates and weekdays", function()
        assert.equal(0, TZ.daysFromCivil(1970, 1, 1))
        assert.equal(1774746000, TZ.epoch(2026, 3, 29, 1, 0))
        local y, m, d = TZ.civilFromDays(TZ.daysFromCivil(2024, 2, 29))
        assert.same({ 2024, 2, 29 }, { y, m, d })
        for _, ymd in ipairs({ { 1999, 12, 31 }, { 2000, 3, 1 }, { 2100, 2, 28 }, { 2026, 11, 3 } }) do
            local a, b, c = TZ.civilFromDays(TZ.daysFromCivil(ymd[1], ymd[2], ymd[3]))
            assert.same(ymd, { a, b, c })
        end
        assert.equal(2, TZ.weekday(TZ.daysFromCivil(2026, 11, 3)))  -- a Tuesday
    end)

    it("finds n-th and last weekdays", function()
        local function ymd(days) local y, m, d = TZ.civilFromDays(days); return { y, m, d } end
        assert.same({ 2026, 3, 29 }, ymd(TZ.nthWeekday(2026, 3, 0, -1)))
        assert.same({ 2026, 3, 8 }, ymd(TZ.nthWeekday(2026, 3, 0, 2)))
        assert.same({ 2026, 11, 1 }, ymd(TZ.nthWeekday(2026, 11, 0, 1)))
        assert.same({ 2025, 10, 30 }, ymd(TZ.nthWeekday(2025, 10, 4, -1)))
        assert.same({ 2026, 12, 27 }, ymd(TZ.nthWeekday(2026, 12, 0, -1)))
    end)

    it("applies the EU rule at 01:00 UTC on the last Sundays of March and October", function()
        flips("paris", 1774746000, 1, 2)       -- 2026-03-29 01:00 UTC
        flips("paris", 1792890000, 2, 1)       -- 2026-10-25 01:00 UTC
        flips("london", 1774746000, 0, 1)
        flips("london", 1792890000, 1, 0)
        flips("athens", 1743296400, 2, 3)      -- 2025-03-30
        assert.equal(1 * H, off("paris", TZ.epoch(2026, 1, 15, 12)))
        assert.equal(2 * H, off("berlin", TZ.epoch(2026, 7, 14, 12)))
    end)

    it("applies the US rule at 02:00 local time", function()
        flips("newyork", TZ.epoch(2026, 3, 8, 7), -5, -4)
        flips("newyork", TZ.epoch(2026, 11, 1, 6), -4, -5)
        flips("losangeles", 1772964000, -8, -7)  -- 2026-03-08 10:00 UTC
        flips("losangeles", 1793523600, -7, -8)  -- 2026-11-01 09:00 UTC
        flips("chicago", TZ.epoch(2025, 3, 9, 8), -6, -5)
        flips("stjohns", TZ.epoch(2026, 3, 8, 5, 30), -3.5, -2.5)
        assert.equal(-7 * H, off("phoenix", TZ.epoch(2026, 7, 1, 12)))
        assert.equal(-10 * H, off("honolulu", TZ.epoch(2026, 7, 1, 12)))
    end)

    it("applies southern-hemisphere rules", function()
        flips("sydney", 1791043200, 10, 11)    -- 2026-10-04 02:00 AEST
        flips("sydney", 1775318400, 11, 10)    -- 2026-04-05 03:00 AEDT
        flips("adelaide", 1791043200 + 30 * 60, 9.5, 10.5)
        flips("auckland", 1790431200, 12, 13)  -- 2026-09-27 02:00 NZST
        flips("auckland", 1775311200, 13, 12)  -- 2026-04-05 03:00 NZDT
        assert.equal(11 * H, off("sydney", TZ.epoch(2026, 1, 1, 0)))
        assert.equal(10 * H, off("brisbane", TZ.epoch(2026, 1, 1, 0)))
        assert.equal(10 * H, off("sydney", TZ.epoch(2026, 7, 1, 0)))
    end)

    it("applies Egypt's rule", function()
        flips("cairo", 1745532000, 2, 3)       -- Fri 2025-04-25 00:00 EET
        flips("cairo", 1761858000, 3, 2)       -- Thu 2025-10-30 24:00 EEST
    end)

    it("leaves no-DST cities alone all year", function()
        for _, id in ipairs({ "tokyo", "delhi", "kathmandu", "tehran", "mexico", "saopaulo", "istanbul" }) do
            assert.equal(off(id, TZ.epoch(2026, 1, 10)), off(id, TZ.epoch(2026, 7, 10)), id)
        end
        assert.equal(5.75 * H, off("kathmandu", 0))
    end)

    it("converts a typed time between cities", function()
        local now = TZ.epoch(2026, 11, 3, 10, 0)  -- 11:00 in Paris
        local r = TZ.convert(TZ.city("paris"), TZ.city("newyork"), now, 9 * 60, 0)
        assert.same({ 3, 0, 0 }, { r.to_h, r.to_m, r.day_shift })  -- 09:00 Paris = 03:00 NY
        r = TZ.convert(TZ.city("paris"), TZ.city("tokyo"), now, 20 * 60, 0)
        assert.same({ 4, 0, 1 }, { r.to_h, r.to_m, r.day_shift })
        r = TZ.convert(TZ.city("tokyo"), TZ.city("losangeles"), now, 8 * 60, 0)
        assert.same({ 15, 0, -1 }, { r.to_h, r.to_m, r.day_shift })
        -- "Here" by offset; nil minutes = now
        r = TZ.convert(nil, TZ.city("delhi"), now, nil, 3600)
        assert.same({ 11, 0, 15, 30, 0 }, { r.from_h, r.from_m, r.to_h, r.to_m, r.day_shift })
    end)

    it("reads wall clocks across a DST change", function()
        -- 2026-03-29 03:30 in Paris is after the change: 01:30 UTC.
        assert.equal(TZ.epoch(2026, 3, 29, 1, 30), TZ.wallToUtc(TZ.city("paris"), TZ.epoch(2026, 3, 29, 3, 30)))
        assert.equal(TZ.epoch(2026, 3, 29, 0, 30), TZ.wallToUtc(TZ.city("paris"), TZ.epoch(2026, 3, 29, 1, 30)))
    end)

    it("formats offsets and reads the device offset", function()
        assert.equal("+5:30", TZ.formatOffset(19800))
        assert.equal("−3", TZ.formatOffset(-10800))
        assert.equal("±0", TZ.formatOffset(0))
        local fake = function(fmt)
            if fmt == "*t" then return { year = 2026, month = 1, day = 1, hour = 1, min = 0 } end
            return { year = 2025, month = 12, day = 31, hour = 23, min = 0 }
        end
        assert.equal(2 * H, TZ.deviceOffset(0, fake))
    end)

    it("has about forty cities with unique ids", function()
        local seen = {}
        for _, c in ipairs(TZ.CITIES) do
            assert.is_nil(seen[c.id]); seen[c.id] = true
            assert.is_true(c.dst == nil or TZ.RULES[c.dst] ~= nil)
        end
        assert.is_true(#TZ.CITIES >= 40)
    end)
end)
