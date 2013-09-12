# DEBUG = 1
NORESPRING = 1

include theos/makefiles/common.mk

TWEAK_NAME = ApexSpotlightHelper
ApexSpotlightHelper_FILES = Tweak.xm
ApexSpotlightHelper_PRIVATE_FRAMEWORKS = MobileInstallation GraphicsServices

after-install::
	install.exec "killall -9 searchd"

include $(THEOS_MAKE_PATH)/tweak.mk

