-- ui/screens/youth.lua
-- 青训学院页面：青训球员列表、候选招募、传奇抽卡、自建球员、提拔/释放

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local Nationality = require("scripts/domain/nationality")
local YouthManager = require("scripts/systems/youth_manager")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local LegendImageRegistry = require("scripts/data/legend_image_registry")
local SaveManager = require("scripts/persistence/save_manager")
local SaleListingPriceSheet = require("scripts/ui/components/sale_listing_price_sheet")

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local RecruitTab = require("scripts/ui/screens/youth/recruit_tab")
local SquadTab = require("scripts/ui/screens/youth/squad_tab")
local CustomTab = require("scripts/ui/screens/youth/custom_tab")
local LegendTab = require("scripts/ui/screens/youth/legend_tab")
local LegendGachaCloud = require("scripts/persistence/legend_gacha_cloud")


local Youth = {}
local refreshLegendTab

local function showLegendCloudSyncingToast()
    UI.Toast.Show({ message = "传奇云存档同步中，请稍候", variant = "info" })
end

local function showLegendCloudConflictToast()
    UI.Toast.Show({ message = "传奇云存档冲突待处理，请先同步云端", variant = "warning" })
end

local function legendCloudMutateBlocked()
    return not YouthManager.canMutateLegendGacha()
end

local function showLegendAccountAttachDialog(gameState)
    local attach = YouthManager.getLegendGachaPendingAccountAttach()
    if not attach then return end
    local pulls = attach.pulls or 0
    local legendCount = attach.legendCount or 0
    ConfirmDialog.show({
        title = "检测到账号级传奇云存档",
        message = string.format(
            "当前账号云端已有传奇抽卡账本（剩余 %d 次抽取，%d 条传奇记录）。\n\n同步后将以云端抽卡次数、已抽传奇名单、补偿领取状态和标签池选择覆盖当前存档的本地镜像；当前存档里已经存在的球员实体不会被删除。\n\n是否同步到当前存档？",
            pulls, legendCount),
        confirmText = "同步云端",
        cancelText = "稍后",
        confirmColor = Theme.COLORS.PRIMARY,
        onConfirm = function()
            local ok, err = YouthManager.acceptLegendGachaAccountLedger(gameState)
            if ok then
                SaveManager.save(gameState, "auto")
                UI.Toast.Show({ message = "已同步账号传奇云存档", variant = "success" })
                refreshLegendTab()
            else
                UI.Toast.Show({ message = "同步失败: " .. tostring(err), variant = "error" })
            end
        end,
    })
end

local function showLegendConflictDialog(gameState)
    local conflict = YouthManager.getLegendGachaPendingConflict()
    if not conflict then return end
    ConfirmDialog.show({
        title = "传奇云存档冲突",
        message = string.format(
            "当前存档的传奇抽卡进度与账号云端不一致（本地约 %d 次抽取，云端约 %d 次抽取）。\n\n选择「使用云端」后，将以云端账本覆盖当前存档的本地镜像；球员实体不会被删除。",
            conflict.localPulls or 0, conflict.remotePulls or 0),
        confirmText = "使用云端",
        cancelText = "稍后处理",
        confirmColor = Theme.COLORS.DANGER,
        onConfirm = function()
            local ok, err = YouthManager.resolveLegendGachaConflictUseCloud(gameState)
            if ok then
                SaveManager.save(gameState, "auto")
                UI.Toast.Show({ message = "已使用云端传奇账本", variant = "success" })
                refreshLegendTab()
            else
                UI.Toast.Show({ message = "处理失败: " .. tostring(err), variant = "error" })
            end
        end,
    })
end

local _legendCloudPrompted = false

local function maybePromptLegendCloudOnce(gameState)
    if YouthManager.getLegendGachaPendingConflict() then
        showLegendConflictDialog(gameState)
        return
    end
    if YouthManager.getLegendGachaPendingAccountAttach() then
        showLegendAccountAttachDialog(gameState)
        return
    end
    if _legendCloudPrompted then return end
    if not LegendGachaCloud.isEnabled() then
        YouthManager.probeLegendGachaAccountLedger({
            ok = function()
                if YouthManager.getLegendGachaPendingAccountAttach() then
                    _legendCloudPrompted = true
                    showLegendAccountAttachDialog(gameState)
                end
            end,
        })
    end
end

