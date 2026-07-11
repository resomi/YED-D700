# CyanBird

CyanBird 是基于 LuatOS-Air 二次开发的蜂窝通信设备脚本项目，面向 Air724UG / Air720U 等合宙 4G 模块场景。项目重点是在固件基础能力之上实现短信/电话通知、MQTT 远程控制、多渠道消息推送、POWERKEY 菜单和设备状态上报等业务功能。

## 二次实现功能

### 短信通知与短信控制

接收到新短信后，项目会将短信内容、发件号码和接收时间整理成通知消息，通过配置的通知渠道转发。短信内容也会进入本地状态，用于 POWERKEY 菜单中的“历史短信”播报。

短信控制由 `handler/handler_sms.lua` 实现，支持白名单限制：

- `SMS_CONTROL_WHITELIST_NUMBERS` 为空时允许任意号码触发控制指令。
- 配置白名单后，仅白名单号码发送的短信可以触发控制逻辑。

支持的短信指令：

| 指令 | 说明 |
| --- | --- |
| `CALL,10086` | 拨打指定号码，接通后播放默认 TTS 并挂断 |
| `SMS,10086,查询流量` | 向指定号码发送短信 |
| `CCFC,?` | 查询所有呼叫转移状态 |
| `CCFC,18888888888` | 设置无条件呼叫转移 |
| `CCFC,0` | 关闭所有呼叫转移 |
| `SIMSWITCH` | 切换 SIM 卡槽优先级并重启 |

### 电话通知与 TTS 外呼队列

电话处理由 `handler/handler_call.lua` 实现，围绕来电、接通、挂断事件做二次业务封装：

- 来电时记录号码并发送来电通知，按 `CALL_IN_ACTION` 决定无操作、自动接听、挂断或延迟接听。
- 来电自动接听后如果配置了 `TTS_TEXT` 则播报后挂断；未配置时直接挂断，不依赖录音或外置存储。
- 来电过程中保持 LTE 指示灯快速闪烁。
- 外呼请求进入等待队列，避免多个电话同时拨打。
- MQTT、短信 `CALL` 和 POWERKEY 回拨都会进入外呼队列。
- 电话接通后播放与该号码绑定的 TTS 内容。
- TTS 播放完成后自动挂断，并发送外呼结果通知。

MQTT 下发的 `CALL` 指令会复用这套外呼队列，实现“远程触发拨号 + 接通后播报文字”。

### MQTT 远程控制

MQTT 逻辑由 `handler/handler_mqtt.lua` 实现。设备等待蜂窝网络就绪后，使用 IMEI 作为 client id 连接 Broker，并订阅 `config.lua` 中配置的主题。

支持的 MQTT Payload：

| Payload | 说明 |
| --- | --- |
| `CALL,13800138000,这是一条电话通知` | 拨打电话，接通后播放指定 TTS 内容 |
| `SMS,13800138000,短信内容` | 向指定号码发送短信 |

MQTT 连接失败时会重试；连续失败次数过多时会关闭链路并重新等待网络状态。

### 多渠道通知队列

通知逻辑由 `utils/util_notify.lua` 实现。业务模块只需要调用 `util_notify.add()` 添加消息，通知模块负责排队、发送、失败重试和成功提示音。

支持的通知渠道：

- `custom_post`
- `telegram`
- `pushdeer`
- `bark`
- `dingtalk`
- `feishu`
- `wecom`
- `pushover`
- `inotify`
- `next-smtp-proxy`
- `gotify`
- `serverchan`

通知消息可以自动追加设备信息，包括本机号码/ICCID、开机时长、运营商、信号、频段、温度和电压。

### POWERKEY 本地菜单

按键菜单由 `handler/handler_powerkey.lua` 实现，用于在无屏幕场景下通过扬声器和 POWERKEY 操作设备。

当前菜单包含：

- 扬声器音量、通话音量、麦克音量、全部静音
- 来电动作、回拨电话、短信播报、历史短信
- 测试通知、开机通知、查询流量、查询卡号、查询信号、查询电压
- RNDIS 网卡、状态指示灯、飞行模式、切换卡槽、重启、关机

菜单项会读写 NVM 配置，使音量、短信播报、开机通知、RNDIS、状态指示灯等状态在重启后保持。

### 设备状态与工具封装

`utils/` 目录包含项目二次封装的工具模块：

- `util_http.lua`：对 LuatOS-Air `http.request` 做同步式等待封装。
- `util_notify.lua`：通知渠道、消息队列、重试和设备信息追加。
- `util_audio.lua`：避免通话中误播放提示音，并封装 AMR 音频流播放。
- `util_mobile.lua`：运营商识别、流量查询短信、本机号码/ICCID 获取、PIN 验证。
- `util_ntp.lua`：开机后同步时间，时间正常后停止重复同步。
- `util_temperature.lua`：读取并缓存模块温度。

## 固件/库基础能力

以下能力主要由 LuatOS-Air 固件和 `lib/` 目录中的基础库提供，本项目只做调用或简单编排：

