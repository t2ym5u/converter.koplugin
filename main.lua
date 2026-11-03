--[[--
Unit converter: units, cooking measures, oven temperatures, ECB exchange
rates, world clock, Roman numerals and number bases, on one screen.

Files:
  catalog.lua    the categories behind one interface (lazy-loads the rest)
  units.lua      physical units (exact factors)
  cooking.lua    kitchen measures per ingredient, oven temperatures
  currency.lua   ECB rates: parsing, bundled snapshot, conversion
  timezones.lua  cities and DST rules
  numtools.lua   Roman numerals, number bases
  numfmt.lua     number formatting, keypad input buffer
  screen.lua     the UI
--]]

-- Add the plugin dir and game-common to the Lua path.
local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase = require("plugin_base")
local _          = require("i18n")

require("i18n").extend(lrequire("i18n_fr"))
local ConverterScreen = lrequire("screen")

local Converter = PluginBase:extend{
    -- MUST equal the plugin directory's basename (see _skeleton.koplugin).
    name      = "converter",
    menu_text = _("Unit converter"),
    menu_hint = "tools",
}

function Converter:createScreen()
    return ConverterScreen:new{ plugin = self }
end

-- A utility, not a game: its own entry in the Tools menu, as Dashboard,
-- Plugin Manager and Book Drop have, rather than a place under Tools →
-- Games (PluginBase's default).
function Converter:addToMainMenu(menu_items)
    menu_items.converter = {
        text         = self.menu_text,
        sorting_hint = "tools",
        callback     = function() self:showGame() end,
    }
end

return Converter
