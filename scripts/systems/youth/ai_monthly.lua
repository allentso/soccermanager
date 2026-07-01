-- systems/youth/ai_monthly.lua
-- AI 球队青训每月管理，从 youth_manager.lua 拆分。

local Constants = require("scripts/app/constants")
local Player = require("scripts/domain/player")
local Team = require("scripts/domain/team")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")
local EventBus = require("scripts/app/event_bus")
local PotentialSystem = require("scripts/systems/potential_system")
local TrainingManager = require("scripts/systems/training_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local FinanceManager = require("scripts/systems/finance_manager")
local Nationality = require("scripts/domain/nationality")
local LegendGachaCloud = require("scripts/persistence/legend_gacha_cloud")
local TextUtil = require("scripts/app/text_util")
local Helpers = require("scripts/systems/youth/youth_helpers")
local randInt = Helpers.randInt

return function(YouthManager)
    ------------------------------------------------------
    -- AI 球队青训每月管理
    ------------------------------------------------------

    --- AI 球队简化的青训管理：自动补员、提拔、释放
    ---@param gameState table
    function YouthManager._processAITeamsMonthly(gameState)
        local playerTeamId = gameState.playerTeamId

        for teamId, team in pairs(gameState.teams) do
            if teamId ~= playerTeamId then
                team._youthPlayerIds = team._youthPlayerIds or {}

                -- 0. 清除残留引用：球员已被删除或已转会离队（租借在外的保留）
                -- 防止提拔逻辑覆盖已转会球员的 teamId/合同（BUG-20260611-06）
                for i = #team._youthPlayerIds, 1, -1 do
                    local pid = team._youthPlayerIds[i]
                    local player = gameState.players[pid]
                    local stillOurs = player and
                        (player.teamId == teamId or player._loanOriginTeamId == teamId)
                    if not stillOurs then
                        table.remove(team._youthPlayerIds, i)
                    end
                end

                -- 1. 自动提拔：年满 18 岁且达到声望分档 OVR 门槛（高潜延迟）
                local toPromote = {}
                if not team:isFirstTeamFull() then
                    for i, pid in ipairs(team._youthPlayerIds) do
                        local player = gameState.players[pid]
                        if player and player.teamId == teamId then
                            if YouthManager._shouldAIPromoteYouth(gameState, team, player) then
                                table.insert(toPromote, i)
                            end
                        end
                    end
                end
                -- 从后向前移除避免索引错位
                for i = #toPromote, 1, -1 do
                    if team:isFirstTeamFull() then break end
                    local idx = toPromote[i]
                    local pid = team._youthPlayerIds[idx]
                    local player = gameState.players[pid]
                    table.remove(team._youthPlayerIds, idx)
                    if player then
                        player.isYouth = false
                        player.teamId = teamId
                        player.contractEnd = {year = gameState.date.year + 3, month = 6, day = 30}
                        player.wage = FinanceManager.estimateYouthPromoteWage(player, team, gameState)
                        if team:addPlayer(pid) then
                            -- promoted
                        end
                    end
                end

                -- 2. 自动释放：年满 19 岁仍在青训且 overall < 50 的球员
                -- （仅处理 teamId 归属本队的球员，租借在外的不动）
                local toRelease = {}
                for i, pid in ipairs(team._youthPlayerIds) do
                    local player = gameState.players[pid]
                    if player and player.teamId == teamId then
                        local age = gameState.date.year - (player.birthYear or 2000)
                        if age >= 19 and (player.overall or 0) < 50 then
                            table.insert(toRelease, i)
                        end
                    end
                end
                for i = #toRelease, 1, -1 do
                    local idx = toRelease[i]
                    local pid = team._youthPlayerIds[idx]
                    local player = gameState.players[pid]
                    table.remove(team._youthPlayerIds, idx)
                    if player then
                        player.isYouth = false
                        player.teamId = nil
                        local rawPotential = player.potential or 0
                        if rawPotential >= 70 then
                            player.isFreeAgent = true
                        else
                            gameState.players[pid] = nil
                        end
                    end
                end

                -- 3. 自动补员：每3个月生成新球员补齐至分级青训目标
                team._aiYouthRefresh = (team._aiYouthRefresh or 0) + 1
                if team._aiYouthRefresh >= YouthManager.YOUTH_REFRESH_INTERVAL then
                    team._aiYouthRefresh = 0
                    local targetYouth = YouthManager.getAIYouthTarget(gameState, teamId, team)
                    local needed = targetYouth - #team._youthPlayerIds
                    if needed > 0 then
                        local facilityYouthBonus =
                            YouthManager._getTeamYouthFacilityBonus(gameState, teamId)
                        local usedNames = YouthManager._collectYouthUsedNames(gameState, teamId)

                        for _ = 1, needed do
                            local candidate = YouthManager._generateYouthPlayer(
                                gameState, facilityYouthBonus, usedNames, team.country)
                            local playerData = {
                                firstName = candidate.firstName,
                                lastName = candidate.lastName,
                                displayName = candidate.displayName,
                                nationality = Nationality.normalize(candidate.nationality),
                                birthYear = math.floor(candidate.birthYear),
                                position = candidate.position,
                                attributes = candidate.attributes,
                                potential = candidate.potential,
                                overall = candidate.overall,
                                wage = YouthManager.YOUTH_WAGE,
                                isYouth = true,
                                teamId = teamId,
                                contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
                            }
                            local player = gameState:addPlayer(playerData)
                            player.teamId = teamId
                            player.paRating = PotentialSystem.rawToRating(player.potential)
                            player.actualPotential = PotentialSystem.generateActualPotential(
                                player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)
                            table.insert(team._youthPlayerIds, player.id)
                        end
                    end
                end
            end
        end
    end
end
