include $(TOPDIR)/rules.mk

PKG_NAME:=paqet
PKG_VERSION:=1.0.0-alpha.15
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/hanselime/paqet.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_PARALLEL:=1
PKG_BUILD_DEPENDS:=golang/host

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

GO_PKG:=github.com/hanselime/paqet
GO_PKG_BUILD_PKG:=./cmd
GO_PKG_BUILD_BIN:=paqet

define Package/paqet
  SECTION:=net
  CATEGORY:=Network
  TITLE:=paqet - transport over raw packets (OpenWrt client)
  URL:=https://github.com/hanselime/paqet
  DEPENDS:=$(GO_ARCH_DEPENDS) +libpcap +sing-box +kmod-tun +ip-full +nftables
endef

define Package/paqet/conffiles
/etc/config/paqet
endef

define Package/paqet/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/paqet $(1)/etc/config/paqet

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/paqet $(1)/etc/init.d/paqet

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/99-paqet $(1)/etc/uci-defaults/99-paqet

	$(INSTALL_DIR) $(1)/usr/share/paqet
	$(INSTALL_BIN) ./files/usr/share/paqet/gen.sh $(1)/usr/share/paqet/gen.sh
	$(INSTALL_BIN) ./files/usr/share/paqet/rules.sh $(1)/usr/share/paqet/rules.sh
	$(INSTALL_BIN) ./files/usr/share/paqet/fw4.include $(1)/usr/share/paqet/fw4.include

	$(INSTALL_DIR) $(1)/etc/paqet
endef

$(eval $(call GoBinPackage,paqet))
$(eval $(call BuildPackage,paqet))
