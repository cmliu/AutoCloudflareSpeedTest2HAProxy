#!/bin/bash
# $ bash ACFST2HAProxy.sh 80 6 8 230
export LANG=zh_CN.UTF-8

port=80 #自定义测速端口 不能为空!!!
STcount=6 #测速数量
speedlower=8  #自定义下载速度下限,单位为mb/s
STmax=230 #测速延迟允许的最大上限
###############################################################以下脚本内容，勿动#######################################################################
speedqueue_max=2 #自定义测速IP冗余量
lossmax=0.75  #自定义丢包几率上限；只输出低于/等于指定丢包率的 IP，范围 0.00~1.00，0 过滤掉任何丢包的 IP
speedtestMB=50 #测速文件大小 单位MB，文件过大会拖延测试时长，过小会无法测出准确速度
speedurl="speed.cloudflare.com/__down?bytes=$((speedtestMB * 1000000))" #官方测速链接,开头不要带https:
proxygithub="https://ghproxy.com/" #反代github加速地址，如果不需要可以将引号内容删除，如需修改请确保/结尾 例如"https://ghproxy.com/"
ports=(443 2053 2083 2087 2096 8443) #判断协议使用,勿动

# 读取/etc/os-release文件中的ID字段
os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
Ubuntu=0
# 检查不同的操作系统类型
if [ "$os_id" == "ubuntu" ]; then
    #echo "Ubuntu系统"
	Ubuntu=1
else
    echo "非Ubuntu系统,尝试使用openwrt环境运行"
fi

#带有自定义测速端口参数
if [ -n "$1" ]; then 
    port="$1"
fi

#带有测速数量参数
if [ -n "$2" ]; then 
    STcount="$2"
fi

#带有自定义下载速度下限参数
if [ -n "$3" ]; then 
    speedlower="$3"
fi

#带测速延迟允许的最大上限参数
if [ -n "$4" ]; then 
    STmax="$4"
fi

update_gengxinzhi=0
apt_update() {
    if [ "$update_gengxinzhi" -eq 0 ]; then
		
		if [ "$Ubuntu" -eq 1 ]; then
			sudo apt update
		else
			opkg update
		fi
		
        update_gengxinzhi=$((update_gengxinzhi + 1))
    fi
}

# 检测并安装软件函数
apt_install() {

	if ! command -v "$1" &> /dev/null; then
		echo "$1 未安装，开始安装..."
		apt_update
		
		if [ "$Ubuntu" -eq 1 ]; then
			sudo apt install "$1" -y
		else
			opkg install "$1"
		fi
		
		echo "$1 安装完成！"
	fi

	
}

apt_install curl
apt_install jq
apt_install haproxy

