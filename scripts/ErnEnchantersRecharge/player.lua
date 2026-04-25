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
local MOD_NAME     = require("scripts.ErnEnchantersRecharge.ns")
local core         = require("openmw.core")
local localization = core.l10n(MOD_NAME)
local pself        = require("openmw.self")
local ui           = require("openmw.ui")
local types        = require("openmw.types")
local util         = require("openmw.util")
local async        = require("openmw.async")
local ambient      = require("openmw.ambient")
local input        = require("openmw.input")

local interfaces   = require('openmw.interfaces')

local topic        = string.lower(localization("topic"))

pself.type.addTopic(pself, topic)

---@class RechargeEntity
---@field charge number
---@field capacity number
---@field record any
---@field item any

---comment
---@param item any
---@param record any
---@return RechargeEntity?
local function missingCharge(item, record)
    if record.enchant == nil then
        return nil
    end
    local enchantRecord = core.magic.enchantments.records[record.enchant]
    if enchantRecord.type == core.magic.ENCHANTMENT_TYPE.CastOnce or enchantRecord.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        return nil
    end
    local data = types.Item.itemData(item)
    if not data or (data.enchantmentCharge == nil) then
        return nil
    end
    if data.enchantmentCharge >= enchantRecord.charge then
        return nil
    end
    return {
        charge = data.enchantmentCharge,
        capacity = enchantRecord.charge,
        record = record,
        item = item,
    }
end

---@param recharge RechargeEntity
---@return integer
local function cost(recharge, enchanter)
    local base = (recharge.capacity - recharge.charge) * 1.3
    local playerBarter = pself.type.stats.skills.mercantile(pself).modified
    local enchanterBarter = pself.type.stats.skills.mercantile(enchanter).modified

    return math.ceil(util.clamp(enchanterBarter / playerBarter, 1, 5) * base)
end

---@return RechargeEntity[]
local function getRechargableItems()
    local out = {}
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Weapon)) do
        local recharge = missingCharge(item, types.Weapon.record(item))
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Armor)) do
        local recharge = missingCharge(item, types.Armor.record(item))
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Clothing)) do
        local recharge = missingCharge(item, types.Clothing.record(item))
        if recharge then
            table.insert(out, recharge)
        end
    end
    table.sort(out, function(a, b) return a.record.name > b.record.name end)
    return out
end

local windowPosition = util.vector2(0.5, 0.5)
local windowSize = util.vector2(420, 450)
local itemSize = util.vector2(400, 32)
local viewportSize = util.vector2(420, 400)

local listHeaderLayout = {
    type = ui.TYPE.Flex,
    props = {
        arrange = ui.ALIGNMENT.Center,
        horizontal = true,
        autoSize = false,
        size = itemSize,
    },
    content = ui.content {
        {
            template = interfaces.MWUI.templates.textHeader,
            type = ui.TYPE.Text,
            name = "itemName",
            props = {
                text = localization("magicalItems"),
                textColor = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
                textAlignV = ui.ALIGNMENT.Center,
            },
            external = { grow = 1 }
        },
        {
            template = interfaces.MWUI.templates.textHeader,
            type = ui.TYPE.Text,
            name = "cost",
            props = {
                text = localization("cost"),
                textColor = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
                textAlignV = ui.ALIGNMENT.Center,
                textAlignH = ui.ALIGNMENT.Start,
                anchor = util.vector2(1, 0.5)
            }
        }
    },
}

---@param recharge RechargeEntity
---@return table
local function rechargableItemLayout(recharge, list, enchanter)
    local layout = {
        type = ui.TYPE.Flex,
        props = {
            name = "row_" .. recharge.record.name,
            arrange = ui.ALIGNMENT.Center,
            horizontal = true,
            autoSize = false,
            size = itemSize,
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                name = "itemIcon",
                props = {
                    resource = ui.texture {
                        path = recharge.record.icon
                    },
                    size = util.vector2(32, 32)
                },
            },
            {
                template = interfaces.MWUI.templates.textHeader,
                type = ui.TYPE.Text,
                name = "itemName",
                props = {
                    text = recharge.record.name,
                    textColor = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
                    textAlignV = ui.ALIGNMENT.Center,
                },
                external = { grow = 1 }
            },
            {
                template = interfaces.MWUI.templates.textHeader,
                type = ui.TYPE.Text,
                name = "cost",
                props = {
                    text = tostring(cost(recharge, enchanter)),
                    textColor = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
                    textAlignV = ui.ALIGNMENT.Center,
                    textAlignH = ui.ALIGNMENT.Start,
                    anchor = util.vector2(1, 0.5)
                }
            }
        },
    }

    layout.events = {
        mousePress = async:callback(function(e)
            if e.button == 1 then
                ambient.playSound("menu click")
                ui.showMessage("Mouse press: " .. recharge.record.name)
            end
        end),
    }


    return layout
end

local window
local items = {}

-- close window
local function UiModeChanged(data)
    if window ~= nil and ((data.newMode == nil) or (data.newMode ~= "Interface")) then
        window:destroy()
        window = nil
        items = {}
    end
end

---@type VirtualListExt
local List = require("scripts.ErnEnchantersRecharge.VirtualList.virtual_list.extras").VirtualListExt




local function openRechargeWindow(enchanter)
    items = getRechargableItems()
    print("Found " .. #items .. " rechargeable items.")

    interfaces.UI.addMode("Interface", { windows = {} })
    -- Note the list must know the sizes involved to do its math.
    local list = List.create({
        viewportSize = viewportSize,
        itemSize = itemSize,
        itemCount = #items,
        itemLayout = function(i, list)
            return rechargableItemLayout(items[i], list, enchanter)
        end,
    })

    -- Optionally we can set a key press handler for the list.
    list:setKeyPressHandler({
        setSelectedIndex = function(i)
            list:changeSelection(i)
            ui.showMessage("Key press: " .. items[i])
        end,
    })

    -- Put our list in a bordered window with a black background.
    window = ui.create({
        layer = "Windows",
        type = ui.TYPE.Image,
        template = interfaces.MWUI.templates.borders,
        props = {
            size = windowSize,
            anchor = windowPosition,
            relativePosition = windowPosition,
            resource = ui.texture({ path = "black" }),
        },
        content = ui.content(
            {
                listHeaderLayout,
                list:getElement(),
            }
        ),
    })
end




return {
    eventHandlers = {
        UiModeChanged = UiModeChanged,
        DialogueResponse = function(e)
            print(e.recordId)
            if e.recordId == topic then
                openRechargeWindow(e.actor)
            end
        end
    },
    engineHandlers = {
        -- Optional mouse wheel handling for scrolling.
        onMouseWheel = List.getMouseWheelHandler(),
    },
}
