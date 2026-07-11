module(...,package.seeall)

-- 递归读取目录中的所有文件
local function read_files_in_dir(path)
    -- 读取目录下的所有文件和子目录
    local ret, files = io.lsdir(path)
    if not ret then
        log.info("fs", "无法读取目录", path)
        return
    end

    -- 遍历文件列表
    for _, file in ipairs(files) do
        local file_path = path .. "/" .. file

        -- 如果是文件，则读取内容并打印
        local f = io.open(file_path, "rb")
        if f then
            local data = f:read("*a")
            log.info("fs", "文件内容", file_path, data, data:toHex())
            f:close()
        else
            log.info("fs", "无法打开文件", file_path)
        end
    end
end

local function fs_test()
    log.info("hiCall","剩余空间: "..rtos.get_fs_free_size().." Bytes")
    -- 读取并打印根目录下所有文件
    read_files_in_dir("/")

    -- 读取并打印/luadb/目录下的文件
    read_files_in_dir("/luadb/")

end

print("hiCall","终于执行了")
sys.timerLoopStart(function() print("hiCall","剩余空间: "..rtos.get_fs_free_size().." Bytes") end,5000)

sys.taskInit(function()
    log.info("hiCall","进入fs_test")
    -- 为了显示日志,这里特意延迟一秒
    -- 正常使用不需要delay
    sys.wait(1000)
    fs_test()
end)
