module(...)

-------------------------------------------------- 功能及使用说明 --------------------------------------------------

-- 本项目支持外接扬声器和麦克风, 可以实现接打电话等功能, 推荐连接后使用

-- 连接扬声器后, 可以通过短按/双击/长按 POWERKEY 来切换选择菜单项
-- 菜单项包含: 扬声器音量/通话音量/麦克音量/回拨电话/测试通知/网卡/短信播报/历史短信/来电动作/开机通知/查询流量/查询温度/查询时间/查询信号/查询内存/查询电压/状态指示灯/切换卡槽/重启/关机
-- 连接扬声器后, 可以播放: 通知发送成功提示音/来电铃声/通话外放声/短信验证码/短信内容
-- 来电动作配置为无操作时, 如果来电话, 可以通过短按/长按 POWERKEY 来手动接听/挂断电话

-- 支持虚拟U盘来存储历史短信, 需要使用 core 目录下的底层固件

-- 下面配置文件编辑时注意删除注释 (两个短横杠--是lua的注释), 推荐使用 VSCode 代码编辑器

-------------------------------------------------- 通知相关配置 --------------------------------------------------

-- 通知类型, 支持配置多个
-- NOTIFY_TYPE = { "custom_post", "telegram", "pushdeer", "bark", "dingtalk", "feishu", "wecom", "pushover", "inotify", "next-smtp-proxy", "gotify", "serverchan" }
NOTIFY_TYPE = { "custom_post" }

-- custom_post 通知配置, 自定义 POST 请求
-- CUSTOM_POST_CONTENT_TYPE 支持 application/x-www-form-urlencoded 和 application/json
-- CUSTOM_POST_BODY_TABLE 中的 {msg} 会被替换为通知内容
CUSTOM_POST_URL = "http://your-server:3000/wecom/send"
CUSTOM_POST_CONTENT_TYPE = "application/json"
CUSTOM_POST_BODY_TABLE = { ["title"] = "Air724UG 的通知", ["content"] = "{msg}" }

-- telegram 通知配置, https://github.com/0wQ/telegram-notify 或者自行反代
-- TELEGRAM_API = "https://api.telegram.org/bot{token}/sendMessage"
-- TELEGRAM_CHAT_ID = ""

-- pushdeer 通知配置, https://www.pushdeer.com/
-- PUSHDEER_API = "https://api2.pushdeer.com/message/push"
-- PUSHDEER_KEY = ""

-- bark 通知配置, https://github.com/Finb/Bark
-- BARK_API = "https://api.day.app"
-- BARK_KEY = ""

-- dingtalk 通知配置, https://open.dingtalk.com/document/robots/custom-robot-access
-- 自定义关键词方式可填写 ":" "#" "号码"
-- 如果是加签方式, 请填写 DINGTALK_SECRET, 否则留空为自定义关键词方式, https://open.dingtalk.com/document/robots/customize-robot-security-settings
-- DINGTALK_WEBHOOK = "https://oapi.dingtalk.com/robot/send?access_token=xxx"
-- DINGTALK_SECRET = ""

-- feishu 通知配置, https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN
-- FEISHU_WEBHOOK = "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"

-- wecom 通知配置, https://developer.work.weixin.qq.com/document/path/91770
-- WECOM_WEBHOOK = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"

-- pushover 通知配置, https://pushover.net/api
-- PUSHOVER_API_TOKEN = ""
-- PUSHOVER_USER_KEY = ""

-- inotify 通知配置, https://github.com/xpnas/Inotify 或者使用合宙提供的 https://push.luatos.org
-- INOTIFY_API = "https://push.luatos.org/xxx.send"

-- next-smtp-proxy 通知配置, https://github.com/0wQ/next-smtp-proxy
-- NEXT_SMTP_PROXY_API = ""
-- NEXT_SMTP_PROXY_USER = ""
-- NEXT_SMTP_PROXY_PASSWORD = ""
-- NEXT_SMTP_PROXY_HOST = "smtp-mail.outlook.com"
-- NEXT_SMTP_PROXY_PORT = 587
-- NEXT_SMTP_PROXY_FORM_NAME = "Air724UG"
-- NEXT_SMTP_PROXY_TO_EMAIL = ""
-- NEXT_SMTP_PROXY_SUBJECT = "来自 Air724UG 的通知"

-- gotify 通知配置, https://gotify.net/
-- GOTIFY_API = ""
-- GOTIFY_TITLE = "Air724UG"
-- GOTIFY_PRIORITY = 8
-- GOTIFY_TOKEN = ""

-- serverchan 通知配置
-- SERVERCHAN_TITLE = "来自 Air724UG 的通知"
-- SERVERCHAN_API = ""

