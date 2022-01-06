#
# Copyright (C) 2008-2015 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#
     
include $(TOPDIR)/rules.mk
     
PKG_NAME:=luci-app-meshdesk
     
# Version == major.minor.patch
# increase "minor" on new functionality and "patch" on patches/optimization
PKG_VERSION:=8.0.0
     
# Release == build
# increase on changes of translation files
PKG_RELEASE:=1
     
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Dirk van der Walt   <dirkvanderwalt@gmail.com>
     
# LuCI specific settings
LUCI_TITLE:=LuCI Support for MESHdesk firmware
LUCI_DEPENDS:=+luci-mod-admin-full
LUCI_PKGARCH:=all
     
define Package/$(PKG_NAME)/config
# shown in make menuconfig <Help>
help
      $(LUCI_TITLE)
      .
      Version: $(PKG_VERSION)-$(PKG_RELEASE)
      $(PKG_MAINTAINER)
endef
     
include ../../luci.mk
     
# call BuildPackage - OpenWrt buildroot signature

