#include "Cheats.h"
#include "Il2CppRuntime.h"
#include "BasicHacks.h"

#include <string.h>
#include <stdio.h>

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

static inline void   WriteD(uintptr_t a, double v) { *(volatile double*)a = v; }
static inline void   WriteF(uintptr_t a, float v)  { *(volatile float*)a  = v; }
static inline double ReadD(uintptr_t a)            { return *(volatile double*)a; }

// 候選物件是否合理：healthObj 指標有效 + curr 是合理的 double
static bool PlausibleUnit(uintptr_t obj) {
    if (obj < 0x10000000) return false;
    uintptr_t hp = *(volatile uintptr_t*)(obj + OFF_HU_HEALTHOBJ);
    if (hp < 0x10000000) return false;
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
        uintptr_t tmp[64];
        g_Ch_ResCount = g_Ch_Class_ResourceData
                        ? Il2CppFindInstances(g_Ch_Class_ResourceData, tmp, 64) : 0;
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

    snprintf(g_Ch_Log, sizeof(g_Ch_Log),
             "asm=%d hero=%d foe=%d setHp=%d",
             g_Il2CppAsmCount, g_Ch_HeroCount, g_Ch_FoeCount, g_Ch_SetHpOk);
    return true;
}

static int g_Tick = 0;

void Cheats_Tick() {
    // 前 2000 幀持續嘗試接上（il2cpp 可能還沒初始化完）
    if (!g_Ch_ApiOk) {
        if (g_Ch_InitTries >= 2000) return;
        g_Ch_InitTries++;
        Cheats_Init();
        return;
    }

    g_Tick++;

    // 敵人會一直生，定期重新掃描
    if ((g_Tick % 30) == 0) {
        g_Ch_FoeCount = CollectUnits(g_Ch_Class_FoeIns, g_FoeObjs, 32, 128);
        if (g_Ch_HeroCount == 0)
            g_Ch_HeroCount = CollectUnits(g_Ch_Class_HeroIns, g_HeroObjs, 8, 64);
        if (g_Ch_HeroCount > 0) g_Ch_HeroObj = g_HeroObjs[0];
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
}
