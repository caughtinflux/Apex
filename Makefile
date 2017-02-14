export DEBUG = 1
export ARCHS = armv7 arm64
export SDKVERSION = 10.1
export SYSROOT = $(THEOS)/sdks/iPhoneOS10.1.sdk
export TARGET = iphone:clang:10.1:7.0

include theos/makefiles/common.mk

TWEAK_NAME = Apex
Apex_FILES :=  $(wildcard *.*m) $(wildcard *.x)
Apex_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore

Apex_LIBRARIES = mobilegestalt
Apex_CFLAGS += -Wall -Werror -Wno-c++11-extensions

ifeq ($(DEBUG), 0)
Apex_CFLAGS += -O3
endif

ifeq ($(DEBUG), 1)
	ADDITIONAL_LDFLAGS += -Wl,-map,$@.map -g -x c /dev/null -x none
endif

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += SBSHook
SUBPROJECTS += PrefBundle

before-all::
	$(ECHO_NOTHING)python ./VersionUpdate.py $(THEOS_PACKAGE_BASE_VERSION)$(ECHO_END)
	$(ECHO_NOTHING)touch -t 2012310000 PrefBundle/STKPrefsController.m$(ECHO_END)

include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
ifeq ($(KILLPREFS), 1)
	@install.exec "killall Preferences"
	@install.exec "cycript -p SpringBoard /var/root/apexsettings.cy"
else
	@install.exec "killall backboardd"
endif
