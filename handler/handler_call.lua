
------------------------------------------------- 初始化及状态记录 --------------------------------------------------

local record_extentions = { [1] = "pcm", [2] = "wav", [3] = "amr", [4] = "speex" }
local record_mime_types = { [1] = "audio/x-pcm", [2] = "audio/wav", [3] = "audio/amr", [4] = "audio/speex" }
local record_extention = record_extentions[record_format]
local record_mime_type = record_mime_types[record_format]

local record_upload_header = { ["Content-Type"] = record_mime_type, ["Connection"] = "keep-alive" }
local record_upload_body = { [1] = { ["file"] = record.getFilePath() } }

IS_CALLING = false
CALL_IN = false
CALL_NUMBER = ""
local waiting_queue = {}  -- 等待拨打的电话队列，用来排队等待拨打的电话及其 TTS 内容
local in_call_queue = {}  -- 正在通话中的电话队列

local CALL_CONNECTED_TIME = 0
local CALL_DISCONNECTED_TIME = 0
local CALL_RECORD_START_TIME = 0

------------------------------------------------- 消息通知 --------------------------------------------------

local function callOutNotify(num, ttsContent)
    CALL_DISCONNECTED_TIME = CALL_DISCONNECTED_TIME == 0 and rtos.tick() * 5 or CALL_DISCONNECTED_TIME

    local lines = {
        "拨打电话: " .. num,
        "通话时长: " .. (CALL_DISCONNECTED_TIME - CALL_CONNECTED_TIME) / 1000 .. " S",
        "TTS: " .. ttsContent,
        "",
        "#CALL #CALL_OUT",
    }

    util_notify.add(lines)
end

local function callInNotify(num)
    local lines = { "来电号码: " .. num, "来电动作: " .. "无操作", "", "#CALL #CALL_IN" }

    util_notify.add(lines)
end

------------------------------------------------- TTS 相关 --------------------------------------------------

-- 播放 TTS, 播放结束后开始录音
local function tts(num)

    -- 获取当前电话的 TTS 内容
    local tts_message = "没有消息"
    for _, call in ipairs(in_call_queue) do
        if call.phoneNumber == num then
            tts_message = call.ttsContent
            break
        end
    end

    -- 移除
    for _, call in ipairs(in_call_queue) do
        if call.phoneNumber == num then
            table.remove(in_call_queue, _)
            break
        end
    end

    log.info("handler_call.tts", "TTS 播放开始：", num, tts_message)

    -- 播放 TTS
    audio.setTTSSpeed(50)
    audio.play(7, "TTS", tts_message, 7, function (result)
        log.info("handler_call.ttsCallback", "result:", result)

        sys.timerStart(function ()
            cc.hangUp(num)
        end, 1000 * 1)
        log.info("handler_call.ttsCallback", "TTS 播放完毕，挂断电话：", num)

        callOutNotify(num, tts_message)
    end)
end

------------------------------------------------- 电话回调函数 --------------------------------------------------

-- 电话拨入回调
-- 设备主叫时, 不会触发此回调
local function callIncomingCallback(num)
    -- 来电号码
    CALL_NUMBER = num or "unknown"

    -- 发送除了 来电动作为挂断 之外的通知
    callInNotify(num)
end

-- 电话接通回调
local function callConnectedCallback(num)
    -- 标记接听来电中
    CALL_IN = true
    -- 接通时间
    CALL_CONNECTED_TIME = rtos.tick() * 5
    -- 来电号码
    CALL_NUMBER = num or "unknown"

    CALL_DISCONNECTED_TIME = 0
    CALL_RECORD_START_TIME = 0

    log.info("handler_call.callConnectedCallback", num)

    -- 停止之前的播放
    audio.stop()
    -- 向对方播放留言提醒 TTS
    sys.timerStart(function()
        tts(num)
    end, 500 * 1)
end

-- 电话挂断回调
-- 设备主叫时, 被叫方主动挂断电话或者未接, 也会触发此回调
local function callDisconnectedCallback(discReason)
    -- 标记来电结束
    CALL_IN = false
    IS_CALLING = false
    -- 通话结束时间
    CALL_DISCONNECTED_TIME = rtos.tick() * 5

    log.info("handler_call.callDisconnectedCallback", "挂断原因:", discReason)

    -- TTS 结束
    -- tts(util_audio.audioStream 播放的音频文件) 在播放中通话被挂断, 然后在 callDisconnectedCallback 中调用 audio.stop() 有时不会触发 ttsCallback 回调
    -- 调用 audiocore.stop() 可以解决这个问题
    audio.stop(function(result)
        log.info("handler_call.callDisconnectedCallback", "audio.stop() callback result:", result)
    end)
    audiocore.stop()
end

-- 注册电话回调
sys.subscribe("CALL_INCOMING", callIncomingCallback)
sys.subscribe("CALL_CONNECTED", callConnectedCallback)
sys.subscribe("CALL_DISCONNECTED", callDisconnectedCallback)

ril.regUrc("RING", function()
    -- 来电铃声
    local vol = nvm.get("AUDIO_VOLUME") or 0
    if vol == 0 then
        return
    end
    audio.play(4, "FILE", "/lua/audio_ring.mp3", vol)
end)

-- 来电中保持 LTE 灯闪烁
sys.taskInit(function()
    while true do
        if CALL_IN or cc.anyCallExist() then
            sys.publish("LTE_LED_UPDATE", false)
            sys.wait(100)
            sys.publish("LTE_LED_UPDATE", true)
            sys.wait(100)
        else
            sys.waitUntil("RING", 1000 * 5)
        end
    end
end)

------------------------------------------------- 语音通知初始化 --------------------------------------------------

-- 统一检查和拨打队列中的电话（通过循环或定时器方式）
function tryToMakeNextCall()
    if IS_CALLING or CALL_IN then
        -- 如果正在拨打电话或者接听电话，则不进行新的拨打
        return
    end

    -- 如果队列中有电话请求，取出并拨打下一个电话
    if #waiting_queue > 0 then
        local next_call = table.remove(waiting_queue, 1)  -- 从队列中取出下一个电话请求
        table.insert(in_call_queue, next_call)
        local phoneNumber = next_call.phoneNumber
        local ttsContent = next_call.ttsContent

        IS_CALLING = true
        log.info("handler_call.tryToMakeNextCall", "正在拨打电话: " .. phoneNumber, "TTS 内容: " .. ttsContent)

        -- 发起电话
        cc.dial(phoneNumber)
    end
end

-- 启动定时任务定期检查并拨打队列中的电话
function startCallQueueListener()
    sys.timerLoopStart(function()
        tryToMakeNextCall()  -- 定期检查队列并尝试拨打下一个电话
    end, 1000)  -- 每秒钟检查一次队列（根据需求调整检查频率）
end

function isNonEmptyString(str)
    return str and str ~= ""
end

-- 发起电话并指定播放TTS内容
function makeCall(phoneNumber, ttsContent)
    -- 将新的电话请求放入队列
    log.info("handler_call.makeCall", "电话 " .. phoneNumber .. " 被加入到队列")
    if isNonEmptyString(phoneNumber) and isNonEmptyString(ttsContent) then
        table.insert(waiting_queue, {phoneNumber = phoneNumber, ttsContent = ttsContent})  -- 将新的电话请求放入队列
    end
end

-- 启动队列监听器
startCallQueueListener()
