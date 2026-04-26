local ui = require("openmw.ui")
local util = require("openmw.util")
local async = require("openmw.async")
local input = require("openmw.input")
local ambient = require("openmw.ambient")

local I = require("openmw.interfaces")

local styles = require(... .. ".styles") --[[@as Styles]]

local focusedElement = nil
local DIRECTION = { UP = -1, DOWN = 1 }

---@alias Range { start: number, stop: number }
---@alias ItemLayoutFn fun(index: number, list: VirtualList, oldLayout: Layout?): Layout

---@class VirtualList
local VirtualList = {}
VirtualList.__index = VirtualList

function VirtualList.new(element, itemWidth, itemHeight, itemCount, itemLayout, style)
    return setmetatable({
        element = element,
        itemWidth = itemWidth,
        itemHeight = itemHeight,
        itemCount = itemCount,
        itemLayout = itemLayout,
        currentY = 0,
        visibleRange = nil,
        style = style,
    }, VirtualList)
end

function VirtualList.from(element)
    local scrollData = assert(element.layout.userData.scrollData)
    assert(getmetatable(scrollData) == VirtualList)
    return scrollData
end

function VirtualList:getElement()
    return self.element
end

function VirtualList:getContentContainer()
    return self.element.layout.content["contentContainer"]
end

function VirtualList:getContent()
    return self:getContentContainer().content
end

function VirtualList:getScrollbar()
    local content = self.element.layout.content
    local container = content and content["scrollbarContainer"]
    local scrollbar = container and container.content["scrollbar"]
    return scrollbar
end

function VirtualList:getItemTop(index)
    return (index - 1) * self.itemHeight
end

function VirtualList:getVisibleHeight()
    return self.element.layout.props.size.y - styles.VIEWPORT_INSET
end

function VirtualList:getMaxScrollDistance()
    return self.itemCount * self.itemHeight - self:getVisibleHeight()
end

function VirtualList:getScrollOffset()
    return self.currentY * self:getMaxScrollDistance()
end

function VirtualList:calcVisibleRange()
    if self.itemCount == 0 then
        return { start = 1, stop = 0 }
    end

    local itemHeight = self.itemHeight
    local totalHeight = itemHeight * self.itemCount

    local numVisibleItems = math.ceil(self:getVisibleHeight() / itemHeight)
    local visibleItemsHeight = itemHeight * numVisibleItems
    local emptyHeight = math.max(totalHeight - visibleItemsHeight, 0)

    local visibleStart = emptyHeight * self.currentY
    local numSlots = numVisibleItems + 1

    local startIndex = 1 + math.floor(visibleStart / itemHeight)
    local stopIndex = startIndex + numSlots - 1

    if stopIndex > self.itemCount then
        stopIndex = self.itemCount
        startIndex = math.max(1, stopIndex - numSlots + 1)
    end

    return { start = startIndex, stop = stopIndex }
end

function VirtualList:getVisibleRange()
    if not self.visibleRange then
        self.visibleRange = self:calcVisibleRange()
    end
    return self.visibleRange
end

function VirtualList:applyItemProps(layout, index)
    layout.props.size = util.vector2(self.itemWidth, self.itemHeight)
    layout.props.position = util.vector2(0, self:getItemTop(index))
end

-- 🔥 CORE FIX: PURE FUNCTIONAL SYNC (NO REUSE TRUST)
function VirtualList:syncVisibleItems()
    local newRange = self:calcVisibleRange()
    self.visibleRange = newRange

    local content = self:getContent()

    -- clear everything
    for i = #content, 1, -1 do
        content[i] = nil
    end

    if newRange.start > newRange.stop then
        return
    end

    for i = newRange.start, newRange.stop do
        print("getting new layout for idx "..tostring(i))
        local layout = self.itemLayout(i, self, nil) -- 🔥 never reuse
        self:applyItemProps(layout, i)
        content:add(layout)
    end
    self.element:update()
end

function VirtualList:applyScrollPosition()
    local contentContainer = self:getContentContainer()
    contentContainer.props.position =
        util.vector2(0, -math.floor(self:getScrollOffset() + 0.5))

    local handleMaxY, handle = self:getScrollbarContext()
    if handle then
        handle.props.position = util.vector2(0, self.currentY * handleMaxY)
    end

    self:syncVisibleItems()
    self.element:update()
