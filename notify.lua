local function from_base64(data)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i - f%2^(i-1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c = c + (x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local success, encoded = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/BOXLEGENDARY/SimpleSpyZxL/refs/heads/main/SimpleSpyZxL.lua")
end)

if success and encoded and encoded ~= "" and not string.find(encoded, "404: Not Found") then
    local decoded = from_base64(encoded)
    loadstring(decoded)()
else
    local msg = Instance.new("Message", game:GetService("CoreGui"))
    msg.Text = "SCRIPT FIX OR UPDATE"
    wait(5)
    msg:Destroy()
end
