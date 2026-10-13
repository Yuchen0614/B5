#ifndef BASIC_HACKS_H
#define BASIC_HACKS_H

#include <cstdint>

#define TARGET_BINARY "UnityFramework"

// ========== 已驗證可用的 RVA (對照 dump.cs) ==========
#define OFFSET_CHECK_PREPARE_ATTACK 0x2EDD480      // checkPrepareTriggerAttackEvent(Foe, double atkRate, int source, int sourceId)
#define OFFSET_CHECK_TRIGGER_ATTACK 0x2EDD4B0      // checkTriggerAttackEvent(Foe, double atkRate, int source, int sourceId)
#define OFFSET_CHANGE_HEALTH 0x2EDD630             // changeHealthWithTarget(Foe, double attackRate, int source, int sourceId, int hurtType, int weaponSource)
#define OFFSET_CAN_USE_CHEST_GEM 0x27D1124         // canUseChestGemCostNow(StoreItemData, int) -> bool

#define MAX_HOOK_DIAG 4

struct ModConfig {
    bool  enableDamageMultiplier = false;
    float damageMultiplier       = 10.0f;
    bool  enableGodMode          = false;
    bool  enableFreeShopping     = false;
};

// 診斷用：記錄每個 hook 掛上去前後的前 4 bytes
struct HookDiag {
    const char* name;       // 函數名
    uint32_t    rva;        // 預期 RVA
    uintptr_t   addr;       // 實際位址 (base + rva)
    uint32_t    before;     // 掛鉤前 4 bytes
    uint32_t    after;      // 掛鉤後 4 bytes
    bool        installed;  // before != after => 真的被改寫了
    int         method;     // 0=無, 1=MSHookFunction, 2=手動inline, 3=直接改寫
    int         msRet;      // MSHookFunction 回傳值
    int         protBefore; // 該頁修改前的保護旗標 (VM_PROT_*)
    int         protAfter;  // 該頁修改後的保護旗標 (VM_PROT_*)
};

extern struct ModConfig g_ModConfig;

extern HookDiag  g_HookDiag[MAX_HOOK_DIAG];
extern int       g_HookDiagCount;
extern char      g_BaseImage[512];
extern uintptr_t g_BaseAddr;

// 由 MenuLoad 呼叫 (UnityFramework 載入後)
void InitializeHooks();

// 免費購物：由選單即時切換 (on=寫入 patch, off=還原原始指令)
void ApplyFreeShop(bool on);

#endif // BASIC_HACKS_H
