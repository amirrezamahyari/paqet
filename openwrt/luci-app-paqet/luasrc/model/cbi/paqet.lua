local sys  = require "luci.sys"

m = Map("paqet", translate("Paqet Tunnel"))
m.description = translate("VPN-like per-device tunneling using paqet (SOCKS) + sing-box (TUN).")

-- Status
local running = (sys.call("pgrep -x paqet >/dev/null") == 0)
local s_status = m:section(SimpleSection)
s_status.template  = "cbi/nullsection"
s_status.title     = translate("Status")
s_status.description = running and translate("Service is running.") or translate("Service is stopped.")

-- Main settings
s = m:section(NamedSection, "main", "paqet", translate("Settings"))
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable"))
o.rmempty = false

o = s:option(ListValue, "mode", translate("Tunnel mode"))
o:value("devices", translate("Per-device (default)"))
o:value("all", translate("Force all LAN traffic"))
o.default = "devices"

o = s:option(Value, "server_addr", translate("VPS server address"))
o.datatype = "hostport"
o.placeholder = "203.0.113.10:9999"

o = s:option(Value, "key", translate("KCP key"))
o.password = true

o = s:option(Value, "socks_listen", translate("Local SOCKS listen"))
o.placeholder = "127.0.0.1:1080"

o = s:option(DynamicList, "lan_iif", translate("LAN ingress interfaces (mode=all)"))
o:depends("mode", "all")
o.placeholder = "br-lan"

o = s:option(Value, "tun_ifname", translate("TUN interface name"))
o.default = "paqet0"

o = s:option(Value, "tun_mtu", translate("TUN MTU"))
o.datatype = "uinteger"
o.default = "1500"

o = s:option(Value, "log_level", translate("paqet log level"))
o:value("none")
o:value("debug")
o:value("info")
o:value("warn")
o:value("error")
o:value("fatal")
o.default = "info"

-- Buttons
btn = s:option(Button, "_restart", translate("Restart service"))
btn.inputstyle = "apply"
function btn.write()
	sys.call("/etc/init.d/paqet restart >/dev/null 2>&1")
end

btn2 = s:option(Button, "_stop", translate("Stop service"))
btn2.inputstyle = "reset"
function btn2.write()
	sys.call("/etc/init.d/paqet stop >/dev/null 2>&1")
end

btn3 = s:option(Button, "_start", translate("Start service"))
btn3.inputstyle = "apply"
function btn3.write()
	sys.call("/etc/init.d/paqet start >/dev/null 2>&1")
end

-- Device list
d = m:section(TypedSection, "device", translate("Proxied devices"))
d.addremove = true
d.anonymous = true

de = d:option(Flag, "enabled", translate("Enabled"))
de.default = "1"

dn = d:option(Value, "name", translate("Name"))
dn.optional = true

dip = d:option(Value, "ip", translate("Client IP address"))
dip.datatype = "ipaddr"
dip.placeholder = "192.168.1.123"

-- Logs
log = m:section(SimpleSection, translate("Logs (last 200 lines)"))
tv = log:option(TextValue, "_log")
tv.rows = 20
tv.wrap = "off"
tv.readonly = true
function tv.cfgvalue()
	return sys.exec("logread -e paqet -e sing-box | tail -n 200")
end

return m
