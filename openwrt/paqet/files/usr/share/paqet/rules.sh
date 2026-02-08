#!/bin/sh
set -e

. /lib/functions.sh

NFT_TABLE="paqet"

cfg_load() {
	config_load paqet

	config_get_bool enabled main enabled 0
	config_get mode main mode "devices"
	config_get tun_ifname main tun_ifname "paqet0"
	config_get fwmark main fwmark "0x1"
	config_get routing_table main routing_table "100"
	config_get server_addr main server_addr ""

	# LAN ingress interfaces for mode=all
	LAN_IIF=""
	add_iif() { LAN_IIF="$LAN_IIF $1"; }
	config_list_foreach main lan_iif add_iif
	[ -n "$LAN_IIF" ] || LAN_IIF="br-lan"
}

wait_for_tun() {
	local ifname="$1"
	local i=0
	while [ $i -lt 20 ]; do
		ip link show "$ifname" >/dev/null 2>&1 && return 0
		i=$((i+1))
		sleep 0.2
	done
	return 1
}

nft_clear() {
	nft delete table inet "$NFT_TABLE" 2>/dev/null || true
}

resolve_server_ip4() {
	local host="${server_addr%:*}"
	# crude: if looks like ipv4, use directly; else resolve
	echo "$host" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' && { echo "$host"; return 0; }
	nslookup "$host" 2>/dev/null | awk '/^Address [0-9]*: /{print $3; exit}' | head -n1
}

# Collect enabled device IPs into DEV4/DEV6
DEV4=""
DEV6=""
add_device() {
	local s="$1" enabled ip
	config_get_bool enabled "$s" enabled 1
	[ "$enabled" -eq 1 ] || return 0
	config_get ip "$s" ip ""
	[ -n "$ip" ] || return 0
	case "$ip" in
		*:* ) DEV6="$DEV6 $ip" ;;
		* )   DEV4="$DEV4 $ip" ;;
	esac
}

join_nft_elems() {
	# turns " a b c " into "a, b, c"
	local out="" x
	for x in $1; do
		if [ -z "$out" ]; then out="$x"; else out="$out, $x"; fi
	done
	echo "$out"
}

nft_apply() {
	# Always reset our table first
	nft_clear

	[ "$enabled" -eq 1 ] || return 0

	# Only mark if TUN exists (prevents blackholing on firewall reload)
	ip link show "$tun_ifname" >/dev/null 2>&1 || return 0

	local wan4 wan6
	wan4="$(ip route show default 2>/dev/null | awk 'NR==1{print $5; exit}')"
	wan6="$(ip -6 route show default 2>/dev/null | awk 'NR==1{print $5; exit}')"
	[ -n "$wan4" ] || wan4="$wan6"

	local srv4
	srv4="$(resolve_server_ip4 || true)"

	# Build device sets
	DEV4=""; DEV6=""
	config_foreach add_device device

	local dev4_elems dev6_elems
	dev4_elems="$(join_nft_elems "$DEV4")"
	dev6_elems="$(join_nft_elems "$DEV6")"

	# LAN ingress set for mode=all
	local lan_iif_elems
	lan_iif_elems="$(join_nft_elems "$LAN_IIF")"

	# If per-device mode and no devices, keep table absent (no marking)
	if [ "$mode" = "devices" ] && [ -z "$dev4_elems" ] && [ -z "$dev6_elems" ]; then
		return 0
	fi

	# Create nft table + rules
	{
		echo "table inet $NFT_TABLE {"

		if [ -n "$dev4_elems" ]; then
			echo "  set devices4 { type ipv4_addr; elements = { $dev4_elems } }"
		else
			echo "  set devices4 { type ipv4_addr; elements = { } }"
		fi

		if [ -n "$dev6_elems" ]; then
			echo "  set devices6 { type ipv6_addr; elements = { $dev6_elems } }"
		else
			echo "  set devices6 { type ipv6_addr; elements = { } }"
		fi

		echo "  chain prerouting {"
		echo "    type filter hook prerouting priority mangle; policy accept;"

		# Avoid tunnel recursion if LAN clients try to reach your VPS
		if [ -n "$srv4" ]; then
			echo "    ip daddr $srv4 return"
		fi

		if [ "$mode" = "all" ]; then
			# Force all traffic entering from LAN ifaces that would route out WAN
			# Uses fib to only catch flows that would normally go out WAN
			echo "    iifname { $lan_iif_elems } fib daddr oifname \"$wan4\" meta mark set $fwmark"
		else
			# Per-device
			echo "    ip saddr @devices4 fib daddr oifname \"$wan4\" meta mark set $fwmark"
			# If WAN6 exists, use it for IPv6 (fallback to wan4 name if empty)
			[ -n "$wan6" ] || wan6="$wan4"
			echo "    ip6 saddr @devices6 fib daddr oifname \"$wan6\" meta mark set $fwmark"
		fi

		echo "  }"
		echo "}"
	} | nft -f -
}

routes_apply() {
	# Ensure table has default route via tun
	ip route flush table "$routing_table" 2>/dev/null || true
	ip route add default dev "$tun_ifname" table "$routing_table"

	# IPv6: do best-effort (won't fail the whole script if no v6)
	ip -6 route flush table "$routing_table" 2>/dev/null || true
	ip -6 route add default dev "$tun_ifname" table "$routing_table" 2>/dev/null || true

	# Replace rules idempotently
	ip rule del fwmark "$fwmark" lookup "$routing_table" 2>/dev/null || true
	ip rule add fwmark "$fwmark" lookup "$routing_table" priority 10000

	ip -6 rule del fwmark "$fwmark" lookup "$routing_table" 2>/dev/null || true
	ip -6 rule add fwmark "$fwmark" lookup "$routing_table" priority 10000 2>/dev/null || true
}

routes_clear() {
	ip rule del fwmark "$fwmark" lookup "$routing_table" 2>/dev/null || true
	ip -6 rule del fwmark "$fwmark" lookup "$routing_table" 2>/dev/null || true
	ip route flush table "$routing_table" 2>/dev/null || true
	ip -6 route flush table "$routing_table" 2>/dev/null || true
}

case "$1" in
	start)
		cfg_load
		[ "$enabled" -eq 1 ] || exit 0
		wait_for_tun "$tun_ifname" || { logger -t paqet "WARN: tun $tun_ifname not ready"; exit 0; }
		routes_apply
		nft_apply
		;;
	nft|fw4)
		cfg_load
		nft_apply
		;;
	stop)
		cfg_load
		nft_clear
		routes_clear
		;;
	*)
		echo "usage: $0 {start|stop|nft}"
		exit 1
		;;
esac
