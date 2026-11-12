-- ForgeLayout: pages built as sections, shown in the addon's window in two
-- columns and in AddOn Options (ClassicAPI) in one. Load after ForgeUI.lua.
-- First used by FostercareTweaks 1.15.0; see README.md, "Pages and AddOn Options".
local _, ns = ...
local UI = ns.UI

local LEFT, RIGHT, SIDE = 28, 264, 208      -- the window's columns (README layout grid)
local START, GAP, NARROW = -98, 14, 460     -- first line under the tabs; gap above a heading
UI.L, UI.R = 1, 2                           -- the columns

-- A page is built top to bottom as sections of one or two columns. An item is
-- a group of regions placed together, or a block with place(x, y, width) that
-- places itself and returns its height. Under 460 wide the second column goes
-- under the first and full-width items take the narrower width.
local Layout = {}
Layout.__index = Layout

function UI.NewLayout()
    return setmetatable({ flows = {} }, Layout)
end

function Layout:Flow(page)
    self.flows[page] = self.flows[page] or { sections = {}, footers = {} }
    return self.flows[page]
end

-- Starts a section: two columns, or one across the page (full).
function Layout:Section(page, full)
    table.insert(self:Flow(page).sections, { full = full, {}, {} })
end

-- item: regions = { { region, point, relativePoint, dx, dy } } and height (a
-- number or function(width)), or place(x, y, width) -> height. Options: before
-- (a number, or { two columns, one column }), indent, heading, fill (a region
-- whose width follows the column).
function Layout:Add(page, column, item)
    local sections = self:Flow(page).sections
    if #sections == 0 then self:Section(page) end
    local section = sections[#sections]
    table.insert(section[section.full and UI.L or column], item)
    return item
end

local function Place(page, item, x, y, width)
    if item.place then return item.place(x, y, width) end
    for _, r in ipairs(item.regions) do
        r[1]:ClearAllPoints()
        r[1]:SetPoint(r[2], page, r[3], x + r[4], y + r[5])
    end
    if item.fill then item.fill:SetWidth(width) end
    if type(item.height) == "function" then return item.height(width) end
    return item.height
end

-- Items top to bottom from y; a heading keeps a gap above it, and nothing adds
-- space right under a heading.
local function Stack(page, items, x, width, y, narrow)
    local previous
    for _, item in ipairs(items) do
        local before = item.before or 0
        if type(before) == "table" then before = before[narrow and 2 or 1] end
        if item.heading and y ~= START then before = GAP end
        if previous and previous.heading then before = 0 end
        local indent = item.indent or 0
        y = y - before
        y = y - Place(page, item, x + indent, y, width - indent)
        previous = item
    end
    return y
end

-- Places a page for its width and returns its height. Footer buttons sit along
-- the bottom in two columns, and under the page, one per line, in one.
function Layout:Place(page, width)
    local flow = self:Flow(page)
    local narrow = width < NARROW
    local inner = narrow and width - LEFT - 12 or width - 2 * LEFT
    local y = START
    for _, section in ipairs(flow.sections) do
        if section.full then
            y = Stack(page, section[UI.L], LEFT, inner, y, narrow)
        elseif narrow then
            y = Stack(page, section[UI.R], LEFT, inner, Stack(page, section[UI.L], LEFT, inner, y, true), true)
        else
            y = math.min(Stack(page, section[UI.L], LEFT, SIDE, y), Stack(page, section[UI.R], RIGHT, SIDE, y))
        end
    end
    if narrow then
        y = y - 6
        for _, footer in ipairs(flow.footers) do
            footer.button:ClearAllPoints()
            if footer.button:IsShown() then
                footer.button:SetPoint("TOPLEFT", page, "TOPLEFT", LEFT, y - 8)
                y = y - 30
            end
        end
        return 24 - y
    end
    for _, footer in ipairs(flow.footers) do
        footer.button:ClearAllPoints()
        footer.button:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", footer.x, 18)
    end
    return 56 - y
end

-- Items for the ForgeUI widgets, each made at (0, 0) -------------------------------
function Layout:Heading(page, column, text)
    local label = UI.Heading(page, text, 0, 0)
    self:Add(page, column, { heading = true, height = 20, regions = { { label, "TOPLEFT", "TOPLEFT", 0, 0 } } })
    return label
end

-- UI.Switch sits 2 below its line.
function Layout:Switch(page, column, widget, options)
    options = options or {}
    options.height, options.regions = 26, { { widget, "TOPLEFT", "TOPLEFT", 0, -2 } }
    self:Add(page, column, options)
    return widget
end

function Layout:Button(page, column, button, options)
    options = options or {}
    options.height, options.regions = 24, { { button, "TOPLEFT", "TOPLEFT", 0, 0 } }
    self:Add(page, column, options)
    return button
end

-- A slider made SIDE wide: its label, the bar 16 below, the value at its right end.
function Layout:Slider(page, column, slider, options)
    options = options or {}
    options.height, options.regions = 42, {
        { slider.label, "TOPLEFT", "TOPLEFT", 0, 0 },
        { slider, "TOPLEFT", "TOPLEFT", 0, -16 },
        { slider.valueText, "TOPRIGHT", "TOPLEFT", SIDE, 0 },
    }
    self:Add(page, column, options)
    return slider
end

-- Hint text fills its column; its height follows the lines it wraps to.
function Layout:Hint(page, column, text, options)
    local label = UI.Label(page, text, 0, 0, "GameFontDisableSmall")
    options = options or {}
    options.before = options.before or 8
    options.fill, options.regions = label, { { label, "TOPLEFT", "TOPLEFT", 0, 0 } }
    options.height = function(width)
        return 13 * math.max(1, math.ceil((label:GetStringWidth() or 0) * 1.08 / width))
    end
    self:Add(page, column, options)
    return label
end

-- A footer button made at (0, 0); x is its place along the window's bottom.
function Layout:Footer(page, button, x)
    table.insert(self:Flow(page).footers, { button = button, x = x })
    return button
end

-- Moves a slider's three regions; for blocks that place their own sliders.
function UI.MoveSlider(slider, parent, x, y, width)
    slider.label:ClearAllPoints(); slider.label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    slider:SetWidth(width)
    slider.valueText:ClearAllPoints(); slider.valueText:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
end

-- AddOn Options ----------------------------------------------------------------------
-- The addon's entry, and one category per page in a scroll frame. A page lives in
-- one place at a time: it moves into the category that opens and back into the
-- window when that closes. spec: name, text (the entry's line), open (opens the
-- window), panel, pages, tabs ({ label }), layout, refresh (the addon's refresh,
-- which calls book:Place), and optional select(index) and hide(index).
local SHIFT = -START - 14                   -- the window's title and tabs above each page

function UI.Book(spec)
    local book = { spec = spec, hosts = {} }
    local panel, pages = spec.panel, spec.pages

    local entry = CreateFrame("Frame", spec.name .. "OptionsEntry")
    entry.name = spec.name
    local title = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", entry, "TOPLEFT", 16, -16)
    title:SetText(spec.name)
    local text = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetText(spec.text or ("Open a page under " .. spec.name .. ", or the settings window."))
    local open = UI.Button(spec.name .. "OptionsOpen", entry, "Open settings window", 16, -70, 172, function()
        if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        spec.open()
    end)
    UI.Select(open, true)
    InterfaceOptions_AddCategory(entry)

    for index, tab in ipairs(spec.tabs) do
        local host = CreateFrame("Frame", spec.name .. "Options" .. index)
        host.name, host.parent = tab.label, spec.name
        local scroll = CreateFrame("ScrollFrame", spec.name .. "Options" .. index .. "Scroll", host, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -8)
        scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -28, 8)
        local holder = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(holder)
        host.scroll, host.holder = scroll, holder
        -- The window sizes the category after showing it: place the page again then.
        scroll:SetScript("OnSizeChanged", function() if book.hosted == index then spec.refresh() end end)
        host:SetScript("OnShow", function()
            if panel:IsShown() then panel:Hide() end
            book.hosted = index
            if spec.select then spec.select(index) end
            local page = pages[index]
            page:SetParent(holder); page:ClearAllPoints()
            page:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, SHIFT)
            page:Show()
            spec.refresh()
        end)
        host:SetScript("OnHide", function()
            if book.hosted == index then book.hosted = nil end
            if spec.hide then spec.hide(index) end
            local page = pages[index]
            page:Hide(); page:SetParent(panel); page:ClearAllPoints(); page:SetAllPoints(panel)
        end)
        book.hosts[index] = host
        InterfaceOptions_AddCategory(host)
    end

    -- A page back from AddOn Options is hidden even when its tab is the active one.
    function book:ShowInWindow(index)
        if InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame:Hide() end
        pages[index]:Show()
    end

    function book:Shown() return panel:IsShown() or self.hosted ~= nil end

    -- Places the window's page (index) and the category's; call at the end of refresh.
    function book:Place(index)
        if panel:IsShown() then
            local height = spec.layout:Place(pages[index], panel.width)
            spec.tabs[index].height = height
            panel:SetHeight(height)
        end
        local host = self.hosts[self.hosted]
        if host then
            local width = host.scroll:GetWidth()
            if not width or width < 200 then width = 360 end
            local page = pages[self.hosted]
            page:SetWidth(width); host.holder:SetWidth(width)
            local height = spec.layout:Place(page, width)
            page:SetHeight(height); host.holder:SetHeight(height - SHIFT)
        end
    end

    return book
end
