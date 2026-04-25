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
local myui         = require('scripts.ErnEnchantersRecharge.pcp.myui')

local interfaces   = require('openmw.interfaces')

local topic        = string.lower(localization("topic"))

pself.type.addTopic(pself, topic)

---@return integer
local function cost(charge, capacity, enchanter)
    local base = (capacity - charge) * 1.3
    local playerBarter = pself.type.stats.skills.mercantile(pself).modified
    local enchanterBarter = pself.type.stats.skills.mercantile(enchanter).modified

    return math.ceil(util.clamp(enchanterBarter / playerBarter, 1, 5) * base)
end

---@class RechargeEntity
---@field charge number
---@field capacity number
---@field cost number
---@field record any
---@field item any

---comment
---@param item any
---@param record any
---@return RechargeEntity?
local function missingCharge(item, record, enchanter)
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
        cost = cost(data.enchantmentCharge, enchantRecord.charge, enchanter)
    }
end

---@return RechargeEntity[]
local function getRechargableItems(enchanter)
    local out = {}
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Weapon)) do
        local recharge = missingCharge(item, types.Weapon.record(item), enchanter)
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Armor)) do
        local recharge = missingCharge(item, types.Armor.record(item), enchanter)
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Clothing)) do
        local recharge = missingCharge(item, types.Clothing.record(item), enchanter)
        if recharge then
            table.insert(out, recharge)
        end
    end
    table.sort(out, function(a, b) return a.record.name > b.record.name end)
    return out
end

local windowPosition = util.vector2(0.5, 0.5)
local windowSize = util.vector2(420, 500)
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

local function barLayout(ratio, relativeLength)
    return {
        type = ui.TYPE.Widget,
        name = 'bar',
        template = interfaces.MWUI.templates.borders,
        props = {
            relativeSize = util.vector2(relativeLength or 1, 0),
            size = util.vector2(0, 8)
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                name = 'barContainer',
                props = {
                    resource = ui.texture { path = 'white' },
                    relativePosition = util.vector2(0, 0),
                    relativeSize = util.vector2(1, 1),
                    alpha = 0.7,
                    color = util.color.rgb(0.1, 0.1, 0.1),
                },
                events = {},
            },
            {
                type = ui.TYPE.Image,
                name = 'barFill',
                props = {
                    resource = ui.texture { path = 'Textures/ErnEnchantersRecharge/horz_gradient.dds' },
                    anchor = util.vector2(0, 0),
                    --relativePosition = util.vector2(0, 1),
                    relativeSize = util.vector2(ratio, 1),
                    alpha = 0.7,
                    color = myui.textColors.magic_fill,
                },
            },
        }
    }
end

local function currentGold()
    return pself.type.inventory(pself):countOf("gold_001")
end

local currentGoldElement = ui.create {}
local function updateCurrentGoldElement()
    currentGoldElement.layout = {
        template = interfaces.MWUI.templates.textHeader,
        type = ui.TYPE.Text,
        name = "cost",
        props = {
            text = localization("currentGold", { gold = currentGold() }),
            textColor = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
            textAlignV = ui.ALIGNMENT.Center,
            textAlignH = ui.ALIGNMENT.End,
            relativePosition = util.vector2(1, 1),
            anchor = util.vector2(1, 1),
            position = util.vector2(-4, -4),
        }
    }
    currentGoldElement:update()
end
updateCurrentGoldElement()


---@param recharge RechargeEntity
local function doRecharge(recharge)
    local gp = currentGold()
    if gp <= recharge.cost then
        ambient.playSoundFile("sound\\ErnEnchantersRecharge\\cancel.mp3")
        return
    end
    core.sendGlobalEvent(MOD_NAME .. 'onRecharge', {
        player = pself,
        cost = recharge.cost,
        item = recharge.item
    })
end

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
            myui.padWidget(4, 0),
            {
                type = ui.TYPE.Flex,
                props = {
                    name = "row_" .. recharge.record.name,
                    arrange = ui.ALIGNMENT.Start,
                    horizontal = false,
                    size = itemSize,
                },
                external = { grow = 1 },
                content = ui.content {
                    {
                        template = interfaces.MWUI.templates.textHeader,
                        type = ui.TYPE.Text,
                        name = "itemName",
                        props = {
                            text = recharge.record.name,
                            textColor = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
                            textAlignV = ui.ALIGNMENT.Center,
                        },
                    },
                    myui.padWidget(0, 2),
                    barLayout(recharge.charge / recharge.capacity, 0.7),
                },
            },
            myui.padWidget(4, 0),
            {
                template = interfaces.MWUI.templates.textHeader,
                type = ui.TYPE.Text,
                name = "cost",
                props = {
                    text = tostring(recharge.cost),
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
                doRecharge(recharge)
                ui.showMessage("Mouse press: " .. recharge.record.name)
            end
        end),
    }


    return layout
end

local window
local items = {}

local function closeWindow()
    if window ~= nil then
        window:destroy()
        window = nil
        items = {}
        -- check if nothing is visible
        if interfaces.UI.getMode() == "Interface" then
            local somethingVisible = false
            for wind in pairs(interfaces.UI.getWindowsForMode("Interface")) do
                somethingVisible = somethingVisible or interfaces.UI.isWindowVisible(wind)
            end
            if not somethingVisible then
                interfaces.UI.removeMode("Interface")
            end
        end
    end
end

-- close window
local function UiModeChanged(data)
    if (data.newMode == nil) or (data.newMode ~= "Interface") then
        closeWindow()
    end
end

local cancelButtonElement = ui.create {}
local function updateCancelButtonElement()
    cancelButtonElement.layout = myui.createTextButton(
        cancelButtonElement,
        localization("cancel"),
        "normal",
        "cancelButton",
        {},
        util.vector2(60, 20),
        closeWindow)
    cancelButtonElement:update()
end
updateCancelButtonElement()


---@type VirtualListExt
local List = require("scripts.ErnEnchantersRecharge.VirtualList.virtual_list.extras").VirtualListExt


local stretchPaddingLayout = {
    name = 'stretchPadWidget',
    props = { size = util.vector2(1, 1) },
    external = { grow = 1 }
}

local function openRechargeWindow(enchanter)
    items = getRechargableItems(enchanter)
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
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    arrange = ui.ALIGNMENT.Center,
                    horizontal = false,
                    autoSize = false,
                    relativeSize = util.vector2(1, 1)
                    --size = itemSize,
                },
                content = ui.content {
                    listHeaderLayout,
                    stretchPaddingLayout,
                    list:getElement(),
                    stretchPaddingLayout,
                    cancelButtonElement
                }
            },
            currentGoldElement,
        }
    })
end

local function onUpdateUI()
    updateCurrentGoldElement()
    -- todo: remove the item from the list?
end



return {
    eventHandlers = {
        [MOD_NAME .. "onUpdateUI"] = onUpdateUI,
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
