#include "UserMenu.h"
#include "../Includes.h"
#include "../TextInput.h"
#include "../../Source/BasicHacks.h"

#include <thread>
#include <string>
#include <atomic>

void UserMenu::DrawMenu()
{
    ImVec2 WindowSize = ImVec2(320, 380);

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

        ImGui::Text("%s", MYSTIFY("IdleGongfu Mod Menu v1.0").c_str());
        ImGui::Separator();

        // === 核心戰鬥功能 ===
        if (ImGui::CollapsingHeader("⚔️ 核心戰鬥功能", ImGuiTreeNodeFlags_DefaultOpen))
        {
            // 傷害倍率
            ImGui::Text("⚔️ 傷害倍率");
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

            ImGui::Checkbox("啟用傷害倍率", &g_ModConfig.enableDamageMultiplier);
            
            if (g_ModConfig.damageMultiplier > 1000.0f) {
                ImGui::TextColored(ImVec4(1.0f, 0.5f, 0.0f, 1.0f), "⚠️ 超過 1000x 可能導致遊戲不穩定");
            }
            if (g_ModConfig.damageMultiplier > 10000.0f) {
                ImGui::TextColored(ImVec4(1.0f, 0.0f, 0.0f, 1.0f), "💀 極度危險: 可能導致遊戲崩潰");
            }

            ImGui::Separator();

            // 無敵模式
            ImGui::Checkbox("🛡️ 無敵模式 / 血量鎖定", &g_ModConfig.enableGodMode);

            ImGui::Separator();

            // 免費購物/抽卡
            ImGui::Checkbox("💰 免費購物/抽卡 (武器300寶石→0, 裝備100寶石→0)", &g_ModConfig.enableFreeShopping);
        }

        ImGui::Separator();

        // === 資訊 ===
        if (ImGui::CollapsingHeader("ℹ️ 資訊"))
        {
            ImGui::Text("UnityFramework Base: 0x%llX", (unsigned long long)KTempVars.Base);
            ImGui::Text("RVA: 0x2EDD480 (傷害倍率)");
            ImGui::Text("RVA: 0x2EDD4B0 (二次檢查)");
            ImGui::Text("RVA: 0x2EDD630 (無敵/血量)");
            ImGui::Text("RVA: 0x27D1124 (免費購物/抽卡)");
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
