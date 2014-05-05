ARCHS = armv7 armv7s arm64
TARGET = iphone:clang:7.1:7.0

include theos/makefiles/common.mk

BUNDLE_NAME = ApexSettings
ApexSettings_FILES = STKConfigurationController.m STKPrefsController.m STKProfileController.m STKTableViewCell.m PrefsHelper.m
ApexSettings_INSTALL_PATH = /Library/PreferenceBundles
ApexSettings_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics MessageUI Twitter Social QuartzCore
ApexSettings_PRIVATE_FRAMEWORKS = Preferences
ApexSettings_LIBRARIES = mobilegestalt

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ApexSettings.plist$(ECHO_END)
