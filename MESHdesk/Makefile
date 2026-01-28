include $(TOPDIR)/rules.mk

PKG_NAME:=MESHdesk
PKG_VERSION:=9.6.1
PKG_RELEASE:=01

include $(INCLUDE_DIR)/package.mk

define Package/MESHdesk
   SECTION:=net
   CATEGORY:=Base system
   TITLE:=MESHdesk firmware
   URL:=http://radiusdesk.com/
endef


define Package/MESHdesk/description
MESHdesk is part of RADIUSdesk
endef

define Build/Compile
	rm -rf $(PKG_INSTALL_DIR)
	mkdir -p $(PKG_INSTALL_DIR)
endef

define Package/MESHdesk/install
   	$(INSTALL_DIR) $(1)/etc/MESHdesk
	$(INSTALL_DIR) $(1)/etc/MESHdesk/captive_portals
	$(INSTALL_DIR) $(1)/etc/MESHdesk/configs
	$(INSTALL_DIR) $(1)/etc/MESHdesk/files
	$(INSTALL_DIR) $(1)/etc/MESHdesk/libs
	$(INSTALL_DIR) $(1)/etc/MESHdesk/reporting
	$(INSTALL_DIR) $(1)/etc/MESHdesk/tests
	$(INSTALL_DIR) $(1)/etc/MESHdesk/utils
	cp -r ./files/MESHdesk/captive_portals/* $(1)/etc/MESHdesk/captive_portals
	cp -r ./files/MESHdesk/configs/* $(1)/etc/MESHdesk/configs
	cp -r ./files/MESHdesk/files/* $(1)/etc/MESHdesk/files
	cp -r ./files/MESHdesk/libs/* $(1)/etc/MESHdesk/libs
	cp -r ./files/MESHdesk/reporting/* $(1)/etc/MESHdesk/reporting
	cp -r ./files/MESHdesk/tests/* $(1)/etc/MESHdesk/tests
	cp -r ./files/MESHdesk/utils/* $(1)/etc/MESHdesk/utils
	$(INSTALL_BIN) ./files/MESHdesk/a.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/batman_neighbours.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/heartbeat.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/hotplug_lan.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/led.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/main_led.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/bailout.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/watchdog.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/mqtt.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/mqtt_watcher.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/rogue_scan.lua $(1)/etc/MESHdesk/
	$(INSTALL_BIN) ./files/MESHdesk/mac_setter.lua $(1)/etc/MESHdesk/
	mkdir -p $(1)/etc/init.d
	$(INSTALL_BIN) ./files/MESHdesk/md_prerun $(1)/etc/init.d
	$(INSTALL_BIN) ./files/MESHdesk/md_prep $(1)/etc/init.d
	mkdir -p $(1)/etc/config
	$(INSTALL_DATA) ./files/MESHdesk/meshdesk $(1)/etc/config
	mkdir -p $(1)/etc/hotplug.d/iface
	cp -r ./files/MESHdesk/hotplug_dir/hotplug.d/iface/* $(1)/etc/hotplug.d/iface
	mkdir -p $(1)/etc/chilli/www
	cp ./files/MESHdesk/files/common/radiusdesk.html $(1)/etc/chilli/www
endef

define Package/MESHdesk/postinst
#!/bin/sh
exit 0
endef

define Package/MESHdesk/prerm
#!/bin/sh
# check if we are on real system
if [ -z "$${IPKG_INSTROOT}" ]; then
        echo "Removing rc.d symlink for MESHdesk"
        /etc/init.d/md_prerun disable
        /etc/init.d/md_prep disable 
fi
exit 0
endef

$(eval $(call BuildPackage,MESHdesk))
