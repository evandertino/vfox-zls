local M = {}

local KB = 1024
local MB = 1024 * KB
local GB = 1024 * MB

--- Formats a byte size as a human-readable string.
--- @param size number|string
--- @return string|nil
function M.bytes(size)
    local bytes = tonumber(size)
    if not bytes then
        return nil
    end
    if bytes < KB then
        return string.format("%d B", bytes)
    elseif bytes < MB then
        return string.format("%.2f KB", bytes / KB)
    elseif bytes < GB then
        return string.format("%.2f MB", bytes / MB)
    else
        return string.format("%.2f GB", bytes / GB)
    end
end

return M
