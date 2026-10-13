#include "BasicHacks.h"
#include <substrate.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
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
    // 只要可讀即可（可寫性交給 vm_protect 處理；不硬性要求 X，
    // 避免 VM_PROT_COPY 造成的區段分割誤判）
    return (info.protection & VM_PROT_READ) != 0;
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
    // 注意: 一定要用 memcpy，不要用 vm_write()。
    // vm_write 是 Mach IPC 式呼叫，會以「頁」為單位讀出再寫回，
    // 對自己的 task 使用時可能覆蓋同頁的其他內容 → 弄壞程式碼 → 一執行就閃退。
    memcpy((void*)addr, data, len);
    RestoreRX(addr, len);
    sys_icache_invalidate((void*)addr, len);
    return true;
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

// 方法 3: 直接改寫函數開頭（不需要呼叫原函數、不需要 trampoline、
//         完全不搬移任何指令 → 最安全，不會有 PC 相對指令的問題）。
//         code 必須自帶結尾指令 (ret)。
static void DoPatch(const char* name, uint32_t rva, const void* code, size_t len) {
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

    if (!IsExecutable(addr)) return;

    d.before = *(volatile uint32_t*)addr;

    if (RawWrite(addr, code, len)) {
        d.after = *(volatile uint32_t*)addr;
        if (d.before != d.after) {
            d.installed = true;
            d.method = 3;
        }
    }
}

// 取得某位址所在頁面的保護旗標 (VM_PROT_*)
static int RegionProt(uintptr_t addr) {
    vm_address_t region = (vm_address_t)addr;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &count, &object);
    if (kr != KERN_SUCCESS) return -1;
    return (int)info.protection;
}

// ===== 只改「資料」、完全不碰「程式碼頁」 =====
// il2cpp 呼叫方法時，是從資料段的 methodPointers 陣列取出函數位址。
// 把那個「指標」換成我們自己的函數，就等於換掉整個方法，
// 而且改的是可寫入的資料頁 → 不會踩到 iOS 對可執行程式碼頁的保護。
#define MAX_PTR_PATCH 8
#define MAX_RT_SLOTS  16

struct PtrPatch {
    const char* name;
    uint32_t    rva;
    uintptr_t   target;   // base + rva (原本的函數位址)
    void*       repl;     // 要換成的函數
    uintptr_t*  origOut;  // 套用時把原始位址寫到這裡 (供「呼叫原函數」用)
    int         matches;  // 在二進位資料段找到幾個符合的指標
    uintptr_t   rtSlots[MAX_RT_SLOTS];  // 執行期記憶體中實際改掉的位置
    int         rtCount;
    bool        applied;
    int         diagIdx;
};

static PtrPatch g_PtrPatch[MAX_PTR_PATCH];
static int      g_PtrPatchCount = 0;

// 替代函數：扣資源 → 什麼都不做
extern "C" void rep_noop(void*, void*, void*, void*) { }

// 替代函數：攻擊 → 把 atkRate 放大後再呼叫原函數 (實質秒殺)
typedef void (*tp_checkPrepare)(void*, void*, double, int, int);
static tp_checkPrepare g_OrigCheckPrepare = NULL;

extern "C" void rep_checkPrepare(void* self, void* foe, double atkRate, int source, int sourceId) {
    if (!g_OrigCheckPrepare) return;
    double mult = (double)g_ModConfig.damageMultiplier;
    if (mult < 1.0) mult = 1.0;
    g_OrigCheckPrepare(self, foe, atkRate * mult, source, sourceId);
}

// 掃描 UnityFramework 區段，找出值 == target 的 8 bytes 位置
// pass 0 = 只掃資料區段 ; pass 1 = 連程式碼區段一起掃
static int FindPointerSlotsPass(uintptr_t target, uintptr_t* outSlots, int maxSlots, int pass) {
    int n = 0;

    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header* h = _dyld_get_image_header(i);
        if (!h) continue;
        if ((uintptr_t)h != g_BaseAddr) continue;      // 只處理 UnityFramework

        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct mach_header_64* h64 = (const struct mach_header_64*)h;
        const struct load_command* lc =
            (const struct load_command*)((const uint8_t*)h64 + sizeof(struct mach_header_64));

        for (uint32_t c = 0; c < h64->ncmds; c++) {
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)lc;
                bool isExec = (seg->initprot & VM_PROT_EXECUTE) != 0;
                if (seg->filesize > 0 && ((pass == 0 && !isExec) || (pass == 1 && isExec))) {
                    uintptr_t start = (uintptr_t)seg->vmaddr + (uintptr_t)slide;
                    uintptr_t end   = start + (uintptr_t)seg->filesize;
                    for (uintptr_t a = start; a + 8 <= end; a += 8) {
                        if (*(volatile uintptr_t*)a == target) {
                            if (n < maxSlots) outSlots[n] = a;
                            n++;
                        }
                    }
                }
            }
            lc = (const struct load_command*)((const uint8_t*)lc + lc->cmdsize);
        }
        break;
    }
    return n;
}

