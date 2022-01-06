module("luci.controller.meshdesk.meshdesk", package.seeall)

function index()
    entry( {"admin", "services", "meshdesk"}, cbi("meshdesk/meshdesk"), _("MESHdesk Settings"), 59).acl_depends = { "luci-app-meshdesk" }
--    entry( {"admin", "services", "meshdesk"}, template("meshdesk/index"), _("MESHdesk Settings"), 59).acl_depends = { "luci-app-meshdesk" }
--    entry( {"admin", "services", "meshdesk"}, call("action_tryme"), _("MESHdesk Settings"), 59).acl_depends = { "luci-app-meshdesk" }
    entry({"click", "here", "now"}, call("action_tryme"), "Click here", 10).dependent=false

end
 
function action_tryme()
    luci.http.prepare_content("text/plain")
    luci.http.write("Haha, rebooting now...")
--    luci.sys.reboot()
end

