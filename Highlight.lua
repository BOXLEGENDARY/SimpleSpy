local cloneref  = cloneref or function(...) return ... end
local TextService = cloneref(game:GetService("TextService"))
local RunService = cloneref(game:FindService("RunService"))

local Highlight = {}
Highlight.__index = Highlight

local COLORS = {
    background    = Color3.fromRGB(40, 44, 52),
    operator      = Color3.fromRGB(187, 85, 255), -- purple
    func          = Color3.fromRGB(97, 175, 239), -- blue
    string        = Color3.fromRGB(152, 195, 121), -- green
    number        = Color3.fromRGB(209, 154, 102), -- orange
    boolean       = Color3.fromRGB(86, 182, 194), -- teal-like
    object        = Color3.fromRGB(229, 192, 123), -- tan
    default       = Color3.fromRGB(224, 108, 117), -- red-ish for identifiers
    comment       = Color3.fromRGB(125, 130, 140), -- muted grey
    linenumber    = Color3.fromRGB(125, 130, 140),
    generic       = Color3.fromRGB(240, 240, 240),
}

local function rgbStr(c)
    return string.format("rgb(%d,%d,%d)", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
end

local PATTERNS = {
    operators = {"^(function)[^%w_]", "^(local)[^%w_]", "^(if)[^%w_]", "^(for)[^%w_]",
                 "^(while)[^%w_]", "^(then)[^%w_]", "^(do)[^%w_]", "^(else)[^%w_]",
                 "^(elseif)[^%w_]", "^(return)[^%w_]", "^(end)[^%w_]", "^(continue)[^%w_]",
                 "[^%w_](or)[^%w_]", "[^%w_](and)[^%w_]", "[^%w_](not)[^%w_]", "[^%w_](function)[^%w_]",
                 "[^%w_](local)[^%w_]", "[^%w_](if)[^%w_]", "[^%w_](for)[^%w_]", "[^%w_](while)[^%w_]",
                 "[^%w_](then)[^%w_]", "[^%w_](do)[^%w_]", "[^%w_](else)[^%w_]", "[^%w_](elseif)[^%w_]",
                 "[^%w_](return)[^%w_]", "[^%w_](end)[^%w_]"},
    strings = {{"\"", "\""}, {"'", "'"}, {"%[%[", "%]%]", true}},
    comments = {"%-%-%[%[[^%]%]]+%]?%]", "%-%-[^\n]+"},
    functions = {"[^%w_]([%a_][%a%d_]*)%s*%(", "^([%a_][%a%d_]*)%s*%(", "[:%.%(%[%p]([%a_][%a%d_]*)%s*%("},
    numbers = {"[^%w_](%d+[eE]?%d*)", "[^%w_](%.%d+[eE]?%d*)", "[^%w_](%d+%.%d+[eE]?%d*)", "^(%d+[eE]?%d*)", "^(%.%d+[eE]?%d*)", "^(%d+%.%d+[eE]?%d*)"},
    booleans = {"[^%w_](true)", "^(true)", "[^%w_](false)", "^(false)", "[^%w_](nil)", "^(nil)"},
    objects = {"[^%w_:]([%a_][%a%d_]*):", "^([%a_][%a%d_]*):"},
    other = {"[^_%s%w=>~<%-%+%*]", ">", "~", "<", "%-", "%+", "=", "%*"},
}

local function newInternalState()
    return {
        parentFrame = nil,
        scrollingFrame = nil,
        textFrame = nil,
        lineNumbersFrame = nil,
        tableContents = {}, -- array of {Char=string, Color=Color3, Line=number}
        offLimits = {}, -- intervals {start,end}
        largestX = 0,
        line = 1,
        lineSpace = 15,
        font = Enum.Font.Ubuntu,
        textSize = 14,
    }
end

local function addOffLimit(self, s, e)
    table.insert(self.offLimits, {s, e})
end

local function isOffLimits(self, index)
    for _, v in next, self.offLimits do
        if index >= v[1] and index <= v[2] then
            return true
        end
    end
    return false
end

local function gfind(str, pattern)
    return function()
        local start = 1
        return function()
            local s, e = str:find(pattern, start)
            if not s then return nil end
            start = e + 1
            return s, e
        end
    end
end

local function highlightRange(self, s, e, color)
    for i = s, e do
        if self.tableContents[i] then
            self.tableContents[i].Color = color
        end
    end
end

local function highlightPattern(self, patternArray, color)
    local str = self:getRaw()
    local step = 0
    for _, pattern in next, patternArray do
        local findIter = gfind(str, pattern)()
        while true do
            local s, e = findIter()
            if not s then break end
            step = step + 1
            if step % 1000 == 0 then RunService.Heartbeat:Wait() end
            if not isOffLimits(self, s) and not isOffLimits(self, e) then
                highlightRange(self, s, e, color)
            end
        end
    end
end

local function renderComments(self)
    local str = self:getRaw()
    local step = 0
    for _, pattern in next, PATTERNS.comments do
        local findIter = gfind(str, pattern)()
        while true do
            local s, e = findIter()
            if not s then break end
            step = step + 1
            if step % 1000 == 0 then RunService.Heartbeat:Wait() end
            if not isOffLimits(self, s) then
                addOffLimit(self, s, e)
                highlightRange(self, s, e, COLORS.comment)
            end
        end
    end
end

local function renderStrings(self)
    local tbl = self.tableContents
    local i = 1
    while i <= #tbl do
        local ch = tbl[i].Char
        if ch == "\"" or ch == "'" then
            -- quoted string
            local quote = ch
            local startIdx = i
            i = i + 1
            while i <= #tbl do
                local c = tbl[i].Char
                if c == "\\" then
                    i = i + 2 -- skip escaped char (if present)
                elseif c == quote then
                    -- close
                    addOffLimit(self, startIdx, i)
                    highlightRange(self, startIdx, i, COLORS.string)
                    break
                else
                    i = i + 1
                end
            end
        elseif ch == "[" and tbl[i+1] and tbl[i+1].Char == "[" then
            -- long bracket string [[ ... ]]
            local startIdx = i
            i = i + 2
            while i <= #tbl do
                if tbl[i].Char == "]" and tbl[i+1] and tbl[i+1].Char == "]" then
                    addOffLimit(self, startIdx, i+1)
                    highlightRange(self, startIdx, i+1, COLORS.string)
                    i = i + 2
                    break
                else
                    i = i + 1
                end
            end
        else
            i = i + 1
        end
    end
end

local function buildLineRichText(self, startIdx, endIdx)
    local pieces = {}
    local lastColor = nil
    for i = startIdx, endIdx do
        local ch = self.tableContents[i]
        local c = ch.Color or COLORS.default
        if lastColor ~= c then
            if lastColor then table.insert(pieces, "</font>") end
            table.insert(pieces, ("<font color=\"%s\">"):format(rgbStr(c)))
            lastColor = c
        end
        -- escape html special chars
        local char = ch.Char
        if char == "<" then char = "&lt;" elseif char == ">" then char = "&gt;"
        elseif char == '"' then char = "&quot;" elseif char == "&" then char = "&amp;"
        elseif char == "'" then char = "&apos;" end
        table.insert(pieces, char)
    end
    if lastColor then table.insert(pieces, "</font>") end
    return table.concat(pieces)
end

local function updateZIndex(parentFrame)
    for _, v in next, parentFrame:GetDescendants() do
        if v:IsA("GuiObject") then
            v.ZIndex = parentFrame.ZIndex
        end
    end
end

local function updateCanvasSize(self)
    self.scrollingFrame.CanvasSize = UDim2.new(0, math.max(1, self.largestX), 0, (self.line + 1) * self.lineSpace)
end

local function render(self)
    -- reset
    self.offLimits = {}
    self.line = 1
    self.largestX = 0
    self.textFrame:ClearAllChildren()
    self.lineNumbersFrame:ClearAllChildren()

    for _, ch in next, self.tableContents do
        ch.Color = COLORS.default
    end

    -- highlight passes
    highlightPattern(self, PATTERNS.functions, COLORS.func)
    highlightPattern(self, PATTERNS.numbers, COLORS.number)
    highlightPattern(self, PATTERNS.operators, COLORS.operator)
    highlightPattern(self, PATTERNS.objects, COLORS.object)
    highlightPattern(self, PATTERNS.booleans, COLORS.boolean)
    highlightPattern(self, PATTERNS.other, COLORS.generic)
    renderComments(self)
    renderStrings(self)

    -- build lines and create TextLabels
    local idx = 1
    local bufferStart = 1
    local rawStart = 1
    local lineCharCount = 0

    while idx <= #self.tableContents + 1 do
        local ch = self.tableContents[idx]
        if idx == #self.tableContents + 1 or (ch and ch.Char == "\n") then
            -- build line piece
            local rich = buildLineRichText(self, bufferStart, idx - 1)
            local rawStr = {}
            for j = bufferStart, idx - 1 do
                table.insert(rawStr, self.tableContents[j].Char)
            end
            local rawConcat = table.concat(rawStr)
            local x = TextService:GetTextSize(rawConcat, self.textSize, self.font, Vector2.new(math.huge, math.huge)).X + 60
            if x > self.largestX then self.largestX = x end

            -- create line TextLabel
            local lineText = Instance.new("TextLabel")
            lineText.TextXAlignment = Enum.TextXAlignment.Left
            lineText.TextYAlignment = Enum.TextYAlignment.Top
            lineText.Position = UDim2.new(0, 0, 0, self.line * self.lineSpace - self.lineSpace / 2)
            lineText.Size = UDim2.new(0, x, 0, self.textSize)
            lineText.RichText = true
            lineText.Font = self.font
            lineText.TextSize = self.textSize
            lineText.BackgroundTransparency = 1
            lineText.Text = rich
            lineText.Parent = self.textFrame

            -- line number
            if idx ~= #self.tableContents + 1 then
                local lineNumber = Instance.new("TextLabel")
                lineNumber.Text = tostring(self.line)
                lineNumber.Font = self.font
                lineNumber.TextSize = self.textSize
                lineNumber.Size = UDim2.new(1, 0, 0, self.lineSpace)
                lineNumber.TextXAlignment = Enum.TextXAlignment.Right
                lineNumber.TextColor3 = COLORS.linenumber
                lineNumber.Position = UDim2.new(0, 0, 0, self.line * self.lineSpace - self.lineSpace / 2)
                lineNumber.BackgroundTransparency = 1
                lineNumber.Parent = self.lineNumbersFrame
            end

            -- advance
            self.line = self.line + 1
            bufferStart = idx + 1
            if self.line % 5 == 0 then RunService.Heartbeat:Wait() end
        end
        idx = idx + 1
    end

    updateZIndex(self.parentFrame)
    updateCanvasSize(self)
end

function Highlight:init(frame)
    if typeof(frame) ~= "Instance" or not frame:IsA("Frame") then
        error("Initialization error: argument " .. typeof(frame) .. " is not a Frame Instance")
    end

    -- instance-specific state as fields on self
    self.state = newInternalState()
    self.parentFrame = frame
    self.scrollingFrame = Instance.new("ScrollingFrame")
    self.textFrame = Instance.new("Frame")
    self.lineNumbersFrame = Instance.new("Frame")

    local parentSize = frame.AbsoluteSize
    self.scrollingFrame.Size = UDim2.new(0, parentSize.X, 0, parentSize.Y)
    self.scrollingFrame.BackgroundColor3 = COLORS.background
    self.scrollingFrame.BorderSizePixel = 0
    self.scrollingFrame.ScrollBarThickness = 4

    self.textFrame.Size = UDim2.new(1, -40, 1, 0)
    self.textFrame.Position = UDim2.new(0, 40, 0, 0)
    self.textFrame.BackgroundTransparency = 1

    self.lineNumbersFrame.Size = UDim2.new(0, 25, 1, 0)
    self.lineNumbersFrame.BackgroundTransparency = 1

    self.textFrame.Parent = self.scrollingFrame
    self.lineNumbersFrame.Parent = self.scrollingFrame
    self.scrollingFrame.Parent = self.parentFrame

    -- map state fields to self for convenience
    self.tableContents = self.state.tableContents
    self.offLimits = self.state.offLimits
    self.largestX = self.state.largestX
    self.line = self.state.line
    self.lineSpace = self.state.lineSpace
    self.font = self.state.font
    self.textSize = self.state.textSize

    -- keep references to frames
    self.parentFrame = frame
    self.scrollingFrame = self.scrollingFrame
    self.textFrame = self.textFrame
    self.lineNumbersFrame = self.lineNumbersFrame

    -- connections
    frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        local newSize = frame.AbsoluteSize
        self.scrollingFrame.Size = UDim2.new(0, newSize.X, 0, newSize.Y)
    end)
    frame:GetPropertyChangedSignal("ZIndex"):Connect(function() updateZIndex(frame) end)

    -- initial empty render
    self:setRaw("")
