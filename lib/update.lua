--- 模块功能：远程升级.
-- @module update
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.29

require "misc"
require "http"
require "log"
require "common"

module(..., package.seeall)

local sUpdating,sCbFnc,sUrl,sPeriod,sRedir,sLocation,fotastart
local sProcessedLen = 0
--local sBraekTest = 0
local httpRspCode
local sGetImeiFnc,sDownloadProcessFnc

local updateMsg

local otaBegin

local function httpDownloadCbFnc(result,statusCode,head)
    log.info("update.httpDownloadCbFnc",result,statusCode,head,sCbFnc,sPeriod)
    sys.publish("UPDATE_DOWNLOAD",result,statusCode,head)
end

local function processOta(stepData,totalLen,statusCode)
   
    if stepData and totalLen then
        if statusCode=="200" or statusCode=="206" then
            if not otaBegin then sys.publish("LIB_UPDATE_OTA_DOWNLOAD_BEGIN") otaBegin=true end
            local fotaProcessStatus=rtos.fota_process((sProcessedLen+stepData:len()>totalLen) and stepData:sub(1,totalLen-sProcessedLen) or stepData,totalLen)
            if fotaProcessStatus~=0 then 
                log.error("update.processOta","fail",fotaProcessStatus,"failFotaProcessStatus")
                log.error("update.processOta","get_fs_free_size: ",rtos.get_fs_free_size()," Bytes")
                sys.publish("LIB_UPDATE_OTA_DOWNLOAD_END",false)
                return false
            else
                sProcessedLen = sProcessedLen + stepData:len()
                if sDownloadProcessFnc then sDownloadProcessFnc(sProcessedLen*100/totalLen) end
                log.info("update.processOta",totalLen,sProcessedLen,(sProcessedLen*100/totalLen).."%")
                --if sProcessedLen*100/totalLen==sBraekTest then return false end
                if sProcessedLen*100/totalLen>=100 then sys.publish("LIB_UPDATE_OTA_DOWNLOAD_END",true) return true end
            end
        elseif statusCode:sub(1,1)~="3" and stepData:len()==totalLen and totalLen>0 then
            if totalLen<=200 then
                local msg = stepData:match("\"msg\":%s*\"(.-)\"")
                if msg and msg:len()<=200 then
                    updateMsg = common.ucs2beToUtf8((msg:gsub("\\u","")):fromHex())
                    log.warn("update.error",updateMsg)
                end
            end
            httpRspCode = stepData:match("\"code\":%s*(%d+)")
        end
    end
end

function clientTask()
    sUpdating = true
    --不要省略此处代码，否则下文中的misc.getImei有可能获取不到
    while not socket.isReady() do sys.waitUntil("IP_READY_IND") end


    
    while true do
        local retryCnt = 0
        sProcessedLen = 0
        otaBegin = false
        updateMsg = nil
        while true do
            --sBraekTest = sBraekTest+30
            log.info("update.http.request",sLocation,sUrl,sProcessedLen,sBraekTest,fotastart)
            if not fotastart then break end
            local coreVer = rtos.get_version()
            local coreName1,coreName2 = coreVer:match("(.-)_V%d+(_.+)")
            local coreVersion = tonumber(coreVer:match(".-_V(%d+)"))
            httpRspCode = nil 
            
            -- 合宙云平台升级地址
            local iotURL="iot.openluat.com/api/site/firmware_upgrade"
            -- 模块信息
            local moduleInfo="?project_key=".._G.PRODUCT_KEY
            .."&imei="..(sGetImeiFnc and sGetImeiFnc() or misc.getImei())
            .."&firmware_name=".._G.PROJECT.."_"..coreName1..coreName2
            .."&core_version="..coreVersion
            .."&dfota=1&version=".._G.VERSION..(sRedir and "&need_oss_url=1" or "")
            
            
            -- 如果自定义升级地址前三位为“###”，则不拼接模块信息
            if sUrl and string.sub(sUrl,1,3)=="###" then
                log.info("1-3",string.sub(sUrl,1,3))
                log.info("3-0",string.sub(sUrl,4))
                customizeUrl=string.sub(sUrl,4)
            elseif sUrl  then
                customizeUrl=sUrl..moduleInfo
            else 
                -- 默认向合宙云平台地址拼接模块信息
                iotURL=iotURL..moduleInfo
            end
            
            http.request("GET",
                     sLocation or (customizeUrl or iotURL),
                     nil,{["Range"]="bytes="..sProcessedLen.."-"},nil,60000,httpDownloadCbFnc,processOta)

                     
            local _,result,statusCode,head = sys.waitUntil("UPDATE_DOWNLOAD")
            log.info("update.waitUntil UPDATE_DOWNLOAD",result,statusCode,httpRspCode)
            if result then
                local needBreak                
                if statusCode=="200" or statusCode=="206" then
                    needBreak = true
                    local check = rtos.fota_end()
                    log.info("update.rtos.fota_end", check)
                    if sCbFnc then
                        if check == 0 then
                            sCbFnc(true)
                        else
                            sCbFnc(false)
                        end
                    else
                        if check == 0 then
                            sys.restart("UPDATE_DOWNLOAD_SUCCESS")
                        end
                    end
                elseif statusCode:sub(1,1)=="3" and head and head["Location"] then
                    sLocation = head["Location"]
                    sys.wait(2000)
                elseif httpRspCode=="43" then
                    log.info("update.clientTask","wait server create fota")
                    sys.wait(30000)
                else
                    log.info("update.rtos.fota_end",rtos.fota_end())
                    if sCbFnc then sCbFnc(false) end
                    needBreak = true
                end
                
                if needBreak then                    
                    break
                end
            else
                retryCnt = retryCnt+1
                if retryCnt==30 then
                    rtos.fota_end()
                    if sCbFnc then sCbFnc(false) end
                    break
                end
            end
        end
        
        sProcessedLen = 0
        
        if sPeriod then
            sys.wait(sPeriod)
            if rtos.fota_start()~=0 then 
                log.error("update.request","fota_start fail")
                fotastart = false
            else
                fotastart = true
            end
        else
            break
        end
    end
    sUpdating = false
