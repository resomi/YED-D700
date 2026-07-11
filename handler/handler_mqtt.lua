
local ready = false
--数据发送的消息队列
local msgQueue = {}

local waitTime = 0
local maxWaitTime = 300000  -- 最大等待时间5分钟 (300,000 毫秒)
local checkInterval = 1000  -- 每次检查网络状态的时间间隔 (1000 毫秒 = 1 秒)

------------------------------------------------- 初始化MQTT --------------------------------------------------

--- MQTT连接是否处于激活状态
-- @return 激活状态返回true，非激活状态返回false
-- @usage mqttTask.isReady()
function isReady()
    return ready
end

-- 启动MQTT客户端任务
sys.taskInit(function()
    local retryConnectCnt = 0
    while true do
        while not socket.isReady() do
            sys.wait(checkInterval)  -- 每1秒检查一次网络状态
            waitTime = waitTime + checkInterval  -- 累加等待时间

            -- 每1秒输出一次当前等待时间，给用户反馈
            log.info("handler_mqtt.taskInit", string.format("正在等待网络连接，就绪时间：%d 秒", waitTime / 1000))

            -- 如果超过了最大等待时间，打印错误日志
            if waitTime >= maxWaitTime then
                log.error("handler_mqtt.taskInit", "网络连接超过5分钟仍未准备好")
                break  -- 跳出循环，不再继续等待
            end
        end

        if socket.isReady() then
            log.info("handler_mqtt.taskInit", "网络已准备好")
            local imei = misc.getImei()
            -- 创建一个MQTT客户端
            local mqttClient = mqtt.client(imei, config.MQTT_KEEPALIVE, config.MQTT_USER, config.MQTT_PASSWORD)
            ready = false  -- 连接前标记为非激活状态

            -- 尝试连接MQTT服务器
            --如果使用ssl连接，打开mqttClient:connect("lbsmqtt.airm2m.com",1884,"tcp_ssl",{caCert="ca.crt"})，根据自己的需求配置
            --mqttClient:connect("lbsmqtt.airm2m.com",1884,"tcp_ssl",{caCert="ca.crt"})
            if mqttClient:connect(config.MQTT_HOST, config.MQTT_PORT, config.MQTT_TRANSPORT, config.MQTT_CERT) then
                ready = true
                log.info("handler_mqtt.taskInit", "成功连接到 MQTT 代理")

                -- 订阅主题
                if not mqttClient:subscribe(config.MQTT_SUBSCRIBE_TOPICS) then
                    log.error("handler_mqtt.taskInit", "订阅主题失败")
                    break  -- 退出并重试连接
                end

                -- 循环处理接收和发送的数据
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

                ready = false  -- 处理完后标记为非激活状态
            else
                log.error("handler_mqtt.taskInit", "连接到 MQTT 代理失败")
                retryConnectCnt = retryConnectCnt + 1
            end

            -- 断开MQTT连接
            if mqttClient:disconnect() then
                ready = false  -- 在断开后确保状态是非激活
                log.info("handler_mqtt.taskInit", "MQTT 连接已断开")
            end

            if retryConnectCnt >= 5 then
                log.error("handler_mqtt.taskInit", "连接失败次数过多，正在关闭连接")
                link.shut()
                retryConnectCnt = 0
            end
            sys.wait(5000)
        else
            -- 进入飞行模式，20秒之后，退出飞行模式
            log.info("handler_mqtt.taskInit", "网络未准备好，切换到飞行模式")
            net.switchFly(true)
            sys.wait(20000)
            net.switchFly(false)
        end
    end
end)

------------------------------------------------- MQTT客户端数据发送处理 --------------------------------------------------

--- 向 msgQueue 队列中插入新消息
-- 每条消息是一个包含了四个信息的表：
-- t：主题（Topic），该消息的发布主题。
-- p：有效载荷（Payload），即要发送的消息内容。
-- q：消息的 QoS（Quality of Service）等级，表示消息的可靠性。
-- user：包含一个回调函数 cb 和回调参数 para。回调函数在消息发布完成后被触发，通知应用是否成功。
local function insertMsg(topic,payload,qos,user)
    table.insert(msgQueue,{t=topic,p=payload,q=qos,user=user})
    sys.publish("APP_SOCKET_SEND_DATA")
