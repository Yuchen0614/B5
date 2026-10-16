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
extern int       g_Ch_Armed;      // 使用者是否已按下「接上 il2cpp」→ 在此之前完全不動 il2cpp
extern int       g_Ch_Scanned;    // 是否已按下「掃描物件」

// 由選單按鈕呼叫（共 3 階段，逐步提高風險，方便定位問題）
void Cheats_Arm();          // 階段1：只接 il2cpp API + 解析類別（最安全）
void Cheats_ScanObjects();  // 階段2：掃描物件實例
void Cheats_BuildRes();     // 階段3：建立資源鏈（會呼叫遊戲方法）

// ---- 資源 / 等級 診斷 ----
extern int       g_Ch_ResOk;      // 資源鏈 (EducationNode→EducationData→ResourceData) 是否成功
extern char      g_Ch_ResLog[192];
extern double    g_Ch_Gold;
extern double    g_Ch_Gem;
extern int       g_Ch_Level;
extern int       g_Ch_Exp;

// 改用「遊戲自己的 getter」讀出來的值（絕對不會錯位）
extern double    g_Ch_HpGet;      // get_currentHealth()
extern double    g_Ch_MaxGet;     // get_maxHealth()
extern double    g_Ch_GoldGet;    // ResourceData.get_count()
extern double    g_Ch_GoldTot;    // ResourceData.get_totalCount()
extern double    g_Ch_GoldShow;   // ResourceData.get_showCount()
extern char      g_Ch_Cand[384];  // 所有 HeroIns 候選（位址/等級/血量）

#endif // CHEATS_H
