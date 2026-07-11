------------------------------------------------- 初始化及状态记录 --------------------------------------------------

local DEFAULT_CALL_TTS = "这是一条电话通知"

IS_CALLING = false
CALL_IN = false
CALL_NUMBER = ""

local waiting_queue = {}
local in_call_queue = {}

local CALL_CONNECTED_TIME = 0
local CALL_DISCONNECTED_TIME = 0

------------------------------------------------- 通用方法 --------------------------------------------------

local function isNonEmptyString(str)
    return type(str) == "string" and str ~= ""
end

local function getCallInAction()
    local action = nvm.get("CALL_IN_ACTION")
    return type(action) == "number" and action or 0
end

local function getQueuedCall(num)
    for index, call in ipairs(in_call_queue) do
        if call.phoneNumber == num then
            table.remove(in_call_queue, index)
            return call
        end
    end
end

local function hangUpLater(num)
    sys.timerStart(function()
        cc.hangUp(num)
    end, 1000)
end

------------------------------------------------- 消息通知 --------------------------------------------------

local function callOutNotify(num, ttsContent)
    CALL_DISCONNECTED_TIME = CALL_DISCONNECTED_TIME == 0 and rtos.tick() * 5 or CALL_DISCONNECTED_TIME

    util_notify.add({
        "拨打电话: " .. num,
        "通话时长: " .. (CALL_DISCONNECTED_TIME - CALL_CONNECTED_TIME) / 1000 .. " S",
        "TTS: " .. ttsContent,
        "",
        "#CALL #CALL_OUT",
    })
end

local function callInNotify(num, action)
    local action_desc = { [0] = "无操作", [1] = "自动接听", [2] = "挂断", [3] = "自动接听后挂断", [4] = "等待30秒后自动接听" }
    util_notify.add({ "来电号码: " .. num, "来电动作: " .. (action_desc[action] or "未知"), "", "#CALL #CALL_IN" })
end

------------------------------------------------- TTS 相关 --------------------------------------------------

local function playTtsAndHangUp(num, ttsContent, notify)
    if not isNonEmptyString(ttsContent) then
        log.info("handler_call.playTtsAndHangUp", "TTS 为空，直接挂断", num)
        hangUpLater(num)
        return
    end

    log.info("handler_call.playTtsAndHangUp", "TTS 播放开始", num, ttsContent)
    audio.setTTSSpeed(50)
    audio.play(7, "TTS", ttsContent, 7, function(result)
        log.info("handler_call.ttsCallback", "result:", result)
        hangUpLater(num)
        if notify then
            callOutNotify(num, ttsContent)
        end
    end)
end

local function handleAutoAnsweredCall(num)
    local tts_text = config.TTS_TEXT
    if isNonEmptyString(tts_text) then
        playTtsAndHangUp(num, tts_text, false)
    else
        log.info("handler_call.handleAutoAnsweredCall", "未配置 TTS_TEXT，直接挂断", num)
        hangUpLater(num)
    end
end

------------------------------------------------- 电话回调函数 --------------------------------------------------

local function callIncomingCallback(num)
    CALL_IN = true
    CALL_NUMBER = num or "unknown"

    local action = getCallInAction()

    if action == 2 then
        log.info("handler_call.callIncomingCallback", "来电动作", "挂断")
        cc.hangUp(num)
        callInNotify(num, action)
        return
    end

    if action == 1 or action == 3 or action == 4 then
        local delay = action == 4 and 1000 * 30 or 1000 * 3
        log.info("handler_call.callIncomingCallback", "来电动作", action, "延迟接听", delay)
        sys.timerStart(cc.accept, delay, num)
    else
        log.info("handler_call.callIncomingCallback", "来电动作", "无操作")
    end

    callInNotify(num, action)
end

local function callConnectedCallback(num)
    CALL_CONNECTED_TIME = rtos.tick() * 5
    CALL_DISCONNECTED_TIME = 0
    CALL_NUMBER = num or "unknown"

    log.info("handler_call.callConnectedCallback", num)
    audio.stop()

    local queued_call = getQueuedCall(num)
    if queued_call then
        playTtsAndHangUp(num, queued_call.ttsContent, true)
        return
    end

    local action = getCallInAction()
    if CALL_IN and (action == 1 or action == 3 or action == 4) then
        handleAutoAnsweredCall(num)
    end
end

local function callDisconnectedCallback(discReason)
    CALL_IN = false
    IS_CALLING = false
    CALL_DISCONNECTED_TIME = rtos.tick() * 5
    in_call_queue = {}

    log.info("handler_call.callDisconnectedCallback", "挂断原因:", discReason)

    audio.stop(function(result)
        log.info("handler_call.callDisconnectedCallback", "audio.stop() callback result:", result)
    end)
    audiocore.stop()
end

sys.subscribe("CALL_INCOMING", callIncomingCallback)
sys.subscribe("CALL_CONNECTED", callConnectedCallback)
sys.subscribe("CALL_DISCONNECTED", callDisconnectedCallback)

ril.regUrc("RING", function()
    local vol = nvm.get("AUDIO_VOLUME") or 0
    if vol == 0 then
        return
    end
    audio.play(4, "FILE", "/lua/audio_ring.mp3", vol)
end)

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

function tryToMakeNextCall()
    if IS_CALLING or CALL_IN then
        return
    end

    if #waiting_queue > 0 then
        local next_call = table.remove(waiting_queue, 1)
        table.insert(in_call_queue, next_call)

        IS_CALLING = true
        log.info("handler_call.tryToMakeNextCall", "正在拨打电话: " .. next_call.phoneNumber, "TTS 内容: " .. next_call.ttsContent)
        cc.dial(next_call.phoneNumber)
    end
end

function startCallQueueListener()
    sys.timerLoopStart(tryToMakeNextCall, 1000)
end

function makeCall(phoneNumber, ttsContent)
    if not isNonEmptyString(phoneNumber) then
        log.info("handler_call.makeCall", "号码为空")
        return false
    end

    ttsContent = isNonEmptyString(ttsContent) and ttsContent or DEFAULT_CALL_TTS
    log.info("handler_call.makeCall", "电话 " .. phoneNumber .. " 被加入到队列")
    table.insert(waiting_queue, { phoneNumber = phoneNumber, ttsContent = ttsContent })
    return true
end

startCallQueueListener()