end

function Highlight:setRaw(raw)
    raw = tostring(raw) .. "\n"
    self.tableContents = {}
    local lineIdx = 1
    for i = 1, #raw do
        local ch = raw:sub(i, i)
        table.insert(self.tableContents, {
            Char = ch,
            Color = COLORS.default,
            Line = lineIdx
        })
        if ch == "\n" then
            lineIdx = lineIdx + 1
        end
        if i % 1000 == 0 then RunService.Heartbeat:Wait() end
    end
    -- sync into state for internal functions
    self.state.tableContents = self.tableContents
    render(self)
end

function Highlight:getRaw()
    local out = {}
    for _, ch in next, self.tableContents do
        table.insert(out, ch.Char)
    end
    return table.concat(out)
end

function Highlight:getString()
    -- similar to original: return concatenation (chars trimmed to 1 char each)
    local out = {}
    for _, ch in next, self.tableContents do
        table.insert(out, ch.Char:sub(1,1))
    end
    return table.concat(out)
end

function Highlight:getTable()
    return self.tableContents
end

function Highlight:getSize()
    return #self.tableContents
end

function Highlight:getLine(lineNumber)
    if type(lineNumber) ~= "number" then return "" end
    local currentLine = 1
    local out = {}
    for _, ch in next, self.tableContents do
        if currentLine == lineNumber then
            if ch.Char == "\n" then break end
            table.insert(out, ch.Char)
        end
        if ch.Char == "\n" then
            currentLine = currentLine + 1
        end
    end
    return table.concat(out)
