#ifndef BASIC_HACKS_H
#define BASIC_HACKS_H

#include <cstdint>

#define TARGET_BINARY "UnityFramework"

// ========== 已驗證可用的 RVA (對照 dump.cs) ==========
#define OFFSET_CHECK_PREPARE_ATTACK 0x2EDD480      // checkPrepareTriggerAttackEvent(Foe, double atkRate, int source, int sourceId)
#define OFFSET_CHECK_TRIGGER_ATTACK 0x2EDD4B0      // checkTriggerAttackEvent(Foe, double atkRate, int source, int sourceId)
#define OFFSET_CHANGE_HEALTH 0x2EDD630             // changeHealthWithTarget(Foe, double attackRate, int source, int sourceId, int hurtType, int weaponSource)
#define OFFSET_CAN_USE_CHEST_GEM 0x27D1124         // canUseChestGemCostNow(StoreItemData, int) -> bool

// 扣資源的函數 (都回傳 void → 可直接改寫成 ret = 不扣資源 = 免費購物/資源不減)
#define OFFSET_COST_RESOURCE 0x2763E40             // costResource(int id, double count, RewardChannel)
#define OFFSET_COST_GOLD     0x27BF2B8             // costGold(double count, RewardChannel)
#define OFFSET_COST_GEM      0x278C304             // costGem(double count, RewardChannel)

#define MAX_HOOK_DIAG 8

struct ModConfig {
    bool  enableDamageMultiplier = false;
    float damageMultiplier       = 100000.0f;   // 預設放大 10 萬倍 = 實質秒殺
    bool  enableGodMode          = false;
    bool  enableFreeShopping     = false;
    bool  enableWriteTest        = false;   // 純寫入測試 (寫回原始內容，語意不變)
    bool  enableOneShot          = false;   // 秒殺敵人 (呼叫 setCurrentHealth(0))
    bool  enableResources        = false;   // 無限資源 (金幣/寶石)
    bool  enableTenXExp          = false;   // 快速升級 (呼叫 HeroIns.addExp)
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
    int         matchCount; // 指標替換法: 找到幾個符合的指標 (1 = 正常)
    int         runtimeCount; // 執行期記憶體中找到幾個符合的指標 (才是真正在用的)
};

extern struct ModConfig g_ModConfig;

extern HookDiag  g_HookDiag[MAX_HOOK_DIAG];
extern int       g_HookDiagCount;
extern char      g_BaseImage[512];
extern uintptr_t g_BaseAddr;

// 由 MenuLoad 呼叫 (UnityFramework 載入後)
void InitializeHooks();

// 免費購物/資源不減：由選單即時切換 (改資料段的 methodPointer，不碰程式碼頁)
void ApplyFreeShop(bool on);

// 秒殺敵人：真正的 inline hook (改寫程式碼開頭 + trampoline)
void ApplyDamageHook(bool on);

// 寫入測試：把程式碼頁原始內容原封不動寫回去 (語意不變)，用來確認寫入機制是否安全
void ApplyWriteTest(bool on);

#endif // BASIC_HACKS_H
