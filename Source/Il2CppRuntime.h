#ifndef IL2CPP_RUNTIME_H
#define IL2CPP_RUNTIME_H

#include <cstdint>

// ===== il2cpp 官方 API (用 dlsym 找，不寫死 RVA) =====
// 這是整個新方案的基礎：拿到 Il2CppClass* 之後，
// 我們就能「找物件實例」與「呼叫遊戲方法」，完全不需要 hook 程式碼。

extern bool  g_Il2CppOk;        // API 是否全部解析成功
extern char  g_Il2CppErr[192];  // 失敗原因
extern int   g_Il2CppAsmCount;  // 組件數量

bool Il2CppInit();

// 依 (命名空間, 類別名) 找 Il2CppClass*
void* Il2CppFindClass(const char* ns, const char* name);

// 類別名稱 (除錯用)
const char* Il2CppClassName(void* klass);

// 取得方法指標：MethodInfo 的第 0 個欄位就是 methodPointer
void* Il2CppMethod(void* klass, const char* name, int argc);

// 讀取靜態欄位（回傳裡面的指標值，例如 EducationNode.Instance）
void* Il2CppStaticFieldPtr(void* klass, const char* name);

// 在可寫入且不可執行的記憶體中，掃描「第 0 欄位 == klassPtr」的物件。
// il2cpp 物件的第 0 個欄位就是 Il2CppClass*，所以這就是物件實例。
int Il2CppFindInstances(uintptr_t klassPtr, uintptr_t* out, int maxOut);

#endif // IL2CPP_RUNTIME_H
