#include "Il2CppRuntime.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <string.h>
#include <stdio.h>

bool  g_Il2CppOk = false;
char  g_Il2CppErr[192] = { 0 };
int   g_Il2CppAsmCount = 0;

// ---- il2cpp API 型別 ----
typedef void*  (*fn_domain_get)(void);
typedef void** (*fn_domain_get_assemblies)(void* domain, size_t* size);
typedef void*  (*fn_assembly_get_image)(void* assembly);
typedef void*  (*fn_class_from_name)(void* image, const char* ns, const char* name);
typedef const char* (*fn_class_get_name)(void* klass);
typedef size_t (*fn_class_get_num_methods)(void* klass);
typedef void*  (*fn_class_get_method_from_name)(void* klass, const char* name, int argc);

static fn_domain_get                 p_domain_get = NULL;
static fn_domain_get_assemblies      p_domain_get_assemblies = NULL;
static fn_assembly_get_image         p_assembly_get_image = NULL;
static fn_class_from_name            p_class_from_name = NULL;
static fn_class_get_name             p_class_get_name = NULL;
static fn_class_get_method_from_name p_class_get_method_from_name = NULL;

static void* g_domain = NULL;

// 依序嘗試：主程式 → 每個已載入 image (優先 UnityFramework)
static void* ResolveSym(const char* name) {
    void* p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;

    void* mainH = dlopen(NULL, RTLD_NOW);
    if (mainH) {
        p = dlsym(mainH, name);
        if (p) return p;
    }

    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        if (!nm) continue;
        if (!strstr(nm, "UnityFramework")) continue;
        void* h = dlopen(nm, RTLD_NOW);
        if (!h) continue;
        p = dlsym(h, name);
        if (p) return p;
    }
    return NULL;
}

bool Il2CppInit() {
    if (g_Il2CppOk) return true;

    // 符號只要解析一次；但 domain 可能還沒好，所以每次都重試
    static bool symsResolved = false;
    if (!symsResolved) {
        symsResolved = true;
        p_domain_get                 = (fn_domain_get)ResolveSym("il2cpp_domain_get");
        p_domain_get_assemblies      = (fn_domain_get_assemblies)ResolveSym("il2cpp_domain_get_assemblies");
        p_assembly_get_image         = (fn_assembly_get_image)ResolveSym("il2cpp_assembly_get_image");
        p_class_from_name            = (fn_class_from_name)ResolveSym("il2cpp_class_from_name");
        p_class_get_name             = (fn_class_get_name)ResolveSym("il2cpp_class_get_name");
        p_class_get_method_from_name = (fn_class_get_method_from_name)ResolveSym("il2cpp_class_get_method_from_name");
    }

    if (!p_domain_get || !p_domain_get_assemblies || !p_assembly_get_image || !p_class_from_name) {
        snprintf(g_Il2CppErr, sizeof(g_Il2CppErr),
                 "找不到 il2cpp API: domain=%d asm=%d img=%d cls=%d",
                 p_domain_get ? 1 : 0, p_domain_get_assemblies ? 1 : 0,
                 p_assembly_get_image ? 1 : 0, p_class_from_name ? 1 : 0);
        return false;
    }

    g_domain = p_domain_get();
    if (!g_domain) {
        snprintf(g_Il2CppErr, sizeof(g_Il2CppErr), "il2cpp_domain_get() 回傳 NULL");
        return false;
    }

    size_t count = 0;
    void** asms = p_domain_get_assemblies(g_domain, &count);
    g_Il2CppAsmCount = (int)count;
    if (!asms || count == 0) {
        snprintf(g_Il2CppErr, sizeof(g_Il2CppErr), "沒有組件 (assemblies=%d)", (int)count);
        return false;
    }

    g_Il2CppOk = true;
    return true;
}

void* Il2CppFindClass(const char* ns, const char* name) {
    if (!g_Il2CppOk) return NULL;
    if (!ns) ns = "";

    size_t count = 0;
    void** asms = p_domain_get_assemblies(g_domain, &count);
    if (!asms) return NULL;

    for (size_t i = 0; i < count; i++) {
        if (!asms[i]) continue;
        void* img = p_assembly_get_image(asms[i]);
        if (!img) continue;
        void* k = p_class_from_name(img, ns, name);
        if (k) return k;
    }
    return NULL;
}

const char* Il2CppClassName(void* klass) {
    if (!klass || !p_class_get_name) return "?";
    return p_class_get_name(klass);
}

void* Il2CppMethod(void* klass, const char* name, int argc) {
    if (!klass || !p_class_get_method_from_name) return NULL;
    void* mi = p_class_get_method_from_name(klass, name, argc);
    if (!mi) return NULL;
    return *(void**)mi;      // MethodInfo 第 0 欄位 = methodPointer
}

// 掃描可寫入且不可執行的記憶體，找出「第 0 欄位 == klassPtr」的物件
int Il2CppFindInstances(uintptr_t klassPtr, uintptr_t* out, int maxOut) {
    if (!klassPtr || !out || maxOut <= 0) return 0;

    int n = 0;
    vm_address_t addr = 0;
    uintptr_t budget = (uintptr_t)1024 * 1024 * 1024;   // 上限 1GB 避免卡住

    while (n < maxOut && budget > 0) {
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;

        if (vm_region_64(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO_64,
                         (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS) break;
        if (size == 0) break;

        bool writ = (info.protection & VM_PROT_WRITE) != 0;
        bool exec = (info.protection & VM_PROT_EXECUTE) != 0;

        if (writ && !exec && size >= 8) {
            budget = (budget > (uintptr_t)size) ? budget - (uintptr_t)size : 0;
            uintptr_t s = (uintptr_t)addr;
            uintptr_t e = s + (uintptr_t)size;
            for (uintptr_t a = s; a + 8 <= e; a += 8) {
                if (*(volatile uintptr_t*)a == klassPtr) {
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
