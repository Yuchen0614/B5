#ifndef BASIC_HACKS_H
#define BASIC_HACKS_H

#include <cstdint>
#import "libtitanox.h"

#define TARGET_BINARY "UnityFramework"

#define OFFSET_CHECK_PREPARE_ATTACK 0x2EDD480
#define OFFSET_CHECK_TRIGGER_ATTACK 0x2EDD4B0
#define OFFSET_CHANGE_HEALTH 0x2EDD630
#define OFFSET_CAN_USE_CHEST_GEM 0x27D1124

struct ModConfig {
    bool enableDamageMultiplier = false;
    float damageMultiplier = 10.0f;
    bool enableGodMode = false;
    bool enableFreeShopping = false;
};

extern struct ModConfig g_ModConfig;

void InitializeHooks();

#endif
