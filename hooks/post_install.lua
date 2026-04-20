--- Performs additional setup after installation
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook
--- @param ctx {rootPath: string, runtimeVersion: string, sdkInfo: table} Context
function PLUGIN:PostInstall(ctx)
    local sdkInfo = ctx.sdkInfo[PLUGIN.name]
    local path = sdkInfo.path

    local srcFile = path .. "/" .. PLUGIN.name
    local destFile = path .. "/bin/" .. PLUGIN.name

    os.execute("mkdir -p " .. path .. "/bin")

    local result = os.execute("mv " .. srcFile .. " " .. destFile .. " && chmod +x " .. destFile)
    if result ~= 0 then
        error("Failed to install " .. PLUGIN.name .. " binary")
    end

    local testResult = os.execute(destFile .. " --version > /dev/null 2>&1")
    if testResult ~= 0 then
        error(PLUGIN.name .. " installation appears to be broken")
    end
end
