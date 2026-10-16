#include "Cheats.h"
#include "Il2CppRuntime.h"
#include "BasicHacks.h"

#include <string.h>
#include <stdio.h>
#include <mach/mach.h>
#include <mach/vm_map.h>

// ===== 由 dump.cs 確認過的欄位偏移 =====
#define OFF_HU_HEALTHOBJ   0x38    // HealthUnitIns.healthObj  (UnitAttrObject*)
#define OFF_HU_ATTACKOBJ   0x48    // HealthUnitIns.attackObj  (UnitPropertyObject*)
#define OFF_HU_ORIGINMAX   0x40    // HealthUnitIns.originMaxHealth (double)
#define OFF_HERO_INVINCIB  0x128   // HeroIns.invinciblePowerupTime (float)
#define OFF_HERO_LEVEL     0x134   // HeroIns.level (int)
#define OFF_HERO_EXP       0x138   // HeroIns.exp (int)
#define OFF_UA_CURR        0x10    // UnitAttrObject.curr    (double) ← 目前血量
#define OFF_UA_BASEMAX     0x18    // UnitAttrObject.baseMax (double)

bool      g_Ch_ApiOk = false;
char      g_Ch_ApiErr[192] = { 0 };
char      g_Ch_Log[256] = { 0 };
uintptr_t g_Ch_Class_HeroIns = 0;
uintptr_t g_Ch_Class_FoeIns = 0;
uintptr_t g_Ch_Class_UnitAttr = 0;
uintptr_t g_Ch_Class_ResourceData = 0;
int       g_Ch_HeroCount = 0;
int       g_Ch_FoeCount = 0;
int       g_Ch_ResCount = 0;
uintptr_t g_Ch_HeroObj = 0;
double    g_Ch_HeroHp = 0;
double    g_Ch_HeroMaxHp = 0;
int       g_Ch_SetHpOk = 0;
int       g_Ch_InitTries = 0;

// 呼叫遊戲方法用：HealthUnitIns.setCurrentHealth(double newValue, bool showAni)
typedef void (*fn_setCurrentHealth)(void* self, double newValue, bool showAni);
static fn_setCurrentHealth g_SetCurrentHealth = NULL;

static uintptr_t g_HeroObjs[8];
static uintptr_t g_FoeObjs[32];
static uintptr_t g_ResObjs[64];

// ---- 資源 / 等級 ----
int    g_Ch_ResOk = 0;
char   g_Ch_ResLog[192] = { 0 };
double g_Ch_Gold = 0;
double g_Ch_Gem = 0;
int    g_Ch_Level = 0;
int    g_Ch_Exp = 0;

// 用遊戲自己的 getter 讀值
double g_Ch_HpGet = 0;
double g_Ch_MaxGet = 0;
double g_Ch_GoldGet = 0;
double g_Ch_GoldTot = 0;
double g_Ch_GoldShow = 0;
char   g_Ch_Cand[384] = { 0 };

typedef double (*fn_getD)(void* self);
typedef int    (*fn_getI)(void* self);

static fn_getD g_GetCurrentHealth = NULL;
static fn_getD g_GetMaxHealth = NULL;
static fn_getI g_GetLevel = NULL;
static fn_getI g_GetExp = NULL;
static fn_getD g_GetCount = NULL;
static fn_getD g_GetTotalCount = NULL;
static fn_getD g_GetShowCount = NULL;

#define OFF_RD_CNTOBJ  0x40    // ResourceData.cntObject (NumberObject*)
#define OFF_NO_DOUBLE  0x10    // NumberObject.doubleValue (double)

typedef void  (*fn_reloadCount)(void* self, double count, double addCount);
typedef void  (*fn_addExp)(void* self);
typedef void* (*fn_resourceData)(void* self, int id);
typedef void* (*fn_getMainData)(void* self);

static fn_reloadCount  g_ReloadCount = NULL;
static fn_addExp       g_AddExp = NULL;
static fn_resourceData g_ResourceDataFn = NULL;
static void*           g_EduNodeInstance = NULL;
static void*           g_EduData = NULL;

static inline void   WriteD(uintptr_t a, double v) { *(volatile double*)a = v; }
static inline void   WriteF(uintptr_t a, float v)  { *(volatile float*)a  = v; }
static inline double ReadD(uintptr_t a)            { return *(volatile double*)a; }

int g_Ch_Armed = 0;

