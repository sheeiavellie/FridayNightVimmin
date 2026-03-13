local utils = require("FridayNightVimmin.utils")

---@class FridayNightVimmingWindow
---@field buf_id number
---@field win_id number
local FridayNightVimmingWindow = {}
FridayNightVimmingWindow.__index = FridayNightVimmingWindow

local function close_window(buf_id, win_id)
    if win_id ~= nil and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
    end

    if buf_id ~= nil and vim.api.nvim_buf_is_valid(buf_id) then
        vim.api.nvim_buf_delete(buf_id, { force = true })
    end
end

local function create_buffer()
    local buf_id = vim.api.nvim_create_buf(false, true)

    vim.bo[buf_id].buftype = 'nofile'
    vim.bo[buf_id].readonly = false
    vim.api.nvim_buf_set_lines(buf_id, 4, 4, false, {
        "Press ENTER to get the answer...",
    })
    vim.bo[buf_id].readonly = true
    vim.bo[buf_id].modifiable = false

    return buf_id
end

local function create_window_config()
    local width = 34
    local height = 5

    return {
        relative = 'editor',
        row = math.floor(((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        border = 'rounded',
        title = 'Magic8Ball🔮',
        title_pos = 'center',
        style = 'minimal',
    }
end

local function create_window()
    local buf_id = create_buffer()
    local config = create_window_config()
    local win_id = vim.api.nvim_open_win(buf_id, true, config)
    return buf_id, win_id
end


function FridayNightVimmingWindow.new()
    local self = setmetatable({
        buf_id = nil,
        win_id = nil,
    }, FridayNightVimmingWindow)
    return self
end

function FridayNightVimmingWindow:open()
    if self.buf_id == nil then
        local buf_id, win_id = create_window()

        self.buf_id = buf_id
        self.win_id = win_id

        utils.on_close(buf_id, function()
            -- This thing desintegrates buffer when :quit
            close_window(self.buf_id, self.win_id)

            self.buf_id = nil
            self.win_id = nil
        end)
    end
end

function FridayNightVimmingWindow:close()
    if self.buf_id ~= nil then
        close_window(self.buf_id, self.win_id)

        self.buf_id = nil
        self.win_id = nil
    end
end

return FridayNightVimmingWindow
