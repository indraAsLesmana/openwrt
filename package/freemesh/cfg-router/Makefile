#
# Copyright (C) 2007-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=freemesh-router
PKG_VERSION:=1.2.0
PKG_RELEASE:=$(shell git log | grep '^commit ' | wc -l)

include $(INCLUDE_DIR)/package.mk

define Package/freemesh-router
  SECTION:=freemesh
  CATEGORY:=freemesh Packages
  TITLE:=Default configuration for main router in network
  VERSION:=$(PKG_VERSION)-$(PKG_RELEASE)
  DEPENDS:= +batctl-full +batctl-default +kmod-batman-adv +luci
endef

define Package/freemesh-router/description
 Default configuration applied on first boot and reset.
 This package contains defaults for main router. MESH.
endef

define Build/Compile
	echo "Nothing to compile";
endef

define Package/freemesh-router/install
	[ -e "./files" ] && $(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,freemesh-router))
