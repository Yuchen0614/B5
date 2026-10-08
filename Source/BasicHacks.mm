#include "BasicHacks.h"
#include "KMem/KMem.h"
#include <cstdint>

ModConfig g_ModConfig;

// 原始函數指標
void (*old_checkPrepareTriggerAttackEvent)(void* instance, void* foe, double atkRate, int source, int sourceId) = nullptr;
void (*old_checkTriggerAttackEvent)(void* instance, void* foe, double atkRate, int source, int sourceId) = nullptr;
void* (*old_changeHealthWithTarget)(void* instance, void* target, double attackRate, int source, int sourceId, int hurtType, int weaponSource) = nullptr;
bool (*old_canUseChestGemCostNow)(void* instance, void* itemData, int purchaseCount) = nullptr;

void new_checkPrepareTriggerAttackEvent(void* instance, void* foe, double atkRate, int source, int sourceId) {
    double modifiedRate = atkRate;
    if (g_ModConfig.enableDamageMultiplier) modifiedRate *= g_ModConfig.damageMultiplier;
    if (old_checkPrepareTriggerAttackEvent) old_checkPrepareTriggerAttackEvent(instance, foe, modifiedRate, source, sourceId);
}

void new_checkTriggerAttackEvent(void* instance, void* foe, double atkRate, int source, int sourceId) {
    double modifiedRate = atkRate;
    if (g_ModConfig.enableDamageMultiplier) modifiedRate *= g_ModConfig.damageMultiplier;
    if (old_checkTriggerAttackEvent) old_checkTriggerAttackEvent(instance, foe, modifiedRate, source, sourceId);
}

void* new_changeHealthWithTarget(void* instance, void* target, double attackRate, int source, int sourceId, int hurtType, int weaponSource) {
    if (g_ModConfig.enableGodMode) {
        if (old_changeHealthWithTarget) return old_changeHealthWithTarget(instance, target, 0.0, source, sourceId, hurtType, weaponSource);
        return nullptr;
    }
    return old_changeHealthWithTarget ? old_changeHealthWithTarget(instance, target, attackRate, source, sourceId, hurtType, weaponSource) : nullptr;
}

bool new_canUseChestGemCostNow(void* instance, void* itemData, int purchaseCount) {
    if (g_ModConfig.enableFreeShopping) return true;
    return old_canUseChestGemCostNow ? old_canUseChestGemCostNow(nullptr, nullptr, 0) : false;
}

void InitializeHooks() {
    uintptr_t base = KMEM::scanner::GetImageBase("UnityFramework");
    if (!base) base = (uintptr_t)_dyld_get_image_header(0);
    if (!base) return;

    KTempVars.Base = base;

    // Use TitanoxHook for hooking - it internally uses Dobby
    // Hook function signature: + (BOOL)hookStaticFunction:symbol withReplacement:replacement inLibrary:libName outOldFunction:oldFunction
    
    // 傷害倍率
    [TitanoxHook hookStaticFunction:"checkPrepareTriggerAttackEvent" withReplacement:(void*)new_checkPrepareTriggerAttackEvent inLibrary:"UnityFramework" outOldFunction:(void**)&old_checkPrepareTriggerAttackEvent];
    [TitanoxHook hookStaticFunction:"checkTriggerAttackEvent" withReplacement:(void*)new_checkTriggerAttackEvent inLibrary:"UnityFramework" outOldFunction:(void**)&old_checkTriggerAttackEvent];
    
    // 無敵
    [TitanoxHook hookStaticFunction:"changeHealthWithTarget" withReplacement:(void*)new_changeHealthWithTarget inLibrary:"UnityFramework" outOldFunction:(void**)&old_changeHealthWithTarget];
    
    // 免費購物/抽卡
    [TitanoxHook hookStaticFunction:"canUseChestGemCostNow" withReplacement:(void*)new_canUseChestGemCostNow inLibrary:"UnityFramework" outOldFunction:(void**)&old_canUseChestGemCostNow];
}

__attribute__((constructor))
static void initializer() {
    InitializeHooks();
}