local function buildLegendCloudSyncBanner(gameState)
    if YouthManager.getLegendGachaPendingConflict() then
        return UI.Panel {
            width = "100%",
            padding = 8,
            marginBottom = 8,
            backgroundColor = {70, 35, 35, 255},
            borderRadius = 8,
            borderWidth = 1,
            borderColor = Theme.COLORS.DANGER,
            onClick = function()
                showLegendConflictDialog(gameState)
            end,
            children = {
                UI.Label {
                    text = "传奇云存档冲突，点击处理（使用云端覆盖本地镜像）",
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_SECONDARY,
                },
            },
        }
    end
    if YouthManager.getLegendGachaPendingAccountAttach() then
        return UI.Panel {
            width = "100%",
            padding = 8,
            marginBottom = 8,
            backgroundColor = {35, 50, 70, 255},
            borderRadius = 8,
            borderWidth = 1,
            borderColor = Theme.COLORS.PRIMARY,
            onClick = function()
                showLegendAccountAttachDialog(gameState)
            end,
            children = {
                UI.Label {
                    text = "检测到账号传奇云存档，点击同步到当前存档",
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_SECONDARY,
                },
            },
        }
    end
    if not legendCloudMutateBlocked() then return nil end
    return UI.Panel {
        width = "100%",
        padding = 8,
        marginBottom = 8,
        backgroundColor = {40, 45, 70, 255},
        borderRadius = 8,
        borderWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label {
                text = "云存档同步中，传奇抽卡操作暂不可用",
                fontSize = 11,
                color = Theme.COLORS.TEXT_SECONDARY,
            },
        },
    }
end

refreshLegendTab = function()
    Router.replaceWith("youth", { tab = "legend", _softRefresh = true })
end

--- 子目录标签（在路由切换间保留）：recruit=招募 / legend=传奇 / custom=自建 / squad=青训球员
local _activeTab = "recruit"

--- 自建球员可选位置
local CUSTOM_POSITION_OPTIONS = {
    "GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LW", "RW", "ST",
}
local _customCreatePos = "ST"
local _customCreateNat = nil
local _customNationOptions = nil

local function getCustomNationOptions()
    if not _customNationOptions then
        _customNationOptions = ScoutManager.getNationOptionList()
    end
    return _customNationOptions
end

local function resolveCustomNationIndex(natCode)
    local options = getCustomNationOptions()
    if #options == 0 then return 1 end
    for i, opt in ipairs(options) do
        if Nationality.matches(opt.code, natCode) then
            return i
        end
    end
    return 1
end

