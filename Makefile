export DEBUG = 1
export ARCHS = armv7 armv7s arm64
export TARGET = iphone:clang:7.1:7.0

ifeq ($(DEBUG), 0)
	PACKAGE_VERSION=$(THEOS_PACKAGE_BASE_VERSION)
endif

include theos/makefiles/common.mk

TWEAK_NAME = Apex
Apex_FILES :=  $(wildcard *.*m) $(wildcard *.x)
Apex_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore
Apex_LIBRARIES = mobilegestalt
Apex_CFLAGS += -Wall -Werror -O3

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
ifeq ($(DEBUG), 0)
	$(ECHO_NOTHING)python ./HashUpdate.py $(THEOS_PACKAGE_BASE_VERSION)$(ECHO_END)
endif

ifeq ($(KILLPREFS), 1)
	@install.exec "killall Preferences"
	@install.exec "cycript -p SpringBoard /var/root/apexsettings.cy"
else
	@install.exec "killall backboardd"
endif
