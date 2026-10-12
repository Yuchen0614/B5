#include "BasicHacks.h"
#include <substrate.h>
#include <mach-o/dyld.h>
#include <string.h>

ModConfig g_ModConfig;

// ========== 原始函數指標 ==========
static void (*orig_checkPrepareTriggerAttackEvent)(void*, void*, double, int, int) = nullptr;
static void (*orig_checkTriggerAttackEvent)(void*, void*, double, int, int)      = nullptr;
static void* (*orig_changeHealthWithTarget)(void*, void*, double, int, int, int, int) = nullptr;
static bool  (*orig_canUseChestGemCostNow)(void*, void*, int) = nullptr;

// ========== Hook 實作 ==========

// 1. 核心傷害倍率
static void new_checkPrepareTriggerAttackEvent(void* instance, void* foe, double atkRate, int source, int sourceId) {
    double rate = atkRate;
    if (g_ModConfig.enableDamageMultiplier) rate *= g_ModConfig.damageMultiplier;
    if (orig_checkPrepareTriggerAttackEvent) orig_checkPrepareTriggerAttackEvent(instance, foe, rate, source, sourceId);
}

// 2. 二次傷害檢查
static void new_checkTriggerAttackEvent(void* instance, void* foe, double atkRate, int source, int sourceId) {
    double rate = atkRate;
    if (g_ModConfig.enableDamageMultiplier) rate *= g_ModConfig.damageMultiplier;
    if (orig_checkTriggerAttackEvent) orig_checkTriggerAttackEvent(instance, foe, rate, source, sourceId);
}

// 3. 無敵 / 血量鎖定
static void* new_changeHealthWithTarget(void* instance, void* target, double attackRate, int source, int sourceId, int hurtType, int weaponSource) {
    if (g_ModConfig.enableGodMode)
        return orig_changeHealthWithTarget ? orig_changeHealthWithTarget(instance, target, 0.0, source, sourceId, hurtType, weaponSource) : nullptr;
    return orig_changeHealthWithTarget ? orig_changeHealthWithTarget(instance, target, attackRate, source, sourceId, hurtType, weaponSource) : nullptr;
}

// 4. 免費購物 / 抽卡
static bool new_canUseChestGemCostNow(void* instance, void* itemData, int purchaseCount) {
    if (g_ModConfig.enableFreeShopping) return true;
    return orig_canUseChestGemCostNow ? orig_canUseChestGemCostNow(instance, itemData, purchaseCount) : false;
}

// ========== 初始化 ==========
static uintptr_t GetUnityBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void InitializeHooks() {
    static bool done = false;
    if (done) return;

    uintptr_t base = GetUnityBase();
    if (!base) return;
    done = true;

    #define HOOK(off, fn, orig) \
        MSHookFunction((void*)(base + (off)), (void*)(fn), (void**)&(orig))

    HOOK(OFFSET_CHECK_PREPARE_ATTACK, new_checkPrepareTriggerAttackEvent, orig_checkPrepareTriggerAttackEvent);
    HOOK(OFFSET_CHECK_TRIGGER_ATTACK, new_checkTriggerAttackEvent,      orig_checkTriggerAttackEvent);
    HOOK(OFFSET_CHANGE_HEALTH,        new_changeHealthWithTarget,       orig_changeHealthWithTarget);
    HOOK(OFFSET_CAN_USE_CHEST_GEM,    new_canUseChestGemCostNow,        orig_canUseChestGemCostNow);

    #undef HOOK
}