download_CloudflareST() {
    # 发送 API 请求获取仓库信息（替换 <username> 和 <repo>）
    latest_version=$(curl -s https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "最新版本号: $latest_version"
    # 下载文件到当前目录
	if [ -z "$latest_version" ]; then
		latest_version="v2.2.4"
	fi
    curl -L -o CloudflareST_linux_amd64.tar.gz "${proxygithub}https://github.com/XIU2/CloudflareSpeedTest/releases/download/$latest_version/CloudflareST_linux_amd64.tar.gz"
    # 解压CloudflareST文件到当前目录
    tar -xvf CloudflareST_linux_amd64.tar.gz CloudflareST -C /
	rm CloudflareST_linux_amd64.tar.gz

}

# 尝试次数
max_attempts=5
current_attempt=1

while [ $current_attempt -le $max_attempts ]; do
    # 检查是否存在CloudflareST文件
    if [ -f "CloudflareST" ]; then
        echo "CloudflareST 准备就绪。"
        break
    else
        echo "CloudflareST 未准备就绪。"
        echo "第 $current_attempt 次下载 CloudflareST ..."
        download_CloudflareST
    fi

    ((current_attempt++))
done

if [ $current_attempt -gt $max_attempts ]; then
    echo "连续 $max_attempts 次下载失败。请检查网络环境时候可以访问github后重试。"
    exit 1
fi

download_file() {
  local file_name="$1"
  
  if [ -f "$file_name" ]; then
    echo "$file_name 准备就绪。"
  else
    echo "$file_name 未准备就绪，正在下载 ..."
    curl -o "$file_name" "${proxygithub}https://raw.githubusercontent.com/cmliu/AutoCloudflareSpeedTest2HAProxy/main/$file_name"
  fi
}

download_file ip.txt
download_file haproxy.cfg.bk

speedurlhttp="http://"  # 默认为http
for p in "${ports[@]}"; do
  if [ "$port" -eq "$p" ]; then
    speedurlhttp="https://"
    break  # 找到匹配的端口后可以提前结束循环
  fi
done

# 检测log文件夹是否存在
if [ ! -d "log" ]; then
  mkdir -p "log"
fi

local_IP=$(curl -m 10 -s 4.ipw.cn)
#全球IP地理位置API请求和响应示例
local_IP_geo=$(curl -m 10 -s http://ip-api.com/json/${local_IP}?lang=zh-CN)
# 使用jq解析JSON响应并提取所需的信息
status=$(echo "$local_IP_geo" | jq -r '.status')

if [ "$status" = "success" ]; then
    countryCode=$(echo "$local_IP_geo" | jq -r '.countryCode')
    country=$(echo "$local_IP_geo" | jq -r '.country')
    regionName=$(echo "$local_IP_geo" | jq -r '.regionName')
    city=$(echo "$local_IP_geo" | jq -r '.city')
    # 如果status等于success，则显示地址信息
    # echo "您的地址是 ${country}${regionName}${city}"
    # 判断countryCode是否等于CN
    if [ "$countryCode" != "CN" ]; then
        echo "你的IP地址是 $local_IP ${country}${regionName}${city} 经确认本机网络使用了代理，请关闭代理后重试。"
        exit 1  # 在不是中国的情况下强行退出脚本
    else
        echo "你的IP地址是 $local_IP ${country}${regionName}${city} 经确认本机网络未使用代理..."
    fi
else
    echo "你的IP地址是 $local_IP 地址判断请求失败，请自行确认为本机网络未使用代理..."
fi

speedurl=${speedurlhttp}${speedurl}
result_csv="log/${port}.csv"
Require="测速端口${port}, 需求${STcount}个优选IP, 下载速度至少${speedlower}mb/s, 延迟不超过${STmax}ms"
echo $Require
#./CloudflareST -tp 80 -url http://speed.cloudflare.com/__down?bytes=90000000 -dn 10 -tl 280 -p 0 -sl 10
./CloudflareST -tp $port -url $speedurl -dn $((STcount + speedqueue_max)) -tl $STmax -tlr $lossmax -p 0 -sl $speedlower -o $result_csv

if [ -f "haproxy.cfg" ]; then
  echo "haproxy.cfg 文件已存在，删除后重新配置"
  rm "haproxy.cfg"
fi

cp "haproxy.cfg.bk" "haproxy.cfg"
echo -e "listen 9000\n    mode tcp\n    bind 0.0.0.0:9000" >> haproxy.cfg

# 创建临时文件并将要插入的内容写入临时文件
tmpfile=$(mktemp)
listenport=9001
sed -n "2,$((STcount + 1))p" $result_csv | while read line
do
  echo -e "    server ${line%%,*}:${port} ${line%%,*}:${port} weight 5 check inter 1500 rise 1 fall 3 " >> haproxy.cfg
  echo -e "listen ${listenport}\n    mode tcp\n    bind 0.0.0.0:${listenport}\n    server ${line%%,*}:${port} ${line%%,*}:${port} weight 5 check inter 1500 rise 1 fall 3 \n" >> "$tmpfile"
  ((listenport++))
done
# 将临时文件的内容追加到 haproxy.cfg
cat "$tmpfile" >> haproxy.cfg

# 删除临时文件
rm "$tmpfile"

if [ "$Ubuntu" -eq 1 ]; then
	sudo cp haproxy.cfg /etc/haproxy/
else
	cp haproxy.cfg /etc/
fi

# 检查haproxy服务的状态
service haproxy status >/dev/null 2>&1
clear
# 检查服务的返回状态码
if [ $? -eq 0 ]; then
    echo "HAProxy服务正在运行，重启服务"
	service haproxy restart
else
    echo "HAProxy服务没有运行，启动服务"
	service haproxy start
fi

# 检查haproxy服务的状态
service haproxy status >/dev/null 2>&1

LocalIP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | grep -v "inet 172.17." | awk '{print $2}' | cut -d '/' -f 1 | head -n 1)

# 检查服务的返回状态码
if [ $? -eq 0 ]; then
  #clear
  echo "CloudflareSpeedTest 测速任务完成"
  echo $Require
  echo "HAProxy负载均衡 启动成功"
  echo "负载均衡详细信息面板 http://${LocalIP}:8999"
  echo "负载均衡IP端口: ${LocalIP}:9000"
  listenport=9001
  for ((i = 1; i <= STcount; i++)); do
    echo "${i}号优选IP端口: ${LocalIP}:${listenport}"
	((listenport++))
  done
fi