local function cycleCustomNation(delta)
    local options = getCustomNationOptions()
    if #options == 0 then return end
    local idx = resolveCustomNationIndex(_customCreateNat)
    idx = ((idx - 1 + delta) % #options) + 1
    _customCreateNat = options[idx].code
end

--- 叙事标签池 UI 配置
local LEGEND_POOL_UI = {
    prince = { icon = "👑", short = "王子旗帜" },
    nation = { icon = "🏆", short = "国家英雄" },
    club = { icon = "🏟", short = "俱乐部" },
    golden_era = { icon = "🏅", short = "冠军核心" },
    wanderer = { icon = "🌍", short = "流浪大师" },
    myth = { icon = "✨", short = "神话远方" },
}

------------------------------------------------------
-- 潜力星级显示（1-5星，球探能力影响准确度）
------------------------------------------------------
--- 将潜力转换为星级显示（基于球探能力的准确度）
--- @param potential number 球员潜力值
--- @param scoutAccuracy number 球探准确度 (0.0-1.0)
--- @return number stars 星数 (1-5)
--- @return string display 星级显示字符串
local function getPotentialStars(potential, scoutAccuracy)
    -- 若已解锁潜力透视，直接显示精确值
    local gs = _G.gameState
    if gs and gs.potentialRevealed then
        local paRating = PotentialSystem.rawToRating(potential)
        local text = string.format("%.1f", paRating)
        return 5, text
    end

    -- 基于 paRating (1.0-10.0) 映射到 1-5 星
    local paRating = PotentialSystem.rawToRating(potential)
    -- paRating 1.0-10.0 → 星数 1-5
    local exactStars = (paRating - 1.0) / 9.0 * 4.0 + 1.0  -- 1.0→1星, 10.0→5星

    -- 球探能力引入误差：准确度越低，随机偏移越大
    local accuracy = scoutAccuracy or 0.6
    local maxError = (1.0 - accuracy) * 1.5  -- 准确度0.6 → 最大偏差0.6星，准确度1.0 → 0偏差
    -- 使用确定性偏移（基于潜力值本身作为种子，保证同一球员显示稳定）
    local seed = potential * 7 + 13
    local pseudoRandom = (math.sin(seed) * 10000) % 1.0  -- 0~1 伪随机
    local errorOffset = (pseudoRandom - 0.5) * 2 * maxError  -- -maxError ~ +maxError

    local displayStars = math.floor(exactStars + errorOffset + 0.5)
    displayStars = math.max(1, math.min(5, displayStars))

    -- 生成星号文本
    local starText = string.rep("★", displayStars) .. string.rep("☆", 5 - displayStars)
    return displayStars, starText
end

--- 获取当前球队的球探准确度
local function getTeamScoutAccuracy(gameState)
    return ScoutManager.getAccuracy(gameState)
end

------------------------------------------------------
-- 主页面
------------------------------------------------------
function Youth.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel{} end

    local youthSquad = YouthManager.getYouthSquad(gameState)
    local regularYouthSquad = YouthManager.getRegularYouthSquad(gameState)
    local customYouthSquad = YouthManager.getCustomYouthSquad(gameState)
    local candidates = YouthManager.getCandidates(gameState)
    local playerTeam = gameState:getPlayerTeam()
    local maxYouthSquad = playerTeam
        and YouthManager.getMaxYouthSquad(gameState, playerTeam)
        or YouthManager.MAX_YOUTH_SQUAD

    -- 支持通过路由参数指定初始子目录
    if params and params.tab then
        _activeTab = params.tab
    end

    local orphanCount = #YouthManager.getOrphanedPulledLegends(gameState)

    -- 子目录内容：招募 / 传奇 / 自建 / 青训球员
    local tabContent
    if _activeTab == "squad" then
        tabContent = {
            Youth._buildSquadSection(regularYouthSquad, gameState),
        }
    elseif _activeTab == "legend" then
        Youth._maybePromptLegendCloud(gameState)
        tabContent = {
            Youth._buildOrphanReclaimBanner(gameState),
            Youth._buildLegendGachaSection(gameState),
        }
    elseif _activeTab == "custom" then
        tabContent = {
            Youth._buildCustomSection(customYouthSquad, gameState),
        }
    else
        tabContent = {
            Youth._buildCandidatesSection(candidates, gameState),
        }
    end

    local children = {
        -- 标题栏
        Theme.TopBar {
            children = {
                UI.Button {
                    text = "返回",
                    width = 50, height = 36,
                    backgroundColor = Theme.COLORS.TRANSPARENT,
                    fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function() Router.back() end,
                },
                UI.Label {
                    text = "青训学院",
                    fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                    fontWeight = "bold", flexGrow = 1, textAlign = "center",
                },
                UI.Label {
                    text = string.format("%d/%d人", #youthSquad, maxYouthSquad),
                    fontSize = 12, color = Theme.COLORS.TEXT_MUTED, minWidth = 60, textAlign = "right",
                },
            }
        },
        Theme.SquadSubNav("youth"),
        playerTeam and UI.Panel {
            width = "100%",
            paddingLeft = 12, paddingRight = 12,
            paddingTop = 6, paddingBottom = 4,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label {
                    text = StaffManager.getStaffChipText(gameState, playerTeam.id, "youth"),
                    fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY,
                },
            },
        } or UI.Panel { width = 0, height = 0 },
        -- 三级子目录：招募 / 传奇 / 自建 / 青训球员
        Youth._buildTabBar(#candidates, orphanCount, #customYouthSquad, #regularYouthSquad),
        UI.Panel {
            width = "100%", flexGrow = 1,
            padding = 12,
            overflow = "scroll",
            children = (function()
                -- 青训概览卡片始终置顶，下方按子目录切换内容
                local items = { Youth._buildSummaryCard(youthSquad, maxYouthSquad) }
                for _, node in ipairs(tabContent) do
                    table.insert(items, node)
                end
                return items
            end)(),
        },
        Theme.MainNav("squad"),
    }

    return UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = Theme.COLORS.BG_MAIN,
        children = children,
    }
end

------------------------------------------------------
-- 三级子目录标签栏（招募 / 传奇 / 自建 / 青训球员）
------------------------------------------------------
function Youth._buildTabBar(candidateCount, orphanCount, customCount, youthCount)
    local tabs = {
        { key = "recruit", label = "招募", count = candidateCount },
        { key = "legend",  label = "传奇", count = orphanCount > 0 and orphanCount or nil },
        { key = "custom",  label = "自建", count = customCount > 0 and customCount or nil },
        { key = "squad",   label = "青训", count = youthCount },
    }

    local buttons = {}
    for _, tab in ipairs(tabs) do
        local isActive = (tab.key == _activeTab)
        local labelText = tab.label
        if tab.count and tab.count > 0 then
            labelText = labelText .. " " .. tostring(tab.count)
        end
        table.insert(buttons, UI.Button {
            text = labelText,
            height = 30,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.GOLD or Theme.COLORS.TRANSPARENT,
            borderRadius = 15,
            fontSize = 12,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_MUTED,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 6,
            onClick = function()
                if not isActive then
                    _activeTab = tab.key
                    Router.replaceWith("youth", { tab = tab.key })
                end
            end,
        })
    end

    return UI.Panel {
        width = "100%", height = 40,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        backgroundColor = Theme.COLORS.BG_CARD,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        overflow = "scroll",
        children = buttons,
    }
end

------------------------------------------------------
-- 概览卡片
------------------------------------------------------
function Youth._buildSummaryCard(youthSquad, maxYouthSquad)
    maxYouthSquad = maxYouthSquad or YouthManager.MAX_YOUTH_SQUAD
    local count = #youthSquad
    local avgOvr = 0
    local avgPot = 0
    if count > 0 then
        local totalOvr, totalPot = 0, 0
        for _, p in ipairs(youthSquad) do
            totalOvr = totalOvr + (p.overall or 0)
            totalPot = totalPot + (p.potential or 0)
        end
        avgOvr = math.floor(totalOvr / count)
        avgPot = math.floor(totalPot / count)
    end

    return Theme.Card {
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                marginBottom = 8,
                children = {
                    Theme.Title { text = "青训学院", marginBottom = 0 },
                    UI.Label {
                        text = string.format("%d / %d 名额", count, maxYouthSquad),
                        fontSize = 12,
                        color = count >= maxYouthSquad and Theme.COLORS.WARNING or Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                children = {
                    Theme.StatPill { label = "人数", value = tostring(count) },
                    Theme.StatPill { label = "平均能力", value = count > 0 and tostring(avgOvr) or "-" },
                    Theme.StatPill { label = "平均潜力", value = count > 0 and "★" .. string.format("%.1f", avgPot > 0 and ((PotentialSystem.rawToRating(avgPot) - 1.0) / 9.0 * 4.0 + 1.0) or 0) or "-",
                        valueColor = Theme.COLORS.ACCENT },
                },
            },
        }
    }
end

------------------------------------------------------
-- 批量操作
------------------------------------------------------
function Youth._signAllCandidates(candidates, gameState)
    if not candidates or #candidates == 0 then return end
    ConfirmDialog.show({
        title = "一键签入",
        message = string.format("确认签入全部 %d 名候选青训球员？", #candidates),
        confirmText = "全部签入",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            local signedCount, failCount = 0, 0
            while true do
                local current = YouthManager.getCandidates(gameState)
                if not current or #current == 0 then break end
                local ok = YouthManager.signCandidate(gameState, 1)
                if ok then
                    signedCount = signedCount + 1
                else
                    failCount = failCount + 1
                    break
                end
            end
            if signedCount > 0 then
                SaveManager.save(gameState, "auto")
                UI.Toast.Show({
                    message = string.format("已签入 %d 名青训球员", signedCount),
                    variant = failCount > 0 and "warning" or "success",
                })
            else
                UI.Toast.Show({ message = "没有可签入的候选球员", variant = "warning" })
            end
            Router.replaceWith("youth", { tab = "recruit" })
        end,
    })
end

function Youth._listAllYouthForSale(youthSquad, gameState)
    if not youthSquad or #youthSquad == 0 then return end
    local targets = {}
    for _, player in ipairs(youthSquad) do
        if player and not player.listedForSale then
            table.insert(targets, player)
        end
    end
    if #targets == 0 then
        UI.Toast.Show({ message = "青训球员已全部挂牌", variant = "info" })
        return
    end

    ConfirmDialog.show({
        title = "一键挂牌",
        message = string.format("确认将 %d 名未挂牌青训球员全部挂牌出售？", #targets),
        confirmText = "全部挂牌",
        confirmColor = Theme.COLORS.ACCENT,
        onConfirm = function()
            local okCount, failCount = 0, 0
            local lastErr = nil
            for _, player in ipairs(targets) do
                local ok, err = TransferManager.listForSale(gameState, player)
                if ok then
                    okCount = okCount + 1
                else
                    failCount = failCount + 1
                    lastErr = err
                end
            end
            if okCount > 0 then
                UI.Toast.Show({
                    message = string.format("已挂牌 %d 名青训球员", okCount),
                    variant = failCount > 0 and "warning" or "success",
                })
            end
            if failCount > 0 then
                UI.Toast.Show({ message = lastErr or "部分球员无法挂牌", variant = "error" })
            end
            Router.replaceWith("youth", { tab = "squad" })
        end,
    })
end

------------------------------------------------------
-- 候选招募区域
------------------------------------------------------
------------------------------------------------------
-- 青训球员列表
------------------------------------------------------
------------------------------------------------------
-- 自建球员广告奖励
------------------------------------------------------

------------------------------------------------------
-- 传奇球星池抽卡入口
------------------------------------------------------

--- 构建标签池选择器（解锁后可随时切换）


function Youth._buildCandidatesSection(candidates, gameState)
    return RecruitTab.build(candidates, gameState)
end

function Youth._buildSquadSection(youthSquad, gameState)
    return SquadTab.build(youthSquad, gameState)
end

function Youth._buildCustomSection(customSquad, gameState)
    return CustomTab.build(customSquad, gameState)
end


Youth._getPotentialStars = getPotentialStars
Youth._getTeamScoutAccuracy = getTeamScoutAccuracy
Youth._legendCloudMutateBlocked = legendCloudMutateBlocked
Youth._refreshLegendTab = refreshLegendTab
Youth._buildLegendCloudSyncBanner = buildLegendCloudSyncBanner
Youth._showLegendCloudSyncingToast = showLegendCloudSyncingToast
Youth._showLegendCloudConflictToast = showLegendCloudConflictToast
Youth._maybePromptLegendCloud = maybePromptLegendCloudOnce
Youth._showLegendAccountAttachDialog = showLegendAccountAttachDialog
Youth._showLegendConflictDialog = showLegendConflictDialog
Youth._getCustomCreatePos = function() return _customCreatePos end
Youth._setCustomCreatePos = function(v) _customCreatePos = v end
Youth._getCustomCreateNat = function() return _customCreateNat end
Youth._setCustomCreateNat = function(v) _customCreateNat = v end
Youth._getCustomNationOptions = getCustomNationOptions
Youth._cycleCustomNation = cycleCustomNation
Youth.CUSTOM_POSITION_OPTIONS = CUSTOM_POSITION_OPTIONS
Youth._getLegendPoolUi = function() return LEGEND_POOL_UI end


function Youth._buildCandidateCard(candidate, index, gameState)
    return RecruitTab._buildCandidateCard(candidate, index, gameState)
end

function Youth._confirmSign(candidate, index, gameState)
    return RecruitTab._confirmSign(candidate, index, gameState)
end

function Youth._buildYouthPlayerRow(player, gameState)
    return SquadTab._buildYouthPlayerRow(player, gameState)
end

function Youth._showYouthActions(player, gameState)
    return SquadTab._showYouthActions(player, gameState)
end

function Youth._confirmPromote(player, gameState)
    return SquadTab._confirmPromote(player, gameState)
end

function Youth._confirmRelease(player, gameState)
    return SquadTab._confirmRelease(player, gameState)
end

function Youth._showCreateCustomModal(gameState, defaultNat)
    return CustomTab._showCreateCustomModal(gameState, defaultNat)
end

function Youth._watchAdForCustomCreate(gameState, defaultNat)
    return CustomTab._watchAdForCustomCreate(gameState, defaultNat)
end

function Youth._watchAdForCustomPaBoost(player, gameState)
    return CustomTab._watchAdForCustomPaBoost(player, gameState)
end

function Youth._buildLegendPoolSelector(gameState)
    return LegendTab._buildLegendPoolSelector(gameState)
end

function Youth._showLegendPoolListModal(gameState, poolId)
    return LegendTab._showLegendPoolListModal(gameState, poolId)
end

function Youth._buildOrphanReclaimBanner(gameState)
    return LegendTab._buildOrphanReclaimBanner(gameState)
end

function Youth._showOrphanReclaimModal(gameState)
    return LegendTab._showOrphanReclaimModal(gameState)
end

function Youth._watchAdForUnlock(gameState)
    return LegendTab._watchAdForUnlock(gameState)
end

function Youth._showAdForPullsModal(gameState)
    return LegendTab._showAdForPullsModal(gameState)
end

function Youth._doWatchAdInModal(gameState)
    return LegendTab._doWatchAdInModal(gameState)
end

function Youth._showAdRewardPopup(gameState, newPulls)
    return LegendTab._showAdRewardPopup(gameState, newPulls)
end

function Youth._doSinglePull(gameState)
    return LegendTab._doSinglePull(gameState)
end

function Youth._doTenPull(gameState)
    return LegendTab._doTenPull(gameState)
end

function Youth._showLegendReveal(legendPlayer, isFirstPull)
    return LegendTab._showLegendReveal(legendPlayer, isFirstPull)
end

function Youth._buildLegendGachaSection(gameState)
    return LegendTab.build(gameState)
end

return Youth
