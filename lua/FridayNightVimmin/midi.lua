local bit = require("bit")

local M = {}

local function read_u32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    return bit.bor(bit.lshift(b1, 24), bit.lshift(b2, 16), bit.lshift(b3, 8), b4), pos + 4
end

local function read_u16(data, pos)
    local b1, b2 = data:byte(pos, pos + 1)
    return bit.bor(bit.lshift(b1, 8), b2), pos + 2
end

local function read_varlen(data, pos)
    local value = 0
    while true do
        local b = data:byte(pos)
        pos = pos + 1
        value = bit.bor(bit.lshift(value, 7), bit.band(b, 0x7F))
        if bit.band(b, 0x80) == 0 then break end
    end
    return value, pos
end

local function generate_pattern(raw_notes)
    local notes = {}

    table.sort(raw_notes, function(a, b) return a.time < b.time end)

    local groups = {}
    local current = { raw_notes[1] }

    for i = 2, #raw_notes do
        if math.abs(raw_notes[i].time - current[1].time) < 0.03 then
            table.insert(current, raw_notes[i])
        else
            table.insert(groups, current)
            current = { raw_notes[i] }
        end
    end

    table.insert(groups, current)

    local last_pitch = nil
    local lane = 2

    for _, group in ipairs(groups) do
        table.sort(group, function(a, b) return a.pitch > b.pitch end)
        local melody = group[1]

        if last_pitch then
            if melody.pitch > last_pitch then
                lane = math.min(4, lane + 1)
            elseif melody.pitch < last_pitch then
                lane = math.max(1, lane - 1)
            end
        end

        last_pitch = melody.pitch

        table.insert(notes, {
            lane = lane,
            time = melody.time,
            hit = false
        })

        local beat = melody.time % 0.5

        if beat < 0.03 or beat > 0.47 then
            table.insert(notes, {
                lane = math.min(4, lane + 1),
                time = melody.time,
                hit = false
            })
        end
    end

    return notes
end

M.get_notes = function(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*all")
    f:close()

    local pos = 1
    assert(data:sub(pos, pos + 3) == "MThd")
    pos = pos + 4

    local header_size
    header_size, pos = read_u32(data, pos)

    local format
    format, pos = read_u16(data, pos)

    local tracks
    tracks, pos = read_u16(data, pos)

    local tpq
    tpq, pos = read_u16(data, pos)

    pos = pos + (header_size - 6)

    local tempo = 500000
    local raw_notes = {}

    for _ = 1, tracks do
        assert(data:sub(pos, pos + 3) == "MTrk")
        pos = pos + 4

        local track_size
        track_size, pos = read_u32(data, pos)
        local track_end = pos + track_size

        local ticks = 0
        local running_status = nil

        while pos < track_end do
            local delta
            delta, pos = read_varlen(data, pos)
            ticks = ticks + delta

            local event = data:byte(pos)

            if event >= 0x80 then
                running_status = event
                pos = pos + 1
            else
                event = running_status
            end

            if not event then break end

            if event == 0xFF then
                local meta = data:byte(pos)
                pos = pos + 1
                local len
                len, pos = read_varlen(data, pos)
                if meta == 0x51 and len == 3 then
                    tempo = bit.bor(
                        bit.lshift(data:byte(pos), 16),
                        bit.lshift(data:byte(pos + 1), 8),
                        data:byte(pos + 2)
                    )
                end
                pos = pos + len
            elseif event >= 0x90 and event <= 0x9F then
                local note = data:byte(pos)
                local vel = data:byte(pos + 1)
                pos = pos + 2
                if vel > 0 then
                    local seconds = ticks * tempo / (tpq * 1000000)

                    table.insert(raw_notes, {
                        pitch = note,
                        time = seconds
                    })
                end
            elseif event >= 0x80 and event <= 0x8F then
                pos = pos + 2
            elseif event >= 0xA0 and event <= 0xBF then
                pos = pos + 2
            elseif event >= 0xC0 and event <= 0xCF then
                pos = pos + 1
            elseif event >= 0xD0 and event <= 0xDF then
                pos = pos + 1
            elseif event >= 0xE0 and event <= 0xEF then
                pos = pos + 2
            elseif event == 0xF0 or event == 0xF7 then
                local len
                len, pos = read_varlen(data, pos)
                pos = pos + len
            end
        end
    end

    local notes = generate_pattern(raw_notes, tpq, tempo)

    table.sort(notes, function(a, b) return a.time < b.time end)

    local offset = 2.0

    for _, n in ipairs(notes) do
        n.time = n.time + offset
    end

    return notes
end

return M
