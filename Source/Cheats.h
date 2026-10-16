#ifndef CHEATS_H
#define CHEATS_H

#include <cstdint>

// 每一幀呼叫：第一次呼叫會嘗試接上 il2cpp 並找類別/實例，之後套用已開啟的功能
void Cheats_Tick();

// ---- 診斷 (給選單顯示，讓成功/失敗一目了然) ----
extern bool      g_Ch_ApiOk;
extern char      g_Ch_ApiErr[192];
extern char      g_Ch_Log[256];
extern uintptr_t g_Ch_Class_HeroIns;
extern uintptr_t g_Ch_Class_FoeIns;
extern uintptr_t g_Ch_Class_UnitAttr;
extern uintptr_t g_Ch_Class_ResourceData;
extern int       g_Ch_HeroCount;
extern int       g_Ch_FoeCount;
extern int       g_Ch_ResCount;
extern uintptr_t g_Ch_HeroObj;
extern double    g_Ch_HeroHp;
extern double    g_Ch_HeroMaxHp;
extern int       g_Ch_SetHpOk;   // setCurrentHealth 方法是否解析成功
extern int       g_Ch_InitTries;

// ---- 資源 / 等級 診斷 ----
extern int       g_Ch_ResOk;      // 資源鏈 (EducationNode→EducationData→ResourceData) 是否成功
extern char      g_Ch_ResLog[192];
extern double    g_Ch_Gold;
extern double    g_Ch_Gem;
extern int       g_Ch_Level;
extern int       g_Ch_Exp;

#endif // CHEATS_H
