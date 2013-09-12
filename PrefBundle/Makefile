include theos/makefiles/common.mk

BUNDLE_NAME = ApexSettings
ApexSettings_FILES = STKPrefsController.m STKProfileController.m STKTableViewCell.m PrefsHelper.m
ApexSettings_INSTALL_PATH = /Library/PreferenceBundles
ApexSettings_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics MessageUI Twitter Social QuartzCore
ApexSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ApexSettings.plist$(ECHO_END)
