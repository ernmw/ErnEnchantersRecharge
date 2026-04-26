--[[
ErnEnchantersRecharge for OpenMW.
Copyright (C) 2026 Erin Pentecost

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]
local MOD_NAME = require("scripts.ErnEnchantersRecharge.ns")
local core     = require("openmw.core")
local world    = require('openmw.world')
local types    = require('openmw.types')

local function onRecharge(data)
    -- increase the charges
    local itemData = types.Item.itemData(data.item)
    if not itemData or (itemData.enchantmentCharge == nil) then
        return nil
    end
    itemData.enchantmentCharge = data.capacity
    -- remove the money
    local gold = data.player.type.inventory(data.player):find("gold_001")
    gold:remove(data.cost)
    -- notify UI we are done
    data.player:sendEvent(MOD_NAME .. 'onUpdateUI', { item = data.item })
end

return {
    eventHandlers = {
        [MOD_NAME .. 'onRecharge'] = onRecharge,
    }
}
