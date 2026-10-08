#include "BasicHacks.h"
#include "dobby.h"
#include "../utils/Komaru/KMem.h"
#include <cstdint>
#include "../MenuLoad/Includes.h"

ModConfig g_ModConfig;

// 原始函數指標
void (*old_checkPrepareTriggerAttackEvent)(void* instance, void* foe, double atkRate, int source, int sourceId) = nullptr;
void (*old_checkTriggerAttackEvent)(void* instance, void* foe, double atkRate, int source, int sourceId) = nullptr;
void* (*old_changeHealthWithTarget)(void* instance, void* target, double attackRate, int source, int sourceId, int hurtType, int weaponSource) = nullptr;
bool (*old_canUseChestGemCostNow)(void* instance, void* itemData, int purchaseCount) = nullptr;

// ========== Hook 實作 ==========

// 1. 核心傷害倍率 Hook
void new_checkPrepareTriggerAttackEvent(void* instance, void* foe, double atkRate, int source, int sourceId) {
    double modifiedRate = atkRate;
    if (g_ModConfig.enableDamageMultiplier) {
        modifiedRate *= g_ModConfig.damageMultiplier;
    }
    if (old_checkPrepareTriggerAttackEvent) {
        old_checkPrepareTriggerAttackEvent(instance, foe, modifiedRate, source, sourceId);
    }
}

// 二次檢查傷害倍率 Hook
void new_checkTriggerAttackEvent(void* instance, void* foe, double atkRate, int source, int sourceId) {
    double modifiedRate = atkRate;
    if (g_ModConfig.enableDamageMultiplier) {
        modifiedRate *= g_ModConfig.damageMultiplier;
    }
    if (old_checkTriggerAttackEvent) {
        old_checkTriggerAttackEvent(instance, foe, modifiedRate, source, sourceId);
    }
}

// 無敵/血量修改 Hook
void* new_changeHealthWithTarget(void* instance, void* target, double attackRate, int source, int sourceId, int hurtType, int weaponSource) {
    if (g_ModConfig.enableGodMode) {
        if (old_changeHealthWithTarget) {
            return old_changeHealthWithTarget(instance, target, 0.0, source, sourceId, hurtType, weaponSource);
        }
        return nullptr;
    }
    return old_changeHealthWithTarget ? old_changeHealthWithTarget(instance, target, attackRate, source, sourceId, hurtType, weaponSource) : nullptr;
}

// 免費購物/抽卡 Hook
bool new_canUseChestGemCostNow(void* instance, void* itemData, int purchaseCount) {
    if (g_ModConfig.enableFreeShopping) {
        return true;
    }
    return old_canUseChestGemCostNow ? old_canUseChestGemCostNow(nullptr, nullptr, 0) : false;
}

void InitializeHooks() {
    uintptr_t base = KMEM::scanner::GetImageBase("UnityFramework");
    if (!base) base = (uintptr_t)_dyld_get_image_header(0);
    if (!base) return;

    // 更新 Base 供選單顯示
    KTempVars.Base = base;

    // 1. 核心傷害倍率
    uintptr_t addr1 = base + 0x2EDD480;
    if (KMEM::io::IsValidPointer(addr1)) {
        DobbyHook((void*)addr1, (void*)new_checkPrepareTriggerAttackEvent, (void**)&old_checkPrepareTriggerAttackEvent);
    }

    // 二次檢查
    uintptr_t addr2 = base + 0x2EDD4B0;
    if (KMEM::io::IsValidPointer(addr2)) {
        DobbyHook((void*)addr2, (void*)new_checkTriggerAttackEvent, (void**)&old_checkTriggerAttackEvent);
    }

    // 無敵/血量
    uintptr_t addr3 = base + 0x2EDD630;
    if (KMEM::io::IsValidPointer(addr3)) {
        DobbyHook((void*)addr3, (void*)new_changeHealthWithTarget, (void**)&old_changeHealthWithTarget);
    }

    // 免費購物/抽卡
    uintptr_t addr4 = base + 0x27D1124;
    if (KMEM::io::IsValidPointer(addr4)) {
        DobbyHook((void*)addr4, (void*)new_canUseChestGemCostNow, (void**)&old_canUseChestGemCostNow);
    }
}

__attribute__((constructor))
static void initializer() {
    InitializeHooks();
}
