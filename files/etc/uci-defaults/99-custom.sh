#!/bin/sh
# 旁路由专属 99-custom.sh 无WAN、纯LAN桥接
LOGFILE="/var/log/uci-defaults-log.txt"
echo "Starting 99-custom.sh Passive Router at $(date)" >>$LOGFILE

# 放行防火墙，方便首次访问
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名
hostname="HeiCatWrt"
if [ -n "$hostname" ]; then
  uci set system.@system[0].hostname="$hostname"
  uci commit system
fi

# 修复安卓原生TV time.android.com解析
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 1. 获取所有物理eth/en网口
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')
echo "Detected all LAN physical ifaces: $ifnames" >>$LOGFILE

# 2. 所有网口全部加入br-lan（旁路由无WAN）
br_section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\].name=.br-lan.$/ {print $2; exit}')
if [ -z "$br_section" ]; then
    echo "error：cannot find device 'br-lan'." >>$LOGFILE
else
    uci -q delete "network.$br_section.ports"
    for port in $ifnames; do
        uci add_list "network.$br_section.ports"="$port"
    done
    echo "All ifaces added to br-lan: $ifnames" >>$LOGFILE
fi

# 3. 旁路由LAN静态IP：192.168.101.66
uci set network.lan.proto='static'
uci set network.lan.netmask='255.255.255.0'

IP_VALUE_FILE="/var/run/custom_router_ip.txt"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    uci set network.lan.ipaddr="$CUSTOM_IP"
    echo "custom passive router ip: $CUSTOM_IP" >> $LOGFILE
else
    # 固定旁路由IP 192.168.101.66
    uci set network.lan.ipaddr='192.168.101.66'
    echo "default passive router ip: 192.168.101.66" >> $LOGFILE
fi

# 旁路由关键：设置网关+DNS指向主路由 192.168.101.1
uci set network.lan.gateway='192.168.101.1'
uci set network.lan.dns='192.168.101.1'

# 禁用WAN/WAN6
uci set network.wan.proto='none'
uci set network.wan6.proto='none'
uci commit network

# Docker防火墙优化
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到Docker，配置旁路由Docker防火墙..." >>$LOGFILE
    FW_FILE="/etc/config/firewall"
    uci delete firewall.docker
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done
    uci commit firewall
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF
fi

# 所有网口允许 ttyd / SSH
uci delete ttyd.@ttyd[0].interface 2>/dev/null
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 编译标识
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='Packaged by limitlesstao 旁路由192.168.101.66'/" /etc/openwrt

# 移除zsh报错
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
fi

echo "99-custom.sh 旁路由配置完成 $(date)" >>$LOGFILE
exit 0