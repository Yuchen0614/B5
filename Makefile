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
    ImGui/imgui.cpp \
    ImGui/imgui_draw.cpp \
    ImGui/imgui_tables.cpp \
    ImGui/imgui_widgets.cpp \
    ImGui/imgui_impl_metal.mm \
    utils/libtitanox/brk_hook/Hook/hook.c \
    utils/libtitanox/brk_hook/Hook/mach_excServer.c \
    utils/libtitanox/fishhook/fishhook.c \
    utils/libtitanox/libtitanox/main.mm \
    utils/libtitanox/mempatch/THPatchMem.mm \
    utils/libtitanox/MemX/VMTWrapper.mm \
    utils/libtitanox/static-inline-hook/sih.mm \
    utils/libtitanox/utils/utils.mm \
    utils/libtitanox/vm_funcs/vm.mm \
    utils/Komaru/KLog.mm

$(TWEAK_NAME)_LIBRARIES += substrate
$(TWEAK_NAME)_LDFLAGS += -L./utils/libtitanox -ldobby

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS)/makefiles/aggregate.mk

after-install::
	install.exec "killall -9 idlegongfu || :"