static int FindPointerSlots(uintptr_t target, uintptr_t* outSlots, int maxSlots) {
    int n = FindPointerSlotsPass(target, outSlots, maxSlots, 0);   // 先掃資料段
    if (n == 0) n = FindPointerSlotsPass(target, outSlots, maxSlots, 1);  // 找不到才掃程式碼段
    return n;
}

static int AddPtrPatch(const char* name, uint32_t rva, void* repl, uintptr_t* origOut) {
    if (g_PtrPatchCount >= MAX_PTR_PATCH) return -1;

    PtrPatch& p = g_PtrPatch[g_PtrPatchCount];
    p.name    = name;
    p.rva     = rva;
    p.target  = g_BaseAddr + rva;
    p.repl    = repl;
    p.origOut = origOut;
    p.matches = 0;
    p.rtCount = 0;
    p.applied = false;
    p.diagIdx = -1;

    if (g_HookDiagCount < MAX_HOOK_DIAG) {
        int di = g_HookDiagCount++;
        HookDiag& d = g_HookDiag[di];
        d.name = name; d.rva = rva; d.addr = p.target;
        d.before = 0; d.after = 0;
        d.installed = false; d.method = 0; d.msRet = -999;
        d.protBefore = -1; d.protAfter = -1;
        d.matchCount = 0;
        d.runtimeCount = -1;
        p.diagIdx = di;
    }

    // 啟動時只「找」，不寫入
    uintptr_t slots[16];
    p.matches = FindPointerSlots(p.target, slots, 16);
    if (p.diagIdx >= 0) g_HookDiag[p.diagIdx].matchCount = p.matches;

    g_PtrPatchCount++;
    return p.diagIdx;
}

static void RefreshPtrDiag(PtrPatch& p) {
    if (p.diagIdx < 0) return;
    HookDiag& d = g_HookDiag[p.diagIdx];
    d.installed    = p.applied;
    d.method       = p.applied ? 4 : 0;    // 4 = 指標替換
    d.matchCount   = p.matches;
    d.runtimeCount = p.rtCount;
}

// 掃描「執行期記憶體」(堆積 / 可寫入資料)，找出真正在用的指標。
// pass 0 = 只掃可寫入且不可執行 ; pass 1 = 再加可讀不可執行
static int ScanRuntime(uintptr_t target, uintptr_t* out, int maxOut, int pass) {
    int n = 0;
    vm_address_t addr = 0;
    uintptr_t budget = (uintptr_t)768 * 1024 * 1024;   // 最多掃 768MB，避免卡住 UI

    while (n < maxOut && budget > 0) {
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;

        kern_return_t kr = vm_region_64(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &count, &object);
        if (kr != KERN_SUCCESS) break;
        if (size == 0) break;

        bool exec = (info.protection & VM_PROT_EXECUTE) != 0;
        bool writ = (info.protection & VM_PROT_WRITE) != 0;
        bool rd   = (info.protection & VM_PROT_READ) != 0;
        bool use  = (!exec) && ((pass == 0) ? writ : rd);

        if (use && size >= 8) {
            budget = (budget > (uintptr_t)size) ? budget - (uintptr_t)size : 0;
            uintptr_t s = (uintptr_t)addr;
            uintptr_t e = s + (uintptr_t)size;
            for (uintptr_t a = s; a + 8 <= e; a += 8) {
                if (*(volatile uintptr_t*)a == target) {
                    if (n < maxOut) out[n] = a;
                    n++;
                    if (n >= maxOut) break;
                }
            }
        }
        addr += size;
    }
    return n;
}

static void TogglePtrPatch(PtrPatch& p, bool on) {
    if (on == p.applied) return;

    if (p.origOut) *p.origOut = p.target;   // 原函數位址就是 base + rva

    if (on) {
        // ---- 1) 執行期記憶體 (MethodInfo->methodPointer 等，真正在用的) ----
        p.rtCount = ScanRuntime(p.target, p.rtSlots, MAX_RT_SLOTS, 0);
        if (p.rtCount == 0) p.rtCount = ScanRuntime(p.target, p.rtSlots, MAX_RT_SLOTS, 1);

        uintptr_t rv = (uintptr_t)p.repl;
        for (int i = 0; i < p.rtCount && i < MAX_RT_SLOTS; i++) {
            RawWrite(p.rtSlots[i], &rv, 8);
        }

        // ---- 2) 二進位資料段的指標表 (il2cpp 初始化的來源) ----
        if (p.matches == 1) {
            uintptr_t slots[16];
            if (FindPointerSlots(p.target, slots, 16) == 1) {
                RawWrite(slots[0], &rv, 8);
            }
        }
        p.applied = true;
    } else {
        uintptr_t ov = p.target;
        for (int i = 0; i < p.rtCount && i < MAX_RT_SLOTS; i++) {
            RawWrite(p.rtSlots[i], &ov, 8);
        }
        p.rtCount = 0;

        if (p.matches == 1) {
            uintptr_t slots[16];
            if (FindPointerSlots(p.target, slots, 16) == 1) {
                RawWrite(slots[0], &ov, 8);
            }
        }
        if (p.origOut) *p.origOut = 0;
        p.applied = false;
    }
    RefreshPtrDiag(p);
}

