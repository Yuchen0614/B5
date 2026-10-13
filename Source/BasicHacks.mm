#include "BasicHacks.h"
#include <substrate.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <libkern/OSCacheControl.h>
#include <string.h>
#include <stdio.h>

ModConfig g_ModConfig;

// ========== 診斷資訊 (顯示在選單上) ==========
HookDiag  g_HookDiag[MAX_HOOK_DIAG];
int       g_HookDiagCount = 0;
char      g_BaseImage[512] = {0};
uintptr_t g_BaseAddr = 0;

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

// 確認位址落在可讀+可執行的記憶體區段，避免掛到爛位址直接閃退
static bool IsExecutable(uintptr_t addr) {
    vm_address_t region = (vm_address_t)addr;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &region, &size,
                                    VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &count, &obj);
    if (kr != KERN_SUCCESS) return false;
    if (addr < region || addr >= region + size) return false;
    return (info.protection & (VM_PROT_READ | VM_PROT_EXECUTE)) == (VM_PROT_READ | VM_PROT_EXECUTE);
}

// 1) 先找 UnityFramework image；2) 退回主執行檔 (il2cpp 靜態連結的情況)。
//    重點：主執行檔只有在「base + 代表RVA 落在可執行區段」時才採用，
//    否則代表 UnityFramework 只是還沒載入，回傳 0 讓下一幀重試 (避免鎖死錯誤 base)。
static uintptr_t PickBase(const char** outName) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) {
            uintptr_t b = (uintptr_t)_dyld_get_image_header(i);
            if (b && IsExecutable(b + OFFSET_CHECK_PREPARE_ATTACK)) {
                if (outName) *outName = n;
                return b;
            }
        }
    }
    // fallback: 主執行檔
    const char* m = _dyld_get_image_name(0);
    uintptr_t b0 = (uintptr_t)_dyld_get_image_header(0);
    if (m && b0 && IsExecutable(b0 + OFFSET_CHECK_PREPARE_ATTACK)) {
        if (outName) *outName = m;
        return b0;
    }
    return 0;   // 都還不成立 → 下一幀再試
}

// ================= 手動 arm64 inline hook =================
// 不依賴 substrate：vm_protect 改成可寫 → vm_write 寫入跳轉 → 還原 → flush icache
// 注意：iOS SDK 的 <mach/mach_vm.h> 會直接報「mach_vm.h unsupported」，
//       所以只能用 vm_* 系列 API (vm_protect / vm_write / vm_allocate)。
#define IOS_PAGE 0x4000