// 這個位址是否真的可以安全讀取 len bytes（避免亂解參考造成 SIGSEGV）
static bool IsReadable(uintptr_t addr, size_t len) {
    vm_address_t region = (vm_address_t)addr;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    if (vm_region_64(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64,
                     (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS) return false;
    if (!(info.protection & VM_PROT_READ)) return false;
    if (addr < (uintptr_t)region) return false;
    if (addr + len > (uintptr_t)region + (uintptr_t)size) return false;
    return true;
}

// 候選物件是否合理：每個要讀的位址都先驗證過再讀
static bool PlausibleUnit(uintptr_t obj) {
    if (obj < 0x10000000 || (obj & 7)) return false;
    if (!IsReadable(obj, 0x140)) return false;

    uintptr_t hp = *(volatile uintptr_t*)(obj + OFF_HU_HEALTHOBJ);
    if (hp < 0x10000000 || (hp & 7)) return false;
    if (!IsReadable(hp, 0x40)) return false;

    double curr = ReadD(hp + OFF_UA_CURR);
    if (!(curr >= 0.0 && curr < 1e30)) return false;
    return true;
}

static int CollectUnits(uintptr_t klass, uintptr_t* out, int maxOut, int maxScan) {
    if (!klass) return 0;
    uintptr_t tmp[128];
    if (maxScan > 128) maxScan = 128;
    int n = Il2CppFindInstances(klass, tmp, maxScan);
    int k = 0;
    for (int i = 0; i < n && k < maxOut; i++) {
        if (!PlausibleUnit(tmp[i])) continue;
        out[k++] = tmp[i];
    }
    return k;
}

// 回傳 true = 已成功接上
static bool Cheats_Init() {
    if (!Il2CppInit()) {
        g_Ch_ApiOk = false;
        strncpy(g_Ch_ApiErr, g_Il2CppErr, sizeof(g_Ch_ApiErr) - 1);
        return false;
    }
    g_Ch_ApiOk = true;

    g_Ch_Class_HeroIns      = (uintptr_t)Il2CppFindClass("", "HeroIns");
    g_Ch_Class_FoeIns       = (uintptr_t)Il2CppFindClass("", "FoeIns");
    g_Ch_Class_UnitAttr     = (uintptr_t)Il2CppFindClass("", "UnitAttrObject");
    g_Ch_Class_ResourceData = (uintptr_t)Il2CppFindClass("", "ResourceData");

    g_Ch_HeroCount = CollectUnits(g_Ch_Class_HeroIns, g_HeroObjs, 8, 64);
    g_Ch_FoeCount  = CollectUnits(g_Ch_Class_FoeIns,  g_FoeObjs,  32, 128);
    {
        g_Ch_ResCount = g_Ch_Class_ResourceData
                        ? Il2CppFindInstances(g_Ch_Class_ResourceData, g_ResObjs, 64) : 0;
    }

    if (g_Ch_HeroCount > 0) {
        g_Ch_HeroObj = g_HeroObjs[0];
        uintptr_t hp = *(volatile uintptr_t*)(g_Ch_HeroObj + OFF_HU_HEALTHOBJ);
        g_Ch_HeroHp    = ReadD(hp + OFF_UA_CURR);
        g_Ch_HeroMaxHp = ReadD(hp + OFF_UA_BASEMAX);
    }

    // 解析 setCurrentHealth（呼叫遊戲方法用）
    void* huClass = Il2CppFindClass("", "HealthUnitIns");
    g_SetCurrentHealth = (fn_setCurrentHealth)Il2CppMethod(huClass, "setCurrentHealth", 2);
    g_Ch_SetHpOk = g_SetCurrentHealth ? 1 : 0;

    // ---- 資源鏈：EducationNode.Instance → get_mainData() → EducationData → resourceData(id) ----
    {
        void* eduNodeClass = Il2CppFindClass("", "EducationNode");
        void* eduDataClass = Il2CppFindClass("", "EducationData");
        void* rdClass      = Il2CppFindClass("", "ResourceData");

        g_ReloadCount = rdClass ? (fn_reloadCount)Il2CppMethod(rdClass, "reloadCount", 2) : NULL;

        fn_getMainData getMain = eduNodeClass
            ? (fn_getMainData)Il2CppMethod(eduNodeClass, "get_mainData", 0) : NULL;
        g_EduNodeInstance = eduNodeClass ? Il2CppStaticFieldPtr(eduNodeClass, "Instance") : NULL;
        if (g_EduNodeInstance && getMain) g_EduData = getMain(g_EduNodeInstance);

        g_ResourceDataFn = eduDataClass
            ? (fn_resourceData)Il2CppMethod(eduDataClass, "resourceData", 1) : NULL;

        g_Ch_ResOk = (g_ReloadCount && g_EduData && g_ResourceDataFn) ? 1 : 0;

        snprintf(g_Ch_ResLog, sizeof(g_Ch_ResLog),
                 "node cls=%d inst=%d eduData=%d reload=%d resFn=%d",
                 eduNodeClass ? 1 : 0, g_EduNodeInstance ? 1 : 0, g_EduData ? 1 : 0,
                 g_ReloadCount ? 1 : 0, g_ResourceDataFn ? 1 : 0);
    }

    // HeroIns.addExp() → 升級
    void* heroCls = Il2CppFindClass("", "HeroIns");
    void* rdCls   = Il2CppFindClass("", "ResourceData");
    g_AddExp = (fn_addExp)Il2CppMethod(heroCls, "addExp", 0);

    // 全部改用「遊戲自己的 getter」讀值（避免欄位語意誤判）
    g_GetCurrentHealth = (fn_getD)Il2CppMethod(huClass, "get_currentHealth", 0);
    g_GetMaxHealth     = (fn_getD)Il2CppMethod(huClass, "get_maxHealth", 0);
    g_GetLevel         = (fn_getI)Il2CppMethod(heroCls, "get_level", 0);
    g_GetExp           = (fn_getI)Il2CppMethod(heroCls, "get_exp", 0);
    g_GetCount         = rdCls ? (fn_getD)Il2CppMethod(rdCls, "get_count", 0) : NULL;
    g_GetTotalCount    = rdCls ? (fn_getD)Il2CppMethod(rdCls, "get_totalCount", 0) : NULL;
    g_GetShowCount     = rdCls ? (fn_getD)Il2CppMethod(rdCls, "get_showCount", 0) : NULL;

    snprintf(g_Ch_Log, sizeof(g_Ch_Log),
             "asm=%d hero=%d foe=%d setHp=%d res=%d addExp=%d",
             g_Il2CppAsmCount, g_Ch_HeroCount, g_Ch_FoeCount, g_Ch_SetHpOk,
             g_Ch_ResOk, g_AddExp ? 1 : 0);
    return true;
}

static int g_Tick = 0;

// 由選單按鈕觸發：允許開始動作（在此之前完全不碰 il2cpp）
void Cheats_Arm() {
    g_Ch_Armed = 1;
}

void Cheats_Tick() {
    // 使用者還沒按下「接上 il2cpp」→ 啟動時完全不做事（零風險）
    if (!g_Ch_Armed) return;

    if (!g_Ch_ApiOk) {
        if (g_Ch_InitTries >= 60) return;    // 最多試 60 次，失敗就停，由使用者再按一次
        g_Ch_InitTries++;
        Cheats_Init();
        return;
    }

    g_Tick++;

    // 敵人會一直生：只有在開啟「秒殺」時才定期重掃，且頻率放低（重掃很貴）
    if (g_ModConfig.enableOneShot && (g_Tick % 300) == 0) {
        g_Ch_FoeCount = CollectUnits(g_Ch_Class_FoeIns, g_FoeObjs, 32, 128);
        if (g_Ch_HeroCount == 0)
            g_Ch_HeroCount = CollectUnits(g_Ch_Class_HeroIns, g_HeroObjs, 8, 64);
    }
    if (g_Ch_HeroCount > 0) g_Ch_HeroObj = g_HeroObjs[0];

    // ---- 顯示值：全部用遊戲自己的 getter 讀（不會錯位）----
    if (g_Ch_HeroObj) {
        if (g_GetCurrentHealth) g_Ch_HpGet  = g_GetCurrentHealth((void*)g_Ch_HeroObj);
        if (g_GetMaxHealth)     g_Ch_MaxGet = g_GetMaxHealth((void*)g_Ch_HeroObj);
        if (g_GetLevel)         g_Ch_Level  = g_GetLevel((void*)g_Ch_HeroObj);
        if (g_GetExp)           g_Ch_Exp    = g_GetExp((void*)g_Ch_HeroObj);
    }

    // 列出所有 HeroIns 候選（遊戲有盟友/門派，可能有多個 HeroIns）
    if ((g_Tick % 30) == 0 && g_Ch_HeroCount > 0) {
        char*  p    = g_Ch_Cand;
        size_t left = sizeof(g_Ch_Cand);
        int    n    = 0;
        for (int i = 0; i < g_Ch_HeroCount && i < 4; i++) {
            uintptr_t o  = g_HeroObjs[i];
            int       lv = g_GetLevel ? g_GetLevel((void*)o) : -1;
            double    hp = g_GetCurrentHealth ? g_GetCurrentHealth((void*)o) : -1.0;
            int w = snprintf(p, left, "#%d 0x%llX L=%d HP=%.0f\n",
                             i, (unsigned long long)o, lv, hp);
            if (w <= 0 || (size_t)w >= left) break;
            p += w; left -= (size_t)w; n++;
        }
        if (n == 0) snprintf(g_Ch_Cand, sizeof(g_Ch_Cand), "(無)");
    }

    // ---- 無敵：血量鎖在最大值 + 無敵時間拉高 ----
    if (g_ModConfig.enableGodMode && g_Ch_HeroCount > 0) {
        for (int i = 0; i < g_Ch_HeroCount; i++) {
            uintptr_t obj = g_HeroObjs[i];
            uintptr_t hp  = *(volatile uintptr_t*)(obj + OFF_HU_HEALTHOBJ);
            if (hp < 0x10000000) continue;

            double baseMax = ReadD(hp + OFF_UA_BASEMAX);
            double target  = (baseMax > 0.0 && baseMax < 1e30) ? baseMax : 1e9;
            WriteD(hp + OFF_UA_CURR, target);
            WriteF(obj + OFF_HERO_INVINCIB, 9999.0f);
        }
        if (g_Ch_HeroObj) {
            uintptr_t hp = *(volatile uintptr_t*)(g_Ch_HeroObj + OFF_HU_HEALTHOBJ);
            g_Ch_HeroHp = ReadD(hp + OFF_UA_CURR);
        }
    }

    // ---- 秒殺：呼叫遊戲的 setCurrentHealth(0) 讓敵人正常死亡（事件會照常觸發）----
    if (g_ModConfig.enableOneShot && g_Ch_FoeCount > 0) {
        for (int i = 0; i < g_Ch_FoeCount; i++) {
            void* obj = (void*)g_FoeObjs[i];
            if (g_SetCurrentHealth) {
                g_SetCurrentHealth(obj, 0.0, true);
            } else {
                uintptr_t hp = *(volatile uintptr_t*)(g_FoeObjs[i] + OFF_HU_HEALTHOBJ);
                if (hp >= 0x10000000) WriteD(hp + OFF_UA_CURR, 0.0);
            }
        }
    }

    // ---- 無限資源：呼叫 ResourceData.reloadCount 設定金幣/寶石 ----
    if (g_Ch_ResOk) {
        void* gold = g_ResourceDataFn(g_EduData, 1);   // Resource.Gold = 1
        void* gem  = g_ResourceDataFn(g_EduData, 2);   // Resource.Gem  = 2

        if (g_ModConfig.enableResources && (g_Tick % 60) == 0) {
            if (gold) g_ReloadCount(gold, 1e8, 0.0);
            if (gem)  g_ReloadCount(gem,  1e8, 0.0);
        }

        // 用遊戲的 getter 讀（先前直接讀 NumberObject 欄位，語意可能不對）
        if (gold) {
            g_Ch_GoldGet  = g_GetCount      ? g_GetCount(gold)      : 0;
            g_Ch_GoldTot  = g_GetTotalCount ? g_GetTotalCount(gold) : 0;
            g_Ch_GoldShow = g_GetShowCount  ? g_GetShowCount(gold)  : 0;
            g_Ch_Gold     = g_Ch_GoldGet;
        }
        if (gem) {
            g_Ch_Gem = g_GetCount ? g_GetCount(gem) : 0;
        }
    }

    // ---- 快速升級：呼叫 HeroIns.addExp() ----
    if (g_ModConfig.enableTenXExp && g_Ch_HeroCount > 0 && g_AddExp && (g_Tick % 3) == 0) {
        for (int i = 0; i < g_Ch_HeroCount; i++) {
            int lv = *(volatile int*)(g_HeroObjs[i] + OFF_HERO_LEVEL);
            if (lv > 0 && lv < 99999) {
                for (int k = 0; k < 5; k++) g_AddExp((void*)g_HeroObjs[i]);
            }
        }
        if (g_Ch_HeroObj) {
            g_Ch_Level = *(volatile int*)(g_Ch_HeroObj + OFF_HERO_LEVEL);
            g_Ch_Exp   = *(volatile int*)(g_Ch_HeroObj + OFF_HERO_EXP);
        }
    }
}
