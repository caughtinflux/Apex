ARCHS = armv7
TARGET = iphone:clang:6.1:3.0

include theos/makefiles/common.mk

TWEAK_NAME = ApexGSHelper
ApexGSHelper_FILES = Tweak.mm
ApexGSHelper_PRIVATE_FRAMEWORKS = MobileInstallation GraphicsServices

after-install::
	@install.exec "killall -9 searchd"

include $(THEOS_MAKE_PATH)/tweak.mk

