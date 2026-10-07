#include "BasicHacks.h"
#include "dobby.h"
#include "KMem/KMem.h"
#include <cstdint>

struct ModConfig {
    bool enableDamageMultiplier = false;
    float damageMultiplier = 10.0f;
    bool enableGodMode = false;
    bool enableFreeShopping = false;
};

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

    // 1. 核心傷害倍率
    void* addr1 = (void*)(KMEM::scanner::GetImageBase("UnityFramework") + 0x2EDD480);
    if (KMEM::io::IsValidPointer(addr1)) {
        DobbyHook(addr1, (void*)new_checkPrepareTriggerAttackEvent, (void**)&old_checkPrepareTriggerAttackEvent);
    }

    // 二次檢查
    void* addr2 = (void*)(KMEM::scanner::GetImageBase("UnityFramework") + 0x2EDD4B0);
    if (KMEM::io::IsValidPointer(addr2)) {
        DobbyHook(addr2, (void*)new_checkTriggerAttackEvent, (void**)&old_checkTriggerAttackEvent);
    }

    // 無敵/血量
    void* addr3 = (void*)(KMEM::scanner::GetImageBase("UnityFramework") + 0x2EDD630);
    if (KMEM::io::IsValidPointer(addr3)) {
        DobbyHook(addr3, (void*)new_changeHealthWithTarget, (void**)&old_changeHealthWithTarget);
    }

    // 免費購物/抽卡
    void* addr4 = (void*)(KMEM::scanner::GetImageBase("UnityFramework") + 0x27D1124);
    if (KMEM::io::IsValidPointer(addr4)) {
        DobbyHook(addr4, (void*)new_canUseChestGemCostNow, (void**)&old_canUseChestGemCostNow);
    }
}

__attribute__((constructor))
static void initializer() {
    InitializeHooks();
}
