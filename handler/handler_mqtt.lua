local ready = false
local msgQueue = {}

local waitTime = 0
local maxWaitTime = 300000
local checkInterval = 1000

------------------------------------------------- 初始化MQTT --------------------------------------------------

function isReady()
    return ready
end

sys.taskInit(function()
    local retryConnectCnt = 0
    while true do
        while not socket.isReady() do
            sys.wait(checkInterval)
            waitTime = waitTime + checkInterval
            log.info("handler_mqtt.taskInit", string.format("正在等待网络连接，就绪时间：%d 秒", waitTime / 1000))

            if waitTime >= maxWaitTime then
                log.error("handler_mqtt.taskInit", "网络连接超过5分钟仍未准备好")
                break
            end
        end

        if socket.isReady() then
            waitTime = 0
            log.info("handler_mqtt.taskInit", "网络已准备好")
            local imei = misc.getImei()
            local mqttClient = mqtt.client(imei, config.MQTT_KEEPALIVE, config.MQTT_USER, config.MQTT_PASSWORD)
            ready = false

            if mqttClient:connect(config.MQTT_HOST, config.MQTT_PORT, config.MQTT_TRANSPORT, config.MQTT_CERT, config.MQTT_CONNECTTIMEOUT) then
                ready = true
                log.info("handler_mqtt.taskInit", "成功连接到 MQTT 代理")

                if mqttClient:subscribe(config.MQTT_SUBSCRIBE_TOPICS) then
                    while true do
                        if not procReceive(mqttClient) then
                            log.error("handler_mqtt.procReceive error")
                            break
                        end
                        if not procPublish(mqttClient) then
                            log.error("handler_mqtt.procPublish error")
                            break
                        end
                    end
                else
                    log.error("handler_mqtt.taskInit", "订阅主题失败")
                    retryConnectCnt = retryConnectCnt + 1
                end

                ready = false
            else
                log.error("handler_mqtt.taskInit", "连接到 MQTT 代理失败")
                retryConnectCnt = retryConnectCnt + 1
            end

            mqttClient:disconnect()
            ready = false
            log.info("handler_mqtt.taskInit", "MQTT 连接已断开")

            if retryConnectCnt >= 5 then
                log.error("handler_mqtt.taskInit", "连接失败次数过多，正在关闭连接")
                link.shut()
                retryConnectCnt = 0
            end
            sys.wait(5000)
        else
            log.info("handler_mqtt.taskInit", "网络未准备好，切换到飞行模式")
            net.switchFly(true)
            sys.wait(20000)
            net.switchFly(false)
        end
    end
end)

------------------------------------------------- MQTT客户端数据发送处理 --------------------------------------------------

local function insertMsg(topic,payload,qos,user)
    table.insert(msgQueue,{t=topic,p=payload,q=qos,user=user})
    sys.publish("APP_SOCKET_SEND_DATA")
end

function procPublish(mqttClient)
    while #msgQueue>0 do
        local outMsg = table.remove(msgQueue,1)
        local result = mqttClient:publish(outMsg.t,outMsg.p,outMsg.q)
        if outMsg.user and outMsg.user.cb then outMsg.user.cb(result,outMsg.user.para) end
        if not result then return false end
    end
    return true
end

------------------------------------------------- MQTT客户端数据接收处理 --------------------------------------------------

local function trim(str)
    str = type(str) == "string" and str or ""
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function checkNumber(number)
    if type(number) ~= "string" then
        return false
    end
    number = trim(number)
    return number:match("^%+?%d%d%d%d%d+%d*$") ~= nil
end

local function isNonEmptyString(str)
    return type(str) == "string" and trim(str) ~= ""
end

function procReceive(mqttClient)
    local result,data
    while true do
        result,data = mqttClient:receive(60000,"APP_SOCKET_SEND_DATA")
        if result then
            log.info("handler_mqtt.procReceive",data.topic,string.toHex(data.payload))
            local message = trim(data.payload)

            local called_number, tts_content_to_be_sent = message:match("^CALL%s*,%s*([^,]+)%s*,%s*(.+)$")
            if called_number and tts_content_to_be_sent then
                called_number = trim(called_number)
                tts_content_to_be_sent = trim(tts_content_to_be_sent)
                if checkNumber(called_number) and isNonEmptyString(tts_content_to_be_sent) then
                    log.info("mqtt_handler", "匹配成功: <拨打电话>", called_number)
                    makeCall(called_number, tts_content_to_be_sent)
                    util_notify.add({
                        "指令触发了 <拨打电话>",
                        "",
                        "被叫人号码: " .. called_number,
                        "#CONTROL"
                    })
                else
                    log.info("mqtt_handler", "匹配失败: <拨打电话> - 无效号码或空TTS", called_number)
                end
                return true
            end

            local receiver_number, sms_content_to_be_sent = message:match("^SMS%s*,%s*([^,]+)%s*,%s*(.+)$")
            if receiver_number and sms_content_to_be_sent then
                receiver_number = trim(receiver_number)
                sms_content_to_be_sent = trim(sms_content_to_be_sent)
                if checkNumber(receiver_number) and isNonEmptyString(sms_content_to_be_sent) then
                    if string.sub(sms_content_to_be_sent, 1, 4) == "SMS," then
                        return true
                    end

                    log.info("mqtt_handler", "匹配成功: <发送短信>", receiver_number, sms_content_to_be_sent)
                    sys.taskInit(sms.send, receiver_number, sms_content_to_be_sent)
                    util_notify.add({
                        "指令触发了 <发送短信>",
                        "",
                        "收件人号码: " .. receiver_number,
                        "短信内容: " .. sms_content_to_be_sent,
                        "#CONTROL"
                    })
                else
                    log.info("mqtt_handler", "匹配失败: <发送短信> - 无效号码或空短信内容")
                end
                return true
            end

            log.info("mqtt_handler", "无法匹配任何指令: " .. message)
        else
            break
        end
    end

    return result or data=="timeout" or data=="APP_SOCKET_SEND_DATA"
end