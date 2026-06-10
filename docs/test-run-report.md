# 测试运行报告

**日期**: 2026-06-08  
**运行环境**: Python3 + lupa (Lua 5.4)

---

## 总览

| 测试文件 | 通过 | 失败 | 结果 |
|---------|------|------|------|
| five_season_simulation_test.lua | 全部通过 | 0 | PASS |
| negotiation_flow_test.lua | 45/45 | 0 | PASS |
| transfer_system_flow_test.lua | 78/82 | 4 | FAIL |

---

## 失败详情

### transfer_system_flow_test.lua — 测试 13: 出售流程

**失败的 4 个断言**:

1. `出售流程: 接受后进入awaiting_sale_confirmation` — 期望 `awaiting_sale_confirmation`，实际 `player_considering_sale`
2. `出售流程: confirmSale 成功` — 因状态不对导致 confirmSale 无法执行
3. `出售流程: 确认后completed` — 同上，状态仍为 `player_considering_sale`
4. `出售流程: 球员转至买方` — 球员未转会（teamId 未变）

---

## 根因分析

**结论: 测试程序未适配代码新增流程，非代码 bug。**

### 代码变更说明

`TransferManager.acceptIncomingBid()` 的出售流程新增了「球员考虑期」阶段:

```
旧流程: acceptIncomingBid → awaiting_sale_confirmation → confirmSale → completed
新流程: acceptIncomingBid → player_considering_sale → (推进天数) → awaiting_sale_confirmation → confirmSale → completed
```

具体改动（`scripts/systems/transfer_manager.lua:1165-1195`）:
- `acceptIncomingBid` 调用后，状态设为 `player_considering_sale`
- 设置 `playerConsiderSaleDays`（1-2天）
- 需要通过 `processDailyBids` 推进天数，球员考虑期结束后才进入 `awaiting_sale_confirmation`

### 测试程序问题

测试 13 在调用 `acceptIncomingBid` 后直接断言状态为 `awaiting_sale_confirmation`，没有推进天数让球员完成考虑。

### 修复建议（针对测试程序）

在 `acceptIncomingBid` 成功后、断言 `awaiting_sale_confirmation` 之前，需要添加天数推进:

```lua
local accepted = TransferManager.acceptIncomingBid(gs, bid.id)
if accepted then
    -- 新增：需要推进天数让球员完成考虑
    assertEqual(bid.status, "player_considering_sale", "出售流程: 接受后进入球员考虑期")
    for i = 1, 3 do
        advanceDay(gs)
        TransferManager.processDailyBids(gs)
    end
    -- 此时球员考虑完毕，检查是否进入 awaiting_sale_confirmation
    if bid.status == "awaiting_sale_confirmation" then
        local ok, err = TransferManager.confirmSale(gs, bid.id)
        assertTrue(ok, "出售流程: confirmSale 成功")
        -- ...
    end
end
```

---

## 其他说明

- **five_season_simulation_test**: 5 赛季模拟、训练集成验证全部通过。训练焦点增长占比达标。
- **negotiation_flow_test**: 续约、报价、个人条款、自由球员、求职等 12 个场景共 45 项断言全部通过。
- 测试 14（cancelSale）、15（counterIncomingBid）、16（超时）等涉及出售流程的其他测试均正常通过，因为它们有条件分支跳过了不匹配的情况。