-- 定时查询流量间隔, 单位毫秒, 设置为 0 关闭 (建议检查 util_mobile.lua 文件中运营商号码和查询流量代码是否正确, 以免发错短信导致扣费)
QUERY_TRAFFIC_INTERVAL = 6 * 60 * 60 * 1000

-- 开机通知
BOOT_NOTIFY = true

-- 通知内容追加更多信息
NOTIFY_APPEND_MORE_INFO = true

-- 通知最大重发次数
NOTIFY_RETRY_MAX = 100

-------------------------------------------------- 录音上传配置 --------------------------------------------------

-- 腾讯云 COS / 阿里云 OSS / AWS S3 等对象存储上传地址, 以下为腾讯云 COS 示例, 请自行修改
-- 存储桶需设置为: <私有读写>
-- 存储桶 Policy 权限: <用户类型: 所有用户> <授权资源: xxx-123456/{录音文件目录}/*> <授权操作: PutObject,GetObject>
-- 提示: 本项目未使用签名认证上传, 请勿泄露自己的地址及目录名
-- 当注释掉或者为空则不启用上传, 并且会将来电动作配置项覆盖为: 接听 -> 接听后挂断
-- UPLOAD_URL = "http://xxx-123456.cos.ap-nanjing.myqcloud.com/{录音文件目录}"

-------------------------------------------------- 短信来电配置 --------------------------------------------------

-- 允许发短信控制设备的号码, 如果注释掉或者为空, 则允许所有号码, 短信格式示例:
-- 拨打电话 CALL,10086
-- 发送短信 SMS,10086,查询流量
-- 查询所有呼转状态 CCFC,?
-- 设置无条件呼转 CCFC,18888888888
-- 关闭所有呼转 CCFC,18888888888
-- 切换卡槽优先级 SIMSWITCH
-- SMS_CONTROL_WHITELIST_NUMBERS = { "18xxxxxxx", "18xxxxxxx", "18xxxxxxx" }
SMS_CONTROL_WHITELIST_NUMBERS = {}

-- 扬声器 TTS 播放短信内容, 0:关闭(默认), 1:仅验证码, 2:全部
SMS_TTS = 0

-- 电话接通后 TTS 语音内容, 在播放完后开始录音, 如果注释掉或者为空则播放 audio_pickup_record.amr 或 audio_pickup_hangup.amr 文件
-- TTS_TEXT = "您好，请在语音结束后留言，稍后将发送到机主，结束请挂机。"

-- 来电动作, 0:无操作, 1:自动接听(默认), 2:挂断, 3:自动接听后挂断, 4:等待30秒后自动接听
-- 无操作 / 等待30秒后自动接听, 可以长按 POWERKEY 来手动接听挂断电话
CALL_IN_ACTION = 0

-------------------------------------------------- MQTT配置 --------------------------------------------------

-- 服务器地址
MQTT_HOST = "your-mqtt-server.example.com"
-- string或者number类型，服务器端口
MQTT_PORT = 8883
-- 可选参数，默认为"tcp" "tcp"或者"tcp_ssl"
MQTT_TRANSPORT = "tcp_ssl"
-- 可选参数，默认为nil table或者nil类型，ssl证书，当transport为"tcp_ssl"时，此参数才有意义。
-- cert格式如下：
-- {
--     caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--     clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--     clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式)
--     clientPassword = "123456", --客户端证书文件密码[可选]
-- }
MQTT_CERT = {caCert="emqxsl-ca.crt", hostNameFlag=1}
-- 可选参数，默认为"" 用户名，用户名为空配置为""或者nil
MQTT_USER = "your-username"
-- 可选参数，默认为"" 密码，密码为空配置为""或者nil
MQTT_PASSWORD = "your-password"
-- 可选参数，默认为300 心跳间隔(单位为秒)，默认300秒
MQTT_KEEPALIVE = 120
-- 可选参数，默认为120 可选参数，socket连接超时时间，单位秒
MQTT_CONNECTTIMEOUT = 120

-- 订阅的主题（topics to subscribe to）
MQTT_SUBSCRIBE_TOPICS = {
    -- 订阅的主题和QOS等级
    ["/event0"] = 0,
    ["/event1"] = 1
}

-------------------------------------------------- 其他配置 --------------------------------------------------

-- 扬声器音量, 0-7
AUDIO_VOLUME = 0

-- 通话音量 0-7
CALL_VOLUME = 0

-- 麦克音量 0-7
MIC_VOLUME = 7

-- 开启 RNDIS 网卡
RNDIS_ENABLE = false

-- 状态指示灯开关
LED_ENABLE = true

-- SIM 卡 pin 码
PIN_CODE = ""