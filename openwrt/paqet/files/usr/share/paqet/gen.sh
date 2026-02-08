#!/bin/sh
set -e

. /lib/functions.sh

CFG_DIR="/etc/paqet"
PAQET_YAML="${CFG_DIR}/paqet.yaml"
SB_JSON="${CFG_DIR}/sing-box.json"

mkdir -p "$CFG_DIR"

config_load paqet

config_get server_addr main server_addr
config_get key main key
config_get block main block "aes"
config_get conn main conn "1"
config_get socks_listen main socks_listen "127.0.0.1:1080"
config_get log_level main log_level "info"
config_get local_port main local_port "9999"

config_get wan_iface main wan_iface ""
config_get local_ip main local_ip ""
config_get gateway_mac main gateway_mac ""

if [ -z "$wan_iface" ]; then
	wan_iface="$(ip route show default 2>/dev/null | awk 'NR==1{print $5; exit}')"
fi

if [ -z "$local_ip" ] && [ -n "$wan_iface" ]; then
	local_ip="$(ip -4 addr show dev "$wan_iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
fi

if [ -z "$gateway_mac" ] && [ -n "$wan_iface" ]; then
	gw_ip="$(ip route show default 2>/dev/null | awk 'NR==1{print $3; exit}')"
	if [ -n "$gw_ip" ]; then
		gateway_mac="$(ip neigh show "$gw_ip" dev "$wan_iface" 2>/dev/null | awk 'NR==1{print $5; exit}')"
	fi
fi

cat > "$PAQET_YAML" <<EOF
role: "client"

log:
  level: "$log_level"

socks5:
  - listen: "$socks_listen"

network:
  interface: "$wan_iface"
  ipv4:
    addr: "$local_ip:$local_port"
  router_mac: "$gateway_mac"

server:
  addr: "$server_addr"

transport:
  protocol: "kcp"
  kcp:
    block: "$block"
    key: "$key"
    conn: $conn
EOF

config_get tun_ifname main tun_ifname "paqet0"
config_get tun_mtu main tun_mtu "1500"
config_get tun_inet4 main tun_inet4 "198.18.0.1/30"
config_get tun_inet6 main tun_inet6 "fd00:198:18::1/126"
config_get singbox_log_level main singbox_log_level "warn"

socks_host="$(echo "$socks_listen" | cut -d: -f1)"
socks_port="$(echo "$socks_listen" | awk -F: '{print $NF}')"

cat > "$SB_JSON" <<EOF
{
  "log": {
    "level": "$singbox_log_level",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "$tun_ifname",
      "inet4_address": "$tun_inet4",
      "inet6_address": "$tun_inet6",
      "mtu": $tun_mtu,
      "auto_route": false,
      "strict_route": false,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "paqet",
      "server": "$socks_host",
      "server_port": $socks_port,
      "version": 5
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "paqet"
  }
}
EOF

exit 0
