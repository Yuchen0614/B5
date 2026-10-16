#include "UserMenu.h"
#include "../Includes.h"
#include "../TextInput.h"
#include "../../Source/BasicHacks.h"
#include "../../Source/Cheats.h"

#include <thread>
#include <string>
#include <atomic>

void UserMenu::DrawMenu()
{
    ImVec2 WindowSize = ImVec2(340, 620);

    ImGui::SetNextWindowSize(WindowSize, ImGuiCond_Once);

    ImVec2 WindowPosition = ImVec2(
        (SCREEN_WIDTH - WindowSize.x) / 2,
        (SCREEN_HEIGHT - WindowSize.y) / 2
    );

    ImGui::SetNextWindowPos(WindowPosition, ImGuiCond_Once);

    ImGuiWindowFlags WindowFlags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize;
    if (!KTempVars.MoveMenu) WindowFlags |= ImGuiWindowFlags_NoMove;

    if (ImGui::Begin("IdleGongfu Mod Menu", nullptr, WindowFlags))
    {
        ImGuiWindow* CurrentWindow = ImGui::GetCurrentWindow();

        KTempVars.MenuSize   = CurrentWindow->Size;
        KTempVars.MenuOrigin = CurrentWindow->Pos;

        ImGui::Text("%s", MYSTIFY("IdleGongfu Mod Menu v1.1").c_str());
        ImGui::Separator();

        // === 功能 (純資料改寫，完全不修改程式碼) ===
        if (ImGui::CollapsingHeader("功能 (資料改寫)", ImGuiTreeNodeFlags_DefaultOpen))
        {
            ImGui::Checkbox("無敵 (血量鎖定)", &g_ModConfig.enableGodMode);
            ImGui::Checkbox("秒殺敵人", &g_ModConfig.enableOneShot);

            ImGui::Separator();

            ImGui::Text("玩家血量: %.0f / %.0f", g_Ch_HeroHp, g_Ch_HeroMaxHp);
            ImGui::Text("Hero 物件: 0x%llX  找到 %d 個",
                        (unsigned long long)g_Ch_HeroObj, g_Ch_HeroCount);
            ImGui::Text("敵人: %d 個", g_Ch_FoeCount);
        }

        ImGui::Separator();

        // === il2cpp 狀態 (診斷核心) ===
        if (ImGui::CollapsingHeader("il2cpp 狀態", ImGuiTreeNodeFlags_DefaultOpen))
        {
            ImGui::TextColored(g_Ch_ApiOk ? ImVec4(0,1,0,1) : ImVec4(1,0.4f,0,1),
                               g_Ch_ApiOk ? "API 已接上" : "API 未接上");
            ImGui::TextWrapped("err: %s", g_Ch_ApiErr);
            ImGui::Text("HeroIns=0x%llX  FoeIns=0x%llX",
                        (unsigned long long)g_Ch_Class_HeroIns,
                        (unsigned long long)g_Ch_Class_FoeIns);
            ImGui::Text("UnitAttr=0x%llX  ResourceData=0x%llX",
                        (unsigned long long)g_Ch_Class_UnitAttr,
                        (unsigned long long)g_Ch_Class_ResourceData);
            ImGui::TextWrapped("log: %s", g_Ch_Log);
            ImGui::Text("setCurrentHealth=%d  嘗試=%d", g_Ch_SetHpOk, g_Ch_InitTries);
        }

        ImGui::Separator();

        // === 診斷 (確認 hook 有沒有真的掛上) ===
        if (ImGui::CollapsingHeader("診斷 (Hook 狀態)"))
        {
            ImGui::TextWrapped("Base: %s", g_BaseImage[0] ? g_BaseImage : "(未取得)");
            ImGui::Text("Base Addr: 0x%llX", (unsigned long long)g_BaseAddr);

            if (g_HookDiagCount == 0) {
                ImGui::TextColored(ImVec4(1,0.5f,0,1), "尚未執行 InitializeHooks()");
            }
            for (int i = 0; i < g_HookDiagCount; i++) {
                HookDiag& d = g_HookDiag[i];
                ImVec4 c = d.installed ? ImVec4(0,1,0,1) : ImVec4(1,0.6f,0,1);
                ImGui::TextColored(c, "%s %s", d.installed ? "[已修改]" : "[未修改]", d.name);
                ImGui::Text("    rva=0x%X addr=0x%llX",
                            d.rva, (unsigned long long)d.addr);
                const char* mname = (d.method == 1) ? "MSHook"
                                  : (d.method == 2) ? "manual"
                                  : (d.method == 3) ? "patch"
                                  : (d.method == 4) ? "ptr" : "NONE";
                ImGui::Text("    method=%s", mname);
                ImGui::Text("    bin ptr matches = %d", d.matchCount);
                ImGui::Text("    runtime ptr replaced = %d", d.runtimeCount);
                ImGui::Text("    原始位址=0x%llX", (unsigned long long)d.addr);
            }
        }

        ImGui::Separator();

        // === 資訊 ===
        if (ImGui::CollapsingHeader("資訊"))
        {
            ImGui::Text("0x27D1124  canUseChestGemCostNow");
            ImGui::Text("0x2763E40  costResource");
            ImGui::Text("0x27BF2B8  costGold");
            ImGui::Text("0x278C304  costGem");
        }

        ImGui::Separator();

        // === 選單設定 ===
        ImGui::Checkbox("Move Menu", &KTempVars.MoveMenu);
        ImGui::SameLine();
        ImGui::Checkbox("Streamer Mode", &KTempVars.StreamerMode);
    }

    ImGui::End();
}

void UserMenu::testmenu() {
    if(KTempVars.testMenu) {
        ImGui::Begin("TestMenu", NULL, ImGuiWindowFlags_None);
            ImGui::Text("%s", MYSTIFY("Komaru!").c_str());

            static std::string TestInput;
            ImGuiInput::Text("TestInput", TestInput);
        ImGui::End();
    }
}

void UserMenu::RenderingMenu()
{
    ImGui::Begin(
        "RenderMenu",
        nullptr,
        ImGuiWindowFlags_NoTitleBar |
        ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoBackground |
        ImGuiWindowFlags_NoInputs
    );

    ImDrawList* drawList = ImGui::GetBackgroundDrawList();
    ImGui::End();
}

void UserMenu::Initialize() //init menus
{
    DrawMenu();
    testmenu(); 
    RenderingMenu();
}