end

function Highlight:setLine(lineNumber, text)
    if type(lineNumber) ~= "number" then error("line must be a number") end
    text = tostring(text)
    local raw = self:getRaw()
    local parts = {}
    local current = 1
    local lastPos = 1
    for s, e in gfind(raw, "\n")() do
        if current == lineNumber then
            -- replace line contents between lastPos and s-1 with text
            local prefix = raw:sub(1, lastPos - 1)
            local suffix = raw:sub(s, #raw)
            local newRaw = prefix .. text .. suffix
            self:setRaw(newRaw)
            return
        end
        lastPos = e + 1
        current = current + 1
    end
    -- if line beyond existing, append
    if lineNumber >= current then
        local append = ("\n"):rep(lineNumber - current + 1) .. text
        self:setRaw(raw .. append)
    else
        error("Unable to set line")
    end
end

function Highlight:insertLine(lineNumber, text)
    if type(lineNumber) ~= "number" then error("line must be a number") end
    text = tostring(text)
    local raw = self:getRaw()
    local current = 1
    local lastStart = 1
    for s, e in gfind(raw, "\n")() do
        if current == lineNumber then
            local prefix = raw:sub(1, lastStart - 1)
            local suffix = raw:sub(s, #raw)
            local newRaw = prefix .. "\n" .. text .. "\n" .. suffix
            self:setRaw(newRaw)
            return
        end
        lastStart = e + 1
        current = current + 1
    end
    -- fallback: append at end
    if lineNumber >= current then
        self:setRaw(raw .. "\n" .. text .. "\n")
    else
        error("Unable to insert line")
    end
end

local constructor = {}
function constructor.new(...)
    local self = setmetatable({}, Highlight)
    local args = {...}     
    if self.init then
        -- keep compatibility with earlier pattern new:init(...)
    end  
    if select("#", ...) > 0 then
        -- if passed a frame on creation, call init
        local ok, err = pcall(function() 
            self:init(table.unpack(args)) 
        end)
        
        if not ok then error(err) end
    end
    
    return self
end

return constructor