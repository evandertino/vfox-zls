local M = {}

-- Static constants at module level, built once
local PLATFORM_MAP = {
    ["linux"] = {
        ["386"] = "x86-linux",
        ["amd64"] = "x86_64-linux",
        ["arm"] = "arm-linux",
        ["arm64"] = "aarch64-linux",
        ["riscv64"] = "riscv64-linux",
    },
    ["darwin"] = {
        ["amd64"] = "x86_64-macos",
        ["arm64"] = "aarch64-macos",
    },
    ["windows"] = {
        ["386"] = "x86-windows",
        ["amd64"] = "x86_64-windows",
        ["arm64"] = "aarch64-windows",
    },
}

-- Hash-set for O(1) membership checks
local SUPPORTED_PLATFORMS = {}
for _, arch_map in pairs(PLATFORM_MAP) do
    for _, platform in pairs(arch_map) do
        SUPPORTED_PLATFORMS[platform] = true
    end
end

--- Returns the ZLS platform string for the current system.
--- @return string|nil  e.g. "x86_64-linux", or nil if unsupported
function M.get_platform()
    local os_map = PLATFORM_MAP[RUNTIME.osType:lower()]
    if os_map then
        return os_map[RUNTIME.archType]
    end

    return nil
end

--- Returns true if the given platform string is supported.
--- @param platform string
--- @return boolean
function M.is_platform_supported(platform)
    return SUPPORTED_PLATFORMS[platform] == true
end

M.platform = M.get_platform()

return M
