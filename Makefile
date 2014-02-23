DEBUG = 1
ARCHS = armv7 armv7s arm64
TARGET = iphone:clang:7.0:7.0

ifeq ($DEBUG,0)
	PACKAGE_VERSION=$(THEOS_PACKAGE_BASE_VERSION)
endif

include theos/makefiles/common.mk

TWEAK_NAME = Apex
Apex_FILES :=  $(wildcard *.*m)
Apex_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore
Apex_CFLAGS += -Wall -Werror -O3
ADDITIONAL_LDFLAGS += -Wl,-map,$@.map -g -x c /dev/null -x none

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += SBSHook
SUBPROJECTS += PrefBundle

before-all::
	$(ECHO_NOTHING)python ./VersionUpdate.py $(THEOS_PACKAGE_BASE_VERSION)$(ECHO_END)
	$(ECHO_NOTHING)touch -t 2012310000 PrefBundle/STKPrefsController.m$(ECHO_END)

include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	@install.exec "killall backboardd"