// 秒殺敵人
void ApplyDamageMultiplier(bool on) {
    for (int i = 0; i < g_PtrPatchCount; i++) {
        PtrPatch& p = g_PtrPatch[i];
        if (!p.name || !strstr(p.name, "checkPrepare")) continue;
        TogglePtrPatch(p, on);
    }
}

// 免費購物 / 資源不減
void ApplyFreeShop(bool on) {
    for (int i = 0; i < g_PtrPatchCount; i++) {
        PtrPatch& p = g_PtrPatch[i];
        if (!p.name || strstr(p.name, "checkPrepare")) continue;
        TogglePtrPatch(p, on);
    }
}

// ===== 真正的 inline hook：改寫函數開頭 16 bytes + trampoline 呼叫原函數 =====
typedef void (*tp_checkPrepare_t)(void*, void*, double, int, int);
static tp_checkPrepare_t g_TrampCheckPrepare = NULL;

extern "C" void hook_checkPrepare(void* self, void* foe, double atkRate, int source, int sourceId) {
    if (!g_TrampCheckPrepare) return;
    double mult = (double)g_ModConfig.damageMultiplier;
    if (mult < 1.0) mult = 1.0;
    g_TrampCheckPrepare(self, foe, atkRate * mult, source, sourceId);
}

static bool g_DamageHookInstalled = false;

void ApplyDamageHook(bool on) {
    if (on == g_DamageHookInstalled) return;

    if (on) {
        uintptr_t addr = g_BaseAddr + OFFSET_CHECK_PREPARE_ATTACK;
        if (InstallInlineHook(addr, (void*)hook_checkPrepare, (void**)&g_TrampCheckPrepare)) {
            g_DamageHookInstalled = true;
        }
    } else {
        // 不還原程式碼（避免再寫一次），直接把倍率設回 1.0 即等效關閉
        g_ModConfig.damageMultiplier = 1.0f;
        g_DamageHookInstalled = false;
    }
}

// ===== 寫入測試：把程式碼頁的原始 4 bytes 原封不動寫回去 =====
// 內容完全不變 → 只有「寫入程式碼頁」這個動作被執行。
// 若這樣也會閃退，代表問題在寫入機制；若不會，代表可以正常改程式碼。
static bool g_WriteTestDone = false;

void ApplyWriteTest(bool on) {
    if (!on || g_WriteTestDone) return;

    uintptr_t addr  = g_BaseAddr + OFFSET_CHECK_PREPARE_ATTACK;
    uint32_t  orig  = *(volatile uint32_t*)addr;
    RawWrite(addr, &orig, 4);      // 寫回相同內容
    g_WriteTestDone = true;
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

    // ---- 傷害倍率：暫時停用 ----
    // 這兩個需要「呼叫原函數」→ 必須用 trampoline；
    // 上一版 trampoline 造成「載入到 100% 閃退」，先關掉以確認穩定性。
    // DoHook("checkPrepareTriggerAttackEvent", OFFSET_CHECK_PREPARE_ATTACK,
    //        (void*)new_checkPrepareTriggerAttackEvent, (void**)&orig_checkPrepareTriggerAttackEvent);
    // DoHook("checkTriggerAttackEvent", OFFSET_CHECK_TRIGGER_ATTACK,
    //        (void*)new_checkTriggerAttackEvent, (void**)&orig_checkTriggerAttackEvent);
    // 注意：changeHealthWithTarget (0x2EDD630) 屬於 HeroBaseAttack，
    //       是「英雄造成傷害」的函數，設 attackRate=0 只會讓玩家打不出傷害，
    //       不是無敵，還會抵銷傷害倍率 → 本輪先不掛，改用 HeroIns 的無敵欄位。
    // DoHook("changeHealthWithTarget", OFFSET_CHANGE_HEALTH,
    //        (void*)new_changeHealthWithTarget, (void**)&orig_changeHealthWithTarget);
    // ---- 秒殺敵人 ----
    // 改用「真正的 inline hook」：ApplyDamageHook() 會改寫函數開頭 16 bytes 並建立 trampoline。
    // (先前用 methodPointer 替換無效 —— il2cpp 對這些方法是「直接呼叫」，不經過指標表。)

    // ---- 免費購物 / 資源不減 ----
    // 把「扣資源」方法在資料段的方法指標，換成 rep_noop() → 等於整個方法變成空函數。
    // 完全不修改任何可執行的程式碼頁。
    AddPtrPatch("costResource", OFFSET_COST_RESOURCE, (void*)rep_noop, NULL);
    AddPtrPatch("costGold",     OFFSET_COST_GOLD,     (void*)rep_noop, NULL);
    AddPtrPatch("costGem",      OFFSET_COST_GEM,      (void*)rep_noop, NULL);
}