- 蜂窝网络注册、信号/基站查询、飞行模式、SIM 卡槽控制。
- 短信收发、电话拨打/接听/挂断、呼叫转移 AT 指令。
- MQTT、HTTP、Socket、TLS 证书、NTP、NVM、日志、错误上报。
- 音频播放、TTS、GPIO/电源键、指示灯、RNDIS 网卡。
- 系统任务调度、定时器、事件订阅发布和硬件看门狗。

## 项目结构

```text
.
├── main.lua                 # 项目入口，加载配置、库、工具和业务处理模块
├── config.lua               # 二次业务配置：通知、短信/电话、MQTT、音量、SIM、RNDIS 等
├── test.lua                 # 示例/测试脚本
├── hiCall.lua               # 文件系统测试示例脚本
├── emqxsl-ca.crt            # MQTT TLS CA 证书
├── audio/                   # 提示音、铃声、通话音频资源
├── handler/                 # 二次业务事件处理：电话、短信、MQTT、按键
├── utils/                   # 二次封装工具模块：通知、HTTP、音频、流量、时间、温度
└── lib/                     # LuatOS-Air 基础库与固件能力封装
```

## 启动流程

入口文件是 `main.lua`：

1. 定义 `PROJECT = "CyanBird"` 和 `VERSION = "1.0.0"`。
2. 加载 `config.lua`，并用 `nvm.init("config.lua")` 初始化可持久化配置。
3. 加载 LuatOS-Air 基础库、项目工具模块和业务 handler。
4. 启动温度、信号、基站、流量、NTP 同步等定时任务。
5. 关闭 RNDIS 默认网卡，配置网络指示灯。
6. 注册开机通知、错误日志上报和系统事件处理。
7. 调用 `sys.init()` 与 `sys.run()` 启动系统调度。

## 配置入口

主要配置集中在 `config.lua`。

### 通知配置

```lua
NOTIFY_TYPE = { "custom_post" }
CUSTOM_POST_URL = "http://example.com/notify"
CUSTOM_POST_CONTENT_TYPE = "application/json"
CUSTOM_POST_BODY_TABLE = { ["title"] = "Air724UG 的通知", ["content"] = "{msg}" }
NOTIFY_APPEND_MORE_INFO = true
NOTIFY_RETRY_MAX = 100
```

### MQTT 配置

```lua
MQTT_HOST = "your-broker.example.com"
MQTT_PORT = 8883
MQTT_TRANSPORT = "tcp_ssl"
MQTT_CERT = { caCert = "emqxsl-ca.crt", hostNameFlag = 1 }
MQTT_USER = "your-user"
MQTT_PASSWORD = "your-password"
MQTT_KEEPALIVE = 120
MQTT_SUBSCRIBE_TOPICS = {
    ["/event0"] = 0,
    ["/event1"] = 1,
}
```

### 短信、电话与设备配置

```lua
SMS_CONTROL_WHITELIST_NUMBERS = {}
SMS_TTS = 0
TTS_TEXT = "您好，这是一条电话通知。"
CALL_IN_ACTION = 0
AUDIO_VOLUME = 0
CALL_VOLUME = 0
MIC_VOLUME = 7
RNDIS_ENABLE = false
LED_ENABLE = true
PIN_CODE = ""
```

## 音频资源

`audio/` 目录包含二次业务使用的提示音资源：

- `audio_http_success.mp3`：通知发送成功提示音
- `audio_new_sms.mp3`：新短信提示音
- `audio_ring.mp3`：来电铃声

## 部署与运行

本项目不是普通桌面 Lua 项目，需要运行在 LuatOS-Air 支持的 4G 模块固件环境中。

一般部署步骤：

1. 根据硬件和服务端信息修改 `config.lua`。
2. 如使用 MQTT TLS，确认 `emqxsl-ca.crt` 与 `MQTT_CERT` 配置一致。
3. 将 `main.lua`、`config.lua`、`handler/`、`utils/`、`lib/`、`audio/` 和证书文件一起打包/下载到模块。
4. 通过 Luatools 或对应烧录工具下载脚本到设备。
5. 插入 SIM 卡，等待网络注册和 MQTT/通知通道就绪。
6. 通过短信、MQTT 或 POWERKEY 验证二次业务功能。

## 注意事项

- `config.lua` 中可能包含通知地址、MQTT 用户名/密码等敏感配置，提交或分享前请先脱敏。
- `SMS_CONTROL_WHITELIST_NUMBERS` 为空会允许任意号码触发短信控制，正式使用建议配置白名单。
- `QUERY_TRAFFIC_INTERVAL` 会定时向运营商发送查询短信，使用前请确认运营商号码和指令正确，避免产生费用。
- 当前电话流程不使用录音上传和外置存储；来电自动接听未配置 `TTS_TEXT` 时会直接挂断。
- 默认关闭 RNDIS，避免模块通过 USB 连接电脑后被系统误用为上网网卡导致 SIM 流量消耗。
