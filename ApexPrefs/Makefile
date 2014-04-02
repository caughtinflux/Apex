include theos/makefiles/common.mk

BUNDLE_NAME = Apex
Apex_FILES = Apex.mm
Apex_INSTALL_PATH = /Library/PreferenceBundles
Apex_FRAMEWORKS = UIKit
Apex_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Apex.plist$(ECHO_END)
