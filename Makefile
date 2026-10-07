ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1

TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IdleGongfuModMenu

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation Security QuartzCore CoreGraphics CoreText AVFoundation Accelerate GLKit SystemConfiguration GameController

$(TWEAK_NAME)_CCFLAGS = -std=c++17 -fno-rtti -fno-exceptions -DNDEBUG -DUNITY
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-value -I./Source -I./utils -I./ImGui -I./utils/libtitanox

$(TWEAK_NAME)_FILES = \
    Source/BasicHacks.mm \
    MenuLoad/MenuLoad.mm \
    MenuLoad/ImGuiDrawView.xm \
    MenuLoad/GUI/UserMenu.mm \
    $(wildcard ImGui/*.cpp) \
    $(wildcard utils/libtitanox/**/*.cpp) \
    $(wildcard utils/Komaru/*.mm)

$(TWEAK_NAME)_LIBRARIES += substrate
$(TWEAK_NAME)_LDFLAGS += -L./utils/libtitanox -ldobby

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS)/makefiles/aggregate.mk

after-install::
	install.exec "killall -9 idlegongfu || :"
