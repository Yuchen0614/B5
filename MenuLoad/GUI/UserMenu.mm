#include "UserMenu.h"
#include "../Includes.h"
#include "../TextInput.h"
#include "../../Source/BasicHacks.h"

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

        // === 核心戰鬥功能 ===
        if (ImGui::CollapsingHeader("核心戰鬥功能", ImGuiTreeNodeFlags_DefaultOpen))
        {
            // 傷害倍率
            ImGui::Text("傷害倍率 (暫時停用)");
            ImGui::SliderFloat("##DmgMultSlider", &g_ModConfig.damageMultiplier, 1.0f, 1000000.0f, "%.1fx");
            ImGui::SameLine();
            ImGui::PushItemWidth(120);
            if (ImGui::InputFloat("##DmgMultInput", &g_ModConfig.damageMultiplier, 0.1f, 100.0f, "%.1f")) {
                if (g_ModConfig.damageMultiplier < 1.0f) g_ModConfig.damageMultiplier = 1.0f;
            }
            ImGui::PopItemWidth();
            
            ImGui::SameLine();
            if (ImGui::Button("1x")) g_ModConfig.damageMultiplier = 1.0f;
            ImGui::SameLine(); if (ImGui::Button("10x")) g_ModConfig.damageMultiplier = 10.0f;
            ImGui::SameLine(); if (ImGui::Button("100x")) g_ModConfig.damageMultiplier = 100.0f;
            ImGui::SameLine(); if (ImGui::Button("1000x")) g_ModConfig.damageMultiplier = 1000.0f;
            ImGui::SameLine(); if (ImGui::Button("10000x")) g_ModConfig.damageMultiplier = 10000.0f;

            ImGui::Checkbox("秒殺敵人 (攻擊力放大, 勾選即時生效)", &g_ModConfig.enableDamageMultiplier);
            ApplyDamageMultiplier(g_ModConfig.enableDamageMultiplier);

            ImGui::Separator();

            // 無敵模式
            ImGui::Checkbox("無敵模式 (尚未實作)", &g_ModConfig.enableGodMode);

            ImGui::Separator();

            // 免費購物/資源不減：替換資料段的方法指標 (完全不碰程式碼頁)
            ImGui::Checkbox("免費購物 / 資源不減 (勾選即時生效)", &g_ModConfig.enableFreeShopping);
            ApplyFreeShop(g_ModConfig.enableFreeShopping);

            ImGui::TextDisabled("作法: 替換 methodPointer，不修改程式碼頁");
        }

        ImGui::Separator();

        // === 診斷 (確認 hook 有沒有真的掛上) ===
        if (ImGui::CollapsingHeader("診斷 (Hook 狀態)", ImGuiTreeNodeFlags_DefaultOpen))
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
                ImGui::Text("    pointer matches = %d  (需為 1 才會生效)", d.matchCount);
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