end

--- MQTT客户端数据发送处理
-- @param mqttClient，MQTT客户端对象
-- @return 处理成功返回true，处理出错返回false
-- @usage mqttOutMsg.proc(mqttClient)
function procPublish(mqttClient)
    while #msgQueue>0 do
        local outMsg = table.remove(msgQueue,1)
        local result = mqttClient:publish(outMsg.t,outMsg.p,outMsg.q)
        if outMsg.user and outMsg.user.cb then outMsg.user.cb(result,outMsg.user.para) end
        if not result then return end
    end
    return true
end

------------------------------------------------- MQTT客户端数据接收处理 --------------------------------------------------

--- 判断号码是否符合要求
-- @param number (string) 待判断的号码
-- @return (boolean) 如果号码符合条件则返回 true，否则返回 false
local function checkNumber(number)
    if number == nil or type(number) ~= "string" then
        return false
    end
    -- 号码长度必须大于等于 5 位
    if number:len() < 5 then
        return false
    end

    return true
end

--- MQTT客户端数据接收处理
-- @param mqttClient，MQTT客户端对象
-- @return 处理成功返回true，处理出错返回false
-- @usage mqttInMsg.proc(mqttClient)
function procReceive(mqttClient)
    local result,data
    while true do
        result,data = mqttClient:receive(60000,"APP_SOCKET_SEND_DATA")
        --接收到数据
        if result then
            log.info("handler_mqtt.procReceive",data.topic,string.toHex(data.payload))
            local message = data.payload

            -- 如果消息是 `CALL,{called_number},{tts_content_to_be_sent}`，则拨打电话
            local called_number, tts_content_to_be_sent = message:match("^CALL,(%d+),(.+)$")
            if called_number and tts_content_to_be_sent then
                -- 判断号码是否合法
                if checkNumber(called_number) and type(tts_content_to_be_sent) == "string" and tts_content_to_be_sent:len() > 0 then
                    log.info("mqtt_handler", "匹配成功: <拨打电话>", called_number)

                    -- 拨打电话
                    -- sys.taskInit(cc.dial, called_number)
                    makeCall(called_number, tts_content_to_be_sent)

                    -- 发送通知
                    util_notify.add({
                        "指令触发了 <拨打电话>",
                        "",
                        "被叫人号码: " .. called_number,
                        "#CONTROL"
                    })
                else
                    log.info("mqtt_handler", "匹配失败: <拨打电话> - 无效号码", called_number)
                end
                return  -- 找到匹配项后返回，不再继续处理
            end

            -- 如果消息是 `SMS,{receiver_number},{sms_content_to_be_sent}`，则发送短信
            local receiver_number, sms_content_to_be_sent = message:match("^SMS,(%d+),(.+)$")
            if receiver_number and sms_content_to_be_sent then
                -- 判断号码是否合法，且短信内容不为空
                if checkNumber(receiver_number) and type(sms_content_to_be_sent) == "string" and sms_content_to_be_sent:len() > 0 then
                    -- 防止循环发送短信，检查短信内容是否已经包含 'SMS,' 防止递归调用
                    if string.sub(sms_content_to_be_sent, 1, 4) == "SMS," then
                        return
                    end

                    log.info("mqtt_handler", "匹配成功: <发送短信>", receiver_number, sms_content_to_be_sent)

                    -- 发送短信
                    sys.taskInit(sms.send, receiver_number, sms_content_to_be_sent)

                    -- 发送通知
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
                return  -- 找到匹配项后返回，不再继续处理
            end

            -- 如果没有匹配到任何指令
            log.info("mqtt_handler", "无法匹配任何指令: " .. message)
        else
            break
        end
    end

    return result or data=="timeout" or data=="APP_SOCKET_SEND_DATA"
end
