---@class FridayNightVimming
---@field number integer
local FridayNightVimming = {}

FridayNightVimming.__index = FridayNightVimming

---@return FridayNightVimming
function FridayNightVimming:new()
    local friday_night_vimmin = setmetatable({
        number = 0
    }, self)

    return friday_night_vimmin
end

function FridayNightVimming:increment()
    self.number = self.number + 1
end

function FridayNightVimming:decrement()
    self.number = self.number - 1
end

---@return integer
function FridayNightVimming:number()
    return self.number
end

local friday_night_vimmin = FridayNightVimming:new()

return friday_night_vimmin
