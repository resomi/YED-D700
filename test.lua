local is_calling = false  -- 标记当前是否在拨打电话
local is_in_call = false  -- 标记当前是否有电话接通
local call_queue = {}     -- 电话队列，用来排队等待拨打的电话及其 TTS 内容

-- 处理来电事件
sys.on("CALL_INCOMING", function(id)
    if not is_calling and not is_in_call then
        print("来电: " .. id)
        -- 为当前来电设置一个 TTS 内容（例如 "请留言"）
        -- 这里可以直接修改队列中的项，或者在这里加默认的 TTS
        table.insert(call_queue, {phoneNumber = id, ttsContent = "请留言"})
    end
end)

-- 处理电话接通事件
sys.on("CALL_CONNECTED", function(id)
    print("电话接通: " .. id)
    is_in_call = true  -- 标记电话接通
    current_call_id = id

    -- 获取当前电话的 TTS 内容
    local tts_message = nil
    for _, call in ipairs(call_queue) do
        if call.phoneNumber == id then
            tts_message = call.ttsContent
            break
        end
    end

    if tts_message then
        print("播放电话 " .. id .. " 的 TTS: " .. tts_message)
        tts.play(tts_message, function()
            print("TTS 播放完成")
            -- 播放完成后，清除该电话的 TTS 内容
            -- 此处无需清除，因为已从队列中处理
            is_in_call = false  -- 标记通话结束
            -- 通话结束后，系统自动继续拨打队列中的下一个电话
        end)
    end
end)

-- 统一检查和拨打队列中的电话（通过循环或定时器方式）
function tryToMakeNextCall()
    if is_calling or is_in_call then
        -- 如果正在拨打电话或者接听电话，则不进行新的拨打
        return
    end

    -- 如果队列中有电话请求，取出并拨打下一个电话
    if #call_queue > 0 then
        local next_call = table.remove(call_queue, 1)  -- 从队列中取出下一个电话请求
        local phoneNumber = next_call.phoneNumber
        local ttsContent = next_call.ttsContent

        is_calling = true  -- 标记当前正在拨打电话
        current_call_id = phoneNumber
        print("正在拨打电话: " .. phoneNumber)

        -- 发起电话
        sys.call(phoneNumber, "dial")
        print("正在拨打电话，TTS 内容: " .. ttsContent)
    else
        print("没有更多电话待拨打")
    end
end

-- 启动定时任务定期检查并拨打队列中的电话
function startCallQueueListener()
    sys.timerStart(function()
        tryToMakeNextCall()  -- 定期检查队列并尝试拨打下一个电话
    end, 1000)  -- 每秒钟检查一次队列（根据需求调整检查频率）
end

-- 发起电话并指定播放TTS内容
function makeCall(phoneNumber, ttsContent)
    -- 将新的电话请求放入队列
    print("电话 " .. phoneNumber .. " 被加入到队列")
    table.insert(call_queue, {phoneNumber = phoneNumber, ttsContent = ttsContent})  -- 将新的电话请求放入队列
end

-- 启动队列监听器
startCallQueueListener()

-- 示例：发起电话并指定TTS内容
makeCall("111", "请注意，这是一条电话通知")
makeCall("222", "这是一条紧急通知")
makeCall("333", "请在下次联系时留下您的问题")

-- 示例：接到来电时，自动播放默认TTS
-- 此时，来电时的默认TTS会被设置为 "请留言"
