local midi = require("FridayNightVimmin.midi")
local mpv = require("FridayNightVimmin.mpvcontrolller")
local utils = require("FridayNightVimmin.utils")

local FPS = 120
local FRAME_TIME = 1000 / FPS

local LANES = { 'H', 'J', 'K', 'L' }
local LANE_X = { 7, 15, 23, 31 }

local NOTE_TRAVEL_TIME = 2.0
local HIT_LINE_Y = 55

local HIT_WINDOW = 0.15
local VISUAL_OFFSET = 0.89

local Events = {
    listeners = {}
}

function Events.on(event, fn)
    if not Events.listeners[event] then
        Events.listeners[event] = {}
    end

    table.insert(Events.listeners[event], fn)
end

function Events.emit(event, data)
    local list = Events.listeners[event]
    if not list then return end

    for _, fn in ipairs(list) do
        fn(data)
    end
end

local Game = {
    running = false,

    score = 0,

    base_frame = nil,
    notes = {},
    start_time = 0,
    current_time = 0,
    sync_time = 0,
    sync_clock = 0,

    mpv_controller = nil,
    audio_socket = nil,
    audio_job = nil,
}

function Game:start_audio(path)
    local socket = "/tmp/nvim-rhythm-mpv.sock"
    os.remove(socket)

    self.audio_socket = socket

    self.audio_job = vim.fn.jobstart({
        "mpv",
        "--no-video",
        "--quiet",
        "--idle=no",
        "--untimed",
        "--audio-buffer=0.05",
        "--input-ipc-server=" .. socket,
        "--pause=no",
        path
    })
end

local function cleanup(float)
    if Game.running then
        print("Stopping game!")
        Game.running = false
    end

    if Game.audio_job then
        print("Stopping audio!")
        vim.fn.jobstop(Game.audio_job)
    end

    if float.win and vim.api.nvim_win_is_valid(float.win) then
        print("Closing window!")
        vim.api.nvim_win_close(float.win, true)
    end

    if float.buf and vim.api.nvim_buf_is_valid(float.buf) then
        print("Closing buffer!")
        vim.api.nvim_buf_delete(float.buf, { force = true })
    end

    print("Cleaned!")
end

local function try_hit(lane)
    local best_note = nil
    local best_diff = math.huge

    for _, note in ipairs(Game.notes) do
        if note.lane == lane and not note.hit then
            local diff = math.abs(Game.current_time - note.time)

            if diff < HIT_WINDOW and diff < best_diff then
                best_note = note
                best_diff = diff
            end
        end
    end

    if best_note then
        best_note.hit = true
        Game.score = Game.score + 20
    end
end

local handle_keypress = function(key)
    return vim.schedule_wrap(function()
        local lane = utils.get_item(LANES, key)
        if not lane then
            print("We don't handle " .. key .. "!")

            return
        end

        print("Hit " .. key .. "!")

        Events.emit("keypress", {
            key = key,
            lane = lane
        })
    end)
end

local function create_window_config()
    local width = 37
    local height = 59

    return {
        split = "left",
        width = width,
        height = height,
        style = 'minimal',
    }
end

local function create_floating_window(config, enter)
    if enter == nil then
        enter = false
    end

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, enter or false, config)

    vim.keymap.set('n', 'h', handle_keypress("H"),
        { buffer = buf, noremap = true, silent = true })
    vim.keymap.set('n', 'j', handle_keypress("J"),
        { buffer = buf, noremap = true, silent = true })
    vim.keymap.set('n', 'k', handle_keypress("K"),
        { buffer = buf, noremap = true, silent = true })
    vim.keymap.set('n', 'l', handle_keypress("L"),
        { buffer = buf, noremap = true, silent = true })
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        once = true,
        callback = function()
            cleanup({ buf = buf, win = win })
        end
    })

    return { buf = buf, win = win }
end

local function base_ui()
    local lines = {}

    lines[#lines + 1] = string.format(" SCORE: %06d", Game.score)
    lines[#lines + 1] = "  |-│===│─┬─│===│─┬─│===│─┬─│===│-|  "

    for i = 1, 52 do
        if i % 9 == 0 then
            lines[#lines + 1] = "  |=======|=======|=======|=======|  "
        else
            lines[#lines + 1] = "  |       |       |       |       |  "
        end
    end

    lines[#lines + 1] = "  |->   <-|->   <-|->   <-|->   <-|10"
    lines[#lines + 1] = "  |->   <-|->   <-|->   <-|->   <-|20"
    lines[#lines + 1] = "  | ╭───╮ | ╭───╮ | ╭───╮ | ╭───╮ |  "
    lines[#lines + 1] = "  | │ H │-|-│ J │-|-│ K │-|-│ L │ |  "
    lines[#lines + 1] = "  └─╰───╯---╰───╯---╰───╯---╰───╯─┘  "

    return lines
end

local function update_time()
    local now = vim.loop.hrtime()

    Game.current_time =
        Game.sync_time +
        (now - Game.sync_clock) / 1e9 + VISUAL_OFFSET

    --print(Game.current_time .. " " .. Game.sync_time)

    --print(Game.current_time .. " " ..
    --    Game.sync_time .. " " ..
    --    now .. " " ..
    --    Game.sync_clock .. " " ..
    --    (now - Game.sync_clock) / 1e9)
end

local function update()
    update_time()

    for _, note in ipairs(Game.notes) do
        if not note.hit then
            if Game.current_time - note.time > HIT_WINDOW then
                note.hit = true
            end
        end
    end
end

local function render_frame(float)
    local frame = base_ui()
    assert(frame, "Bad base_frame!")

    frame[1] = string.format(" SCORE: %06d", Game.score)

    for _, note in ipairs(Game.notes) do
        if not note.hit then
            local spawn_time = note.time - NOTE_TRAVEL_TIME

            local progress =
                (Game.current_time - spawn_time) /
                NOTE_TRAVEL_TIME

            if progress >= 0 and progress <= 1 then
                local y =
                    math.floor(4 + progress * (HIT_LINE_Y - 3))

                local x = LANE_X[note.lane]

                if frame[y] then
                    local line = frame[y]

                    frame[y] =
                        line:sub(1, x - 1)
                        .. LANES[note.lane]
                        .. line:sub(x + 1)
                end
            end
        end
    end

    vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, frame)
end

local function start_game(float)
    if Game.running then
        return
    end

    Game.running = true

    Game.base_frame = base_ui()
    Game.sync_clock = vim.loop.hrtime()

    Game.notes = midi.get_notes('./korobeiniki.mid')

    Game.mpv_controller = mpv:new(true)

    Game:start_audio("./korobeiniki.wav")

    vim.defer_fn(function()
        Game.mpv_controller:connect(Game.audio_socket)
        Game.mpv_controller:subscribe_to_mpv_time(function(time)
            Game.sync_time = time
            Game.sync_clock = vim.loop.hrtime()
        end)
    end, 200)


    local timer = vim.loop.new_timer()

    timer:start(
        0,
        FRAME_TIME,
        vim.schedule_wrap(function()
            if not Game.running then
                if not timer:is_closing() then
                    timer:stop()
                    timer:close()
                end

                return
            end

            update()
            render_frame(float)
        end)
    )
end

local M = {}

Events.on("keypress", function(data)
    try_hit(data.lane)
end)

M.run = function()
    local window_config = create_window_config()
    local float = create_floating_window(window_config, true)

    start_game(float)
end

M.run()

return M
