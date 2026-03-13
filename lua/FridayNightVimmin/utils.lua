local M = {}

M.get_item = function(table, value)
    for i, item in ipairs(table) do
        if item == value then
            return i
        end
    end

    return nil
end

return M