end

function VirtualList:scrollToIndex(index, mode)
    if index < 1 or index > self.itemCount then return end

    local maxScrollDistance = self:getMaxScrollDistance()
    if maxScrollDistance <= 0 then return end

    local itemTop = self:getItemTop(index)
    local targetY

    if mode == "top" then
        targetY = itemTop
    elseif mode == "bottom" then
        targetY = itemTop + self.itemHeight - self:getVisibleHeight()
    elseif mode == "center" then
        targetY = itemTop + self.itemHeight / 2 - self:getVisibleHeight() / 2
    elseif type(mode) == "number" then
        targetY = itemTop - mode
    else
        error("Invalid scroll mode")
    end

    self.currentY = util.clamp(targetY / maxScrollDistance, 0, 1)
    self:applyScrollPosition()
end

function VirtualList:applyScrollStep(direction, mode)
    local maxScrollDistance = self:getMaxScrollDistance()
    if maxScrollDistance <= 0 then return end

    local step = self.itemHeight
    if mode == "wheel" then
        step = step * styles.SCROLL_WHEEL_STEP_MULT
    end

    self.currentY = util.clamp(
        self.currentY + (step / maxScrollDistance) * direction,
        0, 1
    )

    self:applyScrollPosition()
end

function VirtualList:getScrollbarContext()
    local scrollbar = self:getScrollbar()
    if not scrollbar then return end

    local handle = scrollbar.content["handle"]
    local handleMaxY = scrollbar.props.size.y - handle.props.size.y

    return handleMaxY, handle, scrollbar
end

function VirtualList:createScrollbar()
    if self.style.autoHideScrollBar and (self:getMaxScrollDistance() <= 0) then
        return
    end

    local scrollbar = {
        template = I.MWUI.templates.borders,
        name = "scrollbar",
        props = {
            size = util.vector2(8, self.element.layout.props.size.y),
        },
        content = ui.content({
            {
                type = ui.TYPE.Image,
                name = "handle",
                props = {
                    resource = styles.SCROLL_CENTER_TEXTURE,
                    size = util.vector2(8, 32),
                },
            },
        }),
    }

    self:getContentContainer().content:add(scrollbar)
end

function VirtualList:rebuild(newItemCount, newItemHeight)
    if newItemCount then self.itemCount = newItemCount end
    if newItemHeight then self.itemHeight = newItemHeight end

    local container = self:getContentContainer()
    container.props.size = util.vector2(
        container.props.size.x,
        self.itemCount * self.itemHeight
    )
    container.props.position = util.vector2(0, 0)

    self.currentY = 0
    self.visibleRange = nil

    self:syncVisibleItems()
    self:createScrollbar()
    self.element:update()
end

function VirtualList.create(params)
    local visibleSize = params.viewportSize
    local style = styles.resolve(params.style or styles.STYLES.Compact)

    local list = ui.create({
        type = ui.TYPE.Widget,
        name = "virtualList",
        props = { size = visibleSize },
        content = ui.content({
            {
                name = "contentContainer",
                props = {
                    position = util.vector2(0, 0),
                    size = util.vector2(
                        visibleSize.x,
                        params.itemCount * params.itemSize.y
                    ),
                },
                content = ui.content({}),
            },
        }),
        userData = {},
    })

    list.layout.events = {
        focusGain = async:callback(function()
            focusedElement = list
        end),
        focusLoss = async:callback(function()
            if focusedElement == list then focusedElement = nil end
        end),
    }

    list.layout.userData.scrollData = VirtualList.new(
        list,
        params.itemSize.x,
        params.itemSize.y,
        params.itemCount,
        params.itemLayout,
        style
    )

    local scrollData = list.layout.userData.scrollData
    scrollData:rebuild()

    return scrollData
end

function VirtualList.getMouseWheelHandler()
    return function(vertical)
        if focusedElement and vertical ~= 0 then
            local dir = (vertical > 0) and DIRECTION.UP or DIRECTION.DOWN
            VirtualList.from(focusedElement):applyScrollStep(dir, "wheel")
        end
    end
end

return VirtualList