end

--- 启动远程升级功能
-- @function[opt=nil] cbFnc 每次执行远程升级功能后的回调函数，回调函数的调用形式为：
-- cbFnc(result)，result为true表示升级包下载成功，其余表示下载失败
--如果没有设置此参数，则升级包下载成功后，会自动重启
-- @string[opt=nil] url 使用http的get命令下载升级包的url，如果没有设置此参数，默认使用Luatiot平台的url
-- 如果用户设置了url，注意：仅传入完整url的前半部分(如果有参数，即传入?前一部分)，http.lua会自动添加?以及后面的参数，例如：
-- 设置的url="www.userserver.com/api/site/firmware_upgrade"，则http.lua会在此url后面补充下面的参数
-- "?project_key=".._G.PRODUCT_KEY
-- .."&imei="..misc.getimei()
-- .."&device_key="..misc.getsn()
-- .."&firmware_name=".._G.PROJECT.."_"..rtos.get_version().."&version=".._G.VERSION
-- 如果用户设置了url，且url前面增加三个井号"###",http.lua会自动忽略"###"并以用户填入的url作为请求地址，不会自动添加模块信息，例如：
-- 设置的url="###www.userserver.com"/api/site/firmware_upgrade?customparam=test",则http.lua会将此url开头的"###"忽略,并以此url为地址进行请求
-- "www.userserver.com"/api/site/firmware_upgrade?customparam=test"
-- 如果redir设置为true，还会补充.."&need_oss_url=1"
-- @number[opt=nil] period 单位毫秒，定时启动远程升级功能的间隔，如果没有设置此参数，仅执行一次远程升级功能
-- @bool[opt=nil] redir 是否访问重定向到阿里云的升级包，使用Luat提供的升级服务器时，此参数才有意义
-- 为了缓解Luat的升级服务器压力，从2018年7月11日起，在iot.openluat.com新增或者修改升级包的升级配置时，升级文件会备份一份到阿里云服务器
-- 如果此参数设置为true，会从阿里云服务器下载升级包；如果此参数设置为false或者nil，仍然从Luat的升级服务器下载升级包
-- @return nil
-- @usage
-- update.request()
-- update.request(cbFnc)
-- update.request(cbFnc,"www.userserver.com/update")
-- update.request(cbFnc,nil,4*3600*1000)
-- update.request(cbFnc,nil,4*3600*1000,true)
function request(cbFnc,url,period,redir)
    if rtos.fota_start()~=0 then 
        log.error("update.request","fota_start fail")
        fotastart = false
        return
    else
        fotastart = true
    end
    sCbFnc,sUrl,sPeriod,sRedir = cbFnc or sCbFnc,url or sUrl,period or sPeriod,sRedir or redir
    log.info("update.request",sCbFnc,sUrl,sPeriod,sRedir)
    if not sUpdating then        
        sys.taskInit(clientTask)
    end
end

function setGetImeiCbFnc(cbFnc)
    sGetImeiFnc = cbFnc
end

--- 设置升级包下载过程中的下载进度通知回调函数
-- @function cbFnc 下载进度通知回调函数，回调函数的调用形式如下：
-- cbFnc(step)
-- step表示下载进度：取值范围是0到100，下载进度更新很快，建议在回调函数中，每隔5或者10执行一次实际动作
-- @return nil
-- @usage update.setDownloadProcessCbFnc(function(step) end)
function setDownloadProcessCbFnc(cbFnc)
    sDownloadProcessFnc = cbFnc
end

--- 获取请求升级包时服务器返回的信息
-- @return updateMsg, 若没有请求升级或服务器未返回相关信息，则返回值为nil，否则返回服务器返回的相关信息
-- @usage local msg = getUpdateMsg()
function getUpdateMsg()
    return updateMsg
end