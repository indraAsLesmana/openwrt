#
# Copyright (C) 2007-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=freemesh-node
PKG_VERSION:=1.2.0
PKG_RELEASE:=$(shell git log | grep '^commit ' | wc -l)

include $(INCLUDE_DIR)/package.mk

define Package/freemesh-node
  SECTION:=freemesh
  CATEGORY:=freemesh Packages
  TITLE:=Default configuration for nodes in network
  VERSION:=$(PKG_VERSION)-$(PKG_RELEASE)
  DEPENDS:= +batctl-full +batctl-default +kmod-batman-adv
endef

define Package/freemesh-node/description
 Default configuration applied on first boot and reset.
 This package contains deaults for nodes. MESH only.
endef

define Build/Compile
	echo "Nothing to compile";
endef

define Package/freemesh-node/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,freemesh-node))
