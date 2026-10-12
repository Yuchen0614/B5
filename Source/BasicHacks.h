#ifndef BASIC_HACKS_H
#define BASIC_HACKS_H

#include <cstdint>

#define TARGET_BINARY "UnityFramework"

// ========== 已驗證可用的 RVA ==========
#define OFFSET_CHECK_PREPARE_ATTACK 0x2EDD480      // checkPrepareTriggerAttackEvent
#define OFFSET_CHECK_TRIGGER_ATTACK 0x2EDD4B0      // checkTriggerAttackEvent
#define OFFSET_CHANGE_HEALTH 0x2EDD630             // changeHealthWithTarget
#define OFFSET_CAN_USE_CHEST_GEM 0x27D1124         // canUseChestGemCostNow (免費購物/抽卡)

struct ModConfig {
    bool  enableDamageMultiplier = false;
    float damageMultiplier       = 10.0f;
    bool  enableGodMode          = false;
    bool  enableFreeShopping     = false;
};

extern struct ModConfig g_ModConfig;

// 由 MenuLoad 呼叫 (UnityFramework 載入後)
void InitializeHooks();

#endif // BASIC_HACKS_H
