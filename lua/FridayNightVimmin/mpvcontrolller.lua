---@class MPVController
---@field pipe uv_pipe_t
local MPVController = {}

MPVController.__index = MPVController

---@param ipc boolean
---@return MPVController
function MPVController:new(ipc)
    local pipe = vim.loop.new_pipe(ipc)

    local mpv_controller = setmetatable({
        pipe = pipe,
    }, self)

    return mpv_controller
end

---@param socket string
function MPVController:connect(socket)
    self.pipe:connect(socket, function(err)
        if err then
            print("mpv IPC error: " .. err)
            return
        end
    end)
end

---@param on_mpv_time_change function
function MPVController:subscribe_to_mpv_time(on_mpv_time_change)
    local cmd = vim.json.encode({
        command = { "observe_property", 1, "time-pos" }
    }) .. "\n"

    self.pipe:write(cmd)

    self.pipe:read_start(function(err, chunk)
        if err then
            return
        end

        if not chunk then
            return
        end

        for line in chunk:gmatch("[^\n]+") do
            local ok, msg = pcall(vim.json.decode, line)

            if ok and msg.event == "property-change" then
                if msg.name == "time-pos" and msg.data then
                    on_mpv_time_change(msg.data)
                end
            end
        end
    end)
end

return MPVController
