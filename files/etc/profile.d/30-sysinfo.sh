#!/bin/sh
# ImmortalWrt 系统信息展示脚本 | 对齐/温度/版本/运行时长 已全部优化完成

# 定义终端输出颜色
GREEN="\033[32m"   # 绿色（正常状态）
YELLOW="\033[33m"  # 黄色（警告状态）
RED="\033[31m"     # 红色（异常状态）
RESET="\033[0m"    # 重置颜色

# ===================== 系统运行时长解析 =====================
uptime_output=$(uptime | sed -n 's/.*up //p' | sed -n 's/,.*load.*//p')
days=$(echo "$uptime_output" | grep -o '[0-9]* day' | awk '{print $1}')
hours=$(echo "$uptime_output" | grep -o '[0-9]*:[0-9]*' | cut -d: -f1)
mins=$(echo "$uptime_output" | grep -o '[0-9]*:[0-9]*' | cut -d: -f2)
[ -z "$mins" ] && mins=$(echo "$uptime_output" | grep -o '[0-9]* min' | awk '{print $1}')

# 空值默认补0，避免显示异常
days=${days:-0}
hours=${hours:-0}
mins=${mins:-0}
# 拼接运行时长字符串
uptime_str="${days}天 ${hours}小时 ${mins}分钟"

# ===================== 网络IP信息获取 =====================
# 获取局域网IPv4地址
lan_ip4="$(ip -4 addr show br-lan 2>/dev/null | grep 'inet ' | head -n1 | awk '{print $2}' | cut -d/ -f1)"
[ -z "$lan_ip4" ] && lan_ip4="未获取"

# 获取局域网IPv6地址（过滤本地链路地址）
lan_ip6="$(ip -6 addr show br-lan 2>/dev/null | grep 'inet6 ' | grep -v '::1/' | grep -v 'fe80::' | head -n1 | awk '{print $2}' | cut -d/ -f1)"
[ -z "$lan_ip6" ] && lan_ip6="未获取"

# ===================== 系统负载监控 =====================
core=$(grep -c processor /proc/cpuinfo)  # CPU核心数
load=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')  # 1/5/15分钟系统负载
load_val=$(echo "$load" | awk '{print $1}')
# 负载颜色判断：超高=红，偏高=黄，正常=绿
color_load=$GREEN
if echo "$load_val $core" | awk '{exit !($1 > $2)}'; then
    color_load=$RED
elif echo "$load_val $core" | awk '{exit !($1 > $2 * 0.7)}'; then
    color_load=$YELLOW
fi

# ===================== 内存占用监控 =====================
mem_total=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
mem_used=$(grep MemAvailable /proc/meminfo | awk -v total="$mem_total" '{print total - int($2/1024)}')
mem_pct=$(( (mem_used * 100) / (mem_total + 1) ))
mem_str="${mem_pct}% of ${mem_total}MB"
# 内存颜色判断：占用≥85%红，≥70%黄，其余绿
color_mem=$GREEN
if [ $mem_pct -ge 85 ]; then
    color_mem=$RED
elif [ $mem_pct -ge 70 ]; then
    color_mem=$YELLOW
fi

# ===================== 系统存储监控 =====================
storage_pct=$(df -h / | awk 'NR==2{gsub(/%/,""); print $5}')
storage_str="${storage_pct}% of $(df -h / | awk 'NR==2{print $2}')"
# 存储颜色判断：占用≥90%红，≥75%黄，其余绿
color_storage=$GREEN
if [ $storage_pct -ge 90 ]; then
    color_storage=$RED
elif [ $storage_pct -ge 75 ]; then
    color_storage=$YELLOW
fi

# ===================== CPU信息获取 =====================
cpu_model="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
cpu_cores="$(grep -c processor /proc/cpuinfo)"
# 兼容无model name的设备，读取Hardware信息
[ -z "$cpu_model" ] && cpu_model="$(grep -m1 'Hardware' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"

# ===================== CPU温度获取 =====================
temp_val=0
has_temp=0
# 读取设备温度传感器（兼容两种路径）
if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
    raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    temp_val=$((raw / 1000))
    has_temp=1
fi

# ===================== 设备硬件信息 =====================
model="$(cat /tmp/sysinfo/model 2>/dev/null)"
[ -z "$model" ] && model="$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')"
[ -z "$model" ] && model="未知设备"

# 系统架构识别
arch="$(uname -m)"
case "$arch" in
  aarch64) arch_str="aarch64 (ARM64)" ;;
  armv7l) arch_str="armv7 (ARM32)" ;;
  x86_64) arch_str="x86_64 (AMD64)" ;;
  *) arch_str="$arch" ;;
esac

# ===================== 固件/内核版本 =====================
# 读取ImmortalWrt官方版本，屏蔽编译者信息
if [ -f /etc/openwrt_release ]; then
  . /etc/openwrt_release
  dist="${DISTRIB_ID} ${DISTRIB_RELEASE}"
else
  dist="ImmortalWrt 未知版本"
fi
kernel="$(uname -r)"  # 内核版本

# ===================== 信息格式化输出 =====================
echo ""
printf "HeiCatWrt 已经持续稳定运行了:  %s\n" "$uptime_str"
echo ""
printf "IPv4地址:   %-26s    IPv6地址:   %s\n" "$lan_ip4" "$lan_ip6"
printf "系统负载:   ${color_load}%-23s${RESET}    内存占用:   ${color_mem}%s${RESET}\n" "$load" "$mem_str"
printf "系统存储:   ${color_storage}%-23s${RESET}    CPU 信息:   %s × %s" "$storage_str" "$cpu_model" "$cpu_cores"

# 温度颜色输出（无传感器则不显示）
if [ "$has_temp" = 1 ]; then
    if [ "$temp_val" -gt 70 ]; then
        printf " | \033[31m%d°C\033[0m" "$temp_val"
    elif [ "$temp_val" -ge 60 ]; then
        printf " | \033[33m%d°C\033[0m" "$temp_val"
    else
        printf " | \033[32m%d°C\033[0m" "$temp_val"
    fi
fi
printf "\n"

printf "设备型号:   %-23s    系统架构:   %s\n" "$model" "$arch_str"
printf "固件版本:   %-23s    内核版本:   %s\n" "$dist" "$kernel"
echo ""
echo "       -----------------------------------------"
echo ""