static bool MakeWritable(uintptr_t addr, size_t len) {
    vm_address_t page = (vm_address_t)(addr & ~(uintptr_t)(IOS_PAGE - 1));
    vm_size_t span = (vm_size_t)((addr - (uintptr_t)page) + len);
    kern_return_t kr = vm_protect(mach_task_self(), page, span, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        kr = vm_protect(mach_task_self(), page, span, FALSE,
                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    }
    return kr == KERN_SUCCESS;
}

static void RestoreRX(uintptr_t addr, size_t len) {
    vm_address_t page = (vm_address_t)(addr & ~(uintptr_t)(IOS_PAGE - 1));
    vm_size_t span = (vm_size_t)((addr - (uintptr_t)page) + len);
    vm_protect(mach_task_self(), page, span, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
}

static bool RawWrite(uintptr_t addr, const void* data, size_t len) {
    if (!MakeWritable(addr, len)) return false;
    kern_return_t kr = vm_write(mach_task_self(), (vm_address_t)addr,
                                (vm_offset_t)data, (mach_msg_type_number_t)len);
    RestoreRX(addr, len);
    sys_icache_invalidate((void*)addr, len);
    return kr == KERN_SUCCESS;
}

// trampoline: 複製被覆蓋的 16 bytes，後面接「跳回 target+16」
static uintptr_t MakeTrampoline(uintptr_t target) {
    vm_address_t tramp = 0;
    if (vm_allocate(mach_task_self(), &tramp, IOS_PAGE, VM_FLAGS_ANYWHERE) != KERN_SUCCESS)
        return 0;
    if (vm_protect(mach_task_self(), tramp, IOS_PAGE, FALSE,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE) != KERN_SUCCESS)
        return 0;

    memcpy((void*)tramp, (void*)target, 16);          // 原始 4 條指令

    uint32_t j0 = 0x58000050;                          // ldr x16, #8
    uint32_t j1 = 0xD61F0200;                          // br  x16
    uintptr_t back = target + 16;
    memcpy((void*)(tramp + 16), &j0,   4);
    memcpy((void*)(tramp + 20), &j1,   4);
    memcpy((void*)(tramp + 24), &back, 8);

    sys_icache_invalidate((void*)tramp, 32);
    return (uintptr_t)tramp;
}

static bool InstallInlineHook(uintptr_t target, void* hook, void** outOrig) {
    uintptr_t tramp = MakeTrampoline(target);
    if (!tramp) return false;

    uint8_t patch[16];
    uint32_t i0 = 0x58000050;                          // ldr x16, #8
    uint32_t i1 = 0xD61F0200;                          // br  x16
    uintptr_t dest = (uintptr_t)hook;
    memcpy(patch,     &i0,   4);
    memcpy(patch + 4, &i1,   4);
    memcpy(patch + 8, &dest, 8);

    if (!RawWrite(target, patch, 16)) return false;
    if (outOrig) *outOrig = (void*)tramp;
    return true;
}
// =========================================================

static void DoHook(const char* name, uint32_t rva, void* fn, void** orig) {
    if (g_HookDiagCount >= MAX_HOOK_DIAG) return;

    uintptr_t addr = g_BaseAddr + rva;
    HookDiag& d = g_HookDiag[g_HookDiagCount++];
    d.name = name;
    d.rva  = rva;
    d.addr = addr;
    d.before = 0;
    d.after  = 0;
    d.installed = false;
    d.method = 0;
    d.msRet  = -999;

    if (!IsExecutable(addr)) {
        // 位址不可執行 → 不掛，避免閃退
        return;
    }

    d.before = *(volatile uint32_t*)addr;

    // ---- 方法 1: MSHookFunction (Theos 的 substrate 回傳 void，無回傳值可判斷) ----
    MSHookFunction((void*)addr, fn, orig);
    d.after = *(volatile uint32_t*)addr;
    if (d.before != d.after) {
        d.installed = true;
        d.method = 1;
        return;
    }

    // ---- 方法 2: 手動 inline hook (substrate 無效時) ----
    if (InstallInlineHook(addr, fn, orig)) {
        d.after = *(volatile uint32_t*)addr;
        if (d.before != d.after) {
            d.installed = true;
            d.method = 2;
        }
    }
}

void InitializeHooks() {
    static bool done = false;
    if (done) return;

    const char* imgName = nullptr;
    uintptr_t base = PickBase(&imgName);
    if (!base) return;          // 還沒載入，下一幀再試

    done = true;
    g_BaseAddr = base;
    if (imgName) {
        strncpy(g_BaseImage, imgName, sizeof(g_BaseImage) - 1);
        g_BaseImage[sizeof(g_BaseImage) - 1] = '\0';
    }

    DoHook("checkPrepareTriggerAttackEvent", OFFSET_CHECK_PREPARE_ATTACK,
           (void*)new_checkPrepareTriggerAttackEvent, (void**)&orig_checkPrepareTriggerAttackEvent);
    DoHook("checkTriggerAttackEvent", OFFSET_CHECK_TRIGGER_ATTACK,
           (void*)new_checkTriggerAttackEvent, (void**)&orig_checkTriggerAttackEvent);
    // 注意：changeHealthWithTarget (0x2EDD630) 屬於 HeroBaseAttack，
    //       是「英雄造成傷害」的函數，設 attackRate=0 只會讓玩家打不出傷害，
    //       不是無敵，還會抵銷傷害倍率 → 本輪先不掛，改用 HeroIns 的無敵欄位。
    // DoHook("changeHealthWithTarget", OFFSET_CHANGE_HEALTH,
    //        (void*)new_changeHealthWithTarget, (void**)&orig_changeHealthWithTarget);
    DoHook("canUseChestGemCostNow", OFFSET_CAN_USE_CHEST_GEM,
           (void*)new_canUseChestGemCostNow, (void**)&orig_canUseChestGemCostNow);
}
