module("luci.controller.paqet", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/paqet") then
		return
	end

	entry({"admin", "services", "paqet"}, cbi("paqet"), _("Paqet Tunnel"), 60).dependent = false
end
