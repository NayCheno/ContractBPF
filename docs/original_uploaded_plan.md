# ContractBPF-Ledger：面向 BPF 可编程调度与分页的有界资源效应账本

## 0. 总体定位

建议将原始 idea 收敛为：

> **ContractBPF-Ledger：面向 BPF 可编程调度与分页策略的资源效应账本系统。**

核心不是做一个覆盖 `sched_ext / paging / transport` 的大而全平台，而是解决一个更具体、更容易做强的系统安全问题：

> **多个 verifier-accepted BPF policies 同时控制调度和分页主路径时，如何约束它们对系统资源造成的动态 effect，并在资源效应失控前进行有界降级与恢复。**

优化后的核心机制是：

```text
effect token + per-scope resource ledger + bounded degrade
```

即：

1. **Effect token**：BPF policy 只有拿到某类 effect token，才能对特定资源产生特定 effect。
2. **Resource ledger**：所有调度与分页 effect 都要按 scope 记账。
3. **Bounded degrade**：当资源债务超预算时，不是直接 kill 整个 BPF 程序，而是逐级降级相关 effect。

---

## 1. 推荐题目

### 英文题目

```text
ContractBPF-Ledger: Bounded Resource-Effect Accounting for BPF-Programmable Scheduling and Paging
```

### 中文题目

```text
ContractBPF-Ledger：面向 BPF 可编程调度与分页的有界资源效应账本
```

---

## 2. 核心问题

当前 eBPF 已经进入内核主路径：

- `sched_ext` 允许用 BPF 程序定义调度器行为。
- PageFlex 等工作说明 paging policy 可以通过 eBPF 委托出去。

现有 verifier、隔离方案、runtime enforcement、safe-language kernel extension 主要解决局部安全问题，例如：

```text
memory safety
control-flow safety
helper permission
pointer safety
sandbox isolation
```

但它们没有充分解决：

> **多个合法 BPF policies 组合后是否会造成系统级资源效应冲突。**

典型例子：

```text
BPF scheduler:
  aggressively boosts latency-sensitive cgroup A
  pins tasks to selected CPUs

BPF paging policy:
  aggressively demotes pages from the same cgroup A
  assumes A is cold based on stale phase information
```

单独看：

```text
P_sched passes verifier
P_page passes verifier
helper usage is legal
return values are legal
memory accesses are legal
```

组合后：

```text
major fault storm
P99/P999 latency spike
scheduler queue delay increase
CPU utilization oscillation
memory pressure feedback loop
```

因此，ContractBPF-Ledger 关注的不是：

```text
这个 BPF 程序是否合法加载？
```

而是：

```text
这个 BPF policy 在某个 scope 内制造了多少资源 effect？
这些 effect 是否与其他 policy 形成动态冲突？
当冲突出现时，系统能否有界降级和恢复？
```

---

## 3. 一句话创新点

原始方案的创新点是：

```text
resource contract + composition check + fallback
```

进一步优化后，建议改成：

```text
effect token + per-scope resource ledger + bounded degrade
```

这比“资源契约平台”更具体，也更容易实现、评测和写出 CCF-A 级别的 strong story。

---

## 4. 系统目标

ContractBPF-Ledger 的目标是：

1. **识别 verifier-accepted BPF policies 之间的 resource-effect conflict。**
2. **用 effect token 明确 BPF policy 可以产生哪些资源 effect。**
3. **用 per-scope ledger 追踪调度与分页 effect 的动态资源债务。**
4. **在 effect boundary 进行低开销 enforcement。**
5. **在违规时进行 effect-level bounded degrade。**
6. **避免把问题退化成 helper allowlist 或 verifier extension。**

---

## 5. Threat Model 与 Problem Scope

### 5.1 Threat Model

假设：

```text
1. BPF programs 可以通过 Linux verifier。
2. BPF programs 可能由不同团队、租户、服务或自动优化系统生成。
3. 单个 BPF policy 局部看是合法的。
4. 多个 BPF policies 同时运行时，可能通过资源效应形成冲突。
5. 攻击者或错误 policy 不一定需要 memory corruption，也可以通过合法 effect 造成 DoS、latency spike 或资源失控。
```

不重点解决：

```text
1. verifier soundness bug 导致的任意 kernel memory read/write；
2. BPF JIT 漏洞；
3. 硬件侧信道；
4. 完整替代 verifier；
5. 所有 BPF hook 类型的统一安全。
```

### 5.2 Scope

强可行版本只覆盖两个子系统：

```text
sched_ext + PageFlex-style paging
```

不将 transport 作为主贡献。

理由：

1. `sched_ext` 已经足够核心，且天然支持 BPF scheduler 的启停，适合 fallback。
2. paging 与 scheduling 的组合冲突非常有说服力。
3. transport 会显著增加实现范围和叙事复杂度。
4. 双子系统已经足以证明跨子系统 resource-effect accounting 的必要性。

---

## 6. 核心抽象

### 6.1 Effect Token

每个 BPF policy 在加载时获得一组 effect token：

```text
Token = <subsystem, effect, scope, budget, fallback>
```

示例：

```text
T1 = <sched_ext, boost_task, cgroup=A, queue_delay_budget=5ms, fallback=throttle_boost>

T2 = <sched_ext, dispatch_task, cgroup=A, dispatch_fail_budget=8/epoch, fallback=disable_scx_policy>

T3 = <mm, demote_page, memcg=A, refault_budget=2.0x, fallback=revoke_demote>

T4 = <mm, reclaim_hint, region=R, pages_touched_budget=100k/s, fallback=kernel_default_reclaim>
```

关键区别：

```text
不是问：程序能不能调用 helper X？
而是问：程序能不能在 scope S 内制造 effect E，最多制造多少，违规后怎么降级？
```

---

### 6.2 Resource Ledger

为每个 scope 维护一个资源账本：

```text
Ledger(scope) = {
  sched_queue_delay_debt,
  sched_dispatch_fail_debt,
  cpu_pin_debt,
  pages_demoted_debt,
  refault_debt,
  reclaim_pressure_debt,
  cross_effect_score
}
```

scope 可以是：

```text
cgroup
memcg
CPU set
NUMA node
memory region
```

最重要的是：**scheduler effect 和 paging effect 可以记入同一个 scope ledger。**

例如：

```text
scope = service-A / cgroup-A / memcg-A
```

则：

```text
scheduler boost  -> 增加 sched_priority_pressure
page demotion    -> 增加 refault_debt
major fault      -> 反向增加 sched_queue_delay_debt
```

这样可以捕捉跨子系统反馈：

```text
调度提高优先级
  -> workload 更频繁运行
  -> hot pages 被访问
  -> paging policy 错误 demote
  -> refault storm
  -> queue delay 上升
  -> scheduler 继续 boost
  -> feedback loop
```

这比单纯 conflict matrix 更强，因为它可以处理动态状态。

---

### 6.3 Bounded Degrade

违规后不直接关闭整个 BPF 程序，而是按 effect 降级。

| 等级 | 行为 | 示例 |
|---:|---|---|
| Level 0 | 正常运行 | scheduler boost、page demotion 都允许 |
| Level 1 | throttle effect | 降低 boost 频率、限制 demotion rate |
| Level 2 | revoke specific effect | 禁用 `demote_page`，保留 read-only paging decision |
| Level 3 | fallback subsystem policy | paging 回到 kernel default reclaim |
| Level 4 | disable BPF policy | 禁用异常 sched_ext scheduler |

fallback 不再只是应急关闭，而是论文的核心机制之一：

```text
fallback = effect-level bounded degradation
```

---

## 7. 系统架构

```text
┌─────────────────────────────────────────────┐
│ User-space Contract Manager                  │
│                                             │
│  1. parse .contract section                  │
│  2. issue effect tokens                      │
│  3. check static scope conflicts             │
│  4. configure runtime ledger                 │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│ Kernel ContractBPF-Ledger Layer              │
│                                             │
│  ┌──────────────┐   ┌─────────────────────┐ │
│  │ Effect Token │   │ Per-scope Ledger     │ │
│  │ Table        │   │ cgroup/memcg/region  │ │
│  └──────┬───────┘   └──────────┬──────────┘ │
│         │                      │            │
│         ▼                      ▼            │
│  ┌──────────────┐   ┌─────────────────────┐ │
│  │ Effect Gate  │   │ Degrade Controller   │ │
│  └──────┬───────┘   └──────────┬──────────┘ │
└─────────┼──────────────────────┼────────────┘
          │                      │
          ▼                      ▼
┌──────────────────┐      ┌──────────────────┐
│ sched_ext hooks  │      │ paging decision  │
│ enqueue/dispatch │      │ demote/reclaim   │
└──────────────────┘      └──────────────────┘
```

---

## 8. Contract Manifest 设计

不要设计过于复杂的 DSL。建议使用结构化 manifest。

### 8.1 Scheduler Policy 示例

```yaml
policy: latency_sched_A
subsystem: sched_ext
scope:
  type: cgroup
  id: service-A

effects:
  - name: boost_task
    budget:
      max_boosts_per_epoch: 20000
      max_queue_delay_us: 5000
    degrade:
      level1: throttle_boost
      level2: revoke_boost
      level3: disable_scheduler

  - name: dispatch_task
    budget:
      max_dispatch_failures_per_epoch: 8
    degrade:
      level1: drain_dsq
      level2: disable_scheduler
```

### 8.2 Paging Policy 示例

```yaml
policy: phase_paging_A
subsystem: mm
scope:
  type: memcg
  id: service-A

effects:
  - name: demote_page
    budget:
      max_pages_per_epoch: 100000
      max_refault_ratio: 2.0
      max_fault_latency_us: 200
    degrade:
      level1: throttle_demote
      level2: revoke_demote
      level3: kernel_default_reclaim

  - name: reclaim_hint
    budget:
      max_hints_per_epoch: 50000
    degrade:
      level1: ignore_hint
      level2: revoke_reclaim_hint
```

### 8.3 Cross-subsystem Composition 示例

```yaml
composition:
  scope: service-A
  coupled_effects:
    - boost_task
    - demote_page
  rule:
    if:
      refault_ratio: "> 2.0"
      queue_delay_us: "> 5000"
    then:
      revoke: demote_page
      preserve: dispatch_task
```

---

## 9. Enforcement 策略

### 9.1 不改 verifier

不要把工作变成 verifier extension。推荐流程是：

```text
BPF verifier accepts program
→ Contract manager parses manifest
→ static composition check
→ kernel installs effect tokens
→ runtime ledger checks effect boundary
→ violation triggers degrade
```

这样可以明确论文定位：

```text
verifier 之后的 policy-effect enforcement
```

---

### 9.2 只在 Effect Boundary 检查

不要在每条 BPF 指令上插桩。ContractBPF-Ledger 只在 effect boundary 检查。

#### sched_ext effect boundary

```text
select_cpu
enqueue
dispatch
boost / priority adjustment
CPU pinning
```

#### paging effect boundary

```text
demote decision
reclaim hint
region classification
page-touch budget
```

设计原则：

```text
BPF 可以提出 decision；
kernel 负责验证和执行 effect。
```

---

### 9.3 Paging 侧不要直接暴露危险对象

错误设计：

```text
BPF program gets raw folio pointer
BPF program directly mutates page state
```

正确设计：

```text
BPF program receives read-only summarized state
BPF program returns policy decision
kernel validates and executes or ignores the effect
```

例如：

```text
BPF returns: keep / demote / reclaim_hint / no_op
kernel checks: pinned? locked? hot? budget exceeded?
kernel performs or ignores effect
```

这样能显著降低 MM 实现风险。

---

## 10. Static Composition Check

静态检查用于排除显然危险或配置错误的组合。

检查内容：

```text
1. contract syntax validity
2. effect token availability
3. scope overlap
4. budget sanity
5. fallback availability
6. known conflicting effect pairs
```

示例：

| Policy A | Policy B | Scope | 静态判断 |
|---|---|---|---|
| boost_task | demote_page | same cgroup/memcg | risky; require runtime ledger |
| boost_task | demote_page | different cgroup/memcg | likely allowed |
| dispatch_task | reclaim_hint | same service | allowed with budget |
| CPU pinning | aggressive demotion | same NUMA node | risky; require runtime guard |

注意：静态检查不是主贡献的全部。主贡献在于：

```text
runtime resource-effect accounting + bounded degrade
```

---

## 11. Runtime Ledger 设计

### 11.1 Ledger 更新

伪代码：

```c
int contract_effect_gate(struct bpf_prog *prog,
                         enum effect_type effect,
                         struct scope_id scope,
                         struct effect_cost cost)
{
    struct token *tok = lookup_effect_token(prog, effect, scope);
    if (!tok)
        return CONTRACT_DENY;

    struct ledger *lg = lookup_ledger(scope);

    if (ledger_would_exceed(lg, tok->budget, cost)) {
        trigger_degrade(prog, effect, scope, lg);
        return CONTRACT_DEGRADED;
    }

    ledger_charge(lg, cost);
    return CONTRACT_ALLOW;
}
```

### 11.2 调度侧指标

```text
sched_queue_delay_debt
sched_dispatch_fail_debt
cpu_pin_debt
boost_rate
starvation_window
runnable_but_idle_time
```

### 11.3 分页侧指标

```text
pages_demoted_debt
pages_reclaim_hint_debt
refault_ratio
major_fault_rate
fault_latency_us
memory_pressure_score
```

### 11.4 跨子系统指标

```text
cross_effect_score = f(
  refault_ratio,
  queue_delay_us,
  boost_rate,
  pages_demoted_per_epoch,
  memory_pressure_score
)
```

一个简单可实现版本：

```text
if refault_ratio > R and queue_delay_us > Q:
    revoke demote_page token for this scope
```

更强版本：

```text
cross_effect_score = w1 * normalized_refault_ratio
                   + w2 * normalized_queue_delay
                   + w3 * normalized_demote_rate
                   + w4 * normalized_boost_rate
```

---

## 12. Degrade Controller

### 12.1 Degrade 原则

```text
1. 优先 revoke specific effect，而不是 kill whole program。
2. 优先降级 paging demotion，而不是禁用 scheduler。
3. 保留 read-only observability capability。
4. 让 fallback action 与具体 subsystem invariant 绑定。
5. 每次 degrade 都记录 audit event。
```

### 12.2 Scheduler Degrade

| 触发条件 | Level 1 | Level 2 | Level 3 |
|---|---|---|---|
| queue delay 超预算 | throttle boost | revoke boost | disable scheduler |
| dispatch failure 过多 | drain DSQ | revoke dispatch modification | disable scheduler |
| starvation risk | force dispatch | fallback scheduler | disable scheduler |

### 12.3 Paging Degrade

| 触发条件 | Level 1 | Level 2 | Level 3 |
|---|---|---|---|
| refault ratio 超预算 | throttle demote | revoke demote | kernel default reclaim |
| pages touched 超预算 | sampling decision | ignore hints | revoke paging policy |
| fault latency 过高 | disable demotion for hot region | revoke demote | kernel default reclaim |

---

## 13. 最关键实验：单一 Killer Story

不要设计太多分散实验。所有实验围绕一个主故事：

> **Latency-sensitive service under memory pressure。**

场景：

```text
service-A 是 latency-sensitive workload
BPF scheduler 试图降低 service-A latency
BPF paging policy 试图减少 service-A memory footprint
两个 policy 单独运行都合理
组合后产生 refault storm + tail latency spike
ContractBPF-Ledger 检测 ledger debt 并 revoke demote effect
```

---

## 14. 实验组

| 组别 | 配置 | 预期结果 |
|---|---|---|
| G1 | native scheduler + native paging | baseline |
| G2 | BPF scheduler only | latency 改善 |
| G3 | BPF paging only | memory footprint 改善 |
| G4 | BPF scheduler + BPF paging | 出现冲突 |
| G5 | static policy checker only | 部分冲突无法处理 |
| G6 | ContractBPF-Ledger | 检测、降级、恢复 |
| G7 | ContractBPF-Ledger without runtime ledger | ablation |
| G8 | ContractBPF-Ledger without degrade | ablation |

---

## 15. 评测指标

| 指标 | 作用 |
|---|---|
| P50/P99/P999 latency | 证明 tail latency 是否被保护 |
| major fault rate | 证明 paging 冲突 |
| refault ratio | 证明 demotion 是否错误 |
| scheduler queue delay | 证明调度影响 |
| pages demoted per epoch | 证明 effect 是否被限制 |
| fallback activation latency | 证明降级是否及时 |
| recovery time | 证明系统是否真正恢复 |
| steady-state overhead | 证明性能可接受 |
| policy throughput | 证明 contract enforcement 没有显著降低吞吐 |

---

## 16. Baseline 设计

### 16.1 必做 Baseline

```text
native eBPF + verifier
native sched_ext
PageFlex-style paging
KRAKENGUARD-style static policy checker
ContractBPF-Ledger
```

### 16.2 可选 / 定性 Baseline

```text
AEE
MOAT
HIVE
Rex / Rax
```

原因：

- **KRAKENGUARD** 是最接近的 baseline，因为它做 policy-driven constraints 和 cross-program interference。
- **AEE** 主要处理 verifier soundness bug 下的 spatial memory safety。
- **MOAT/HIVE** 主要处理隔离。
- **Rex/Rax** 是 safe-language kernel extension 路线。

ContractBPF-Ledger 必须强调：

```text
它处理的是 verified but harmful policy composition。
```

---

## 17. 与现有工作的差异

| 工作类型 | 代表 | 主要目标 | ContractBPF-Ledger 的差异 |
|---|---|---|---|
| Verifier | Linux eBPF verifier | 局部内存/控制流安全 | 不替代 verifier，处理 verifier 之后的资源效应 |
| Static policy checker | KRAKENGUARD | helper/memory/return value/cross-program policy | 处理 runtime resource-effect debt 与跨子系统反馈 |
| Runtime memory safety | AEE | verifier bug 下的 spatial memory safety | 处理 resource-effect safety，不主打 memory safety |
| Isolation | MOAT/HIVE | 隔离 BPF 代码与内核 | 约束合法 BPF 对调度/分页资源的 effect |
| Safe language | Rex/Rax | 用 safe Rust 替代部分 eBPF/verifier 复杂性 | 保留 eBPF 生态，处理多 policy 组合运行问题 |

---

## 18. 推荐实现路线

### Phase 1：模型与 Threat Model，3 周

产出：

```text
effect token 定义
ledger 状态机
bounded degrade 策略
cross-subsystem conflict case
paper motivation draft
```

---

### Phase 2：sched_ext Effect Gate，5–6 周

产出：

```text
contract-aware scx scheduler
enqueue / dispatch / select_cpu guard
queue-delay ledger
boost-rate ledger
scheduler degrade controller
```

成功标准：

```text
native sched_ext 能跑
ContractBPF sched_ext 能跑
queue-delay 违规可检测
boost effect 可 throttle / revoke
fallback 后系统稳定
```

---

### Phase 3：PageFlex-style Paging Hook，6–8 周

产出：

```text
BPF paging decision hook
read-only folio / region state summary
demote / reclaim_hint effect gate
refault ledger
paging degrade controller
```

成功标准：

```text
BPF 可以返回 paging decision
ContractBPF 可以限制 demote effect
hot-page demotion storm 可以被检测
fallback 后 refault rate 下降
```

---

### Phase 4：Cross-subsystem Ledger，4–5 周

产出：

```text
cgroup / memcg unified scope mapping
cross_effect_score
scheduler-paging coupled rule
runtime violation event stream
```

核心规则：

```text
same service scope:
  boost_task + demote_page + refault_ratio high + queue_delay high
  => revoke demote_page
```

---

### Phase 5：Static Composition Checker，4 周

产出：

```text
contract manifest parser
scope overlap checker
effect conflict matrix
fallback availability checker
```

---

### Phase 6：实验与 Ablation，6–8 周

产出：

```text
killer experiment
baseline comparison
ablation study
overhead measurement
fallback timeline
```

---

### Phase 7：论文与 Artifact，5–6 周

产出：

```text
paper draft
artifact scripts
benchmark harness
reproducibility package
camera-ready cleanup
```

---

## 19. 总体时间估计

| 团队情况 | 时间 |
|---|---:|
| 2 名强系统学生 | 7–10 个月 |
| 普通系统团队 | 10–14 个月 |
| 单人推进 | 12–18 个月 |

---

## 20. 风险与降级方案

### 风险 1：MM hook 太难

降级方案：

```text
只做 paging decision hook，不直接改 MM 状态。
BPF returns decision; kernel validates and executes.
```

### 风险 2：runtime overhead 太高

降级方案：

```text
1. 只在 effect boundary 检查。
2. 使用 per-CPU counter。
3. 使用 epoch-level accounting。
4. 对部分指标采用 sampling。
5. 静态预计算 token 与 scope mapping。
```

### 风险 3：被 KRAKENGUARD 压住 novelty

解决方式：

```text
强调 runtime state-dependent resource-effect debt。
不要把 contribution 写成 helper allowlist 或 static checker。
```

对比写法：

| KRAKENGUARD | ContractBPF-Ledger |
|---|---|
| load-time policy checking | runtime resource-effect accounting |
| helper / memory / return value | scheduler / paging effect |
| cross-program static interference | cross-subsystem dynamic feedback |
| symbolic execution | ledger + budget + bounded degrade |
| 防止不合规 BPF 加载 | 让已加载合法 BPF 可控运行并可恢复 |

### 风险 4：双子系统仍然太散

解决方式：

所有实验围绕同一个场景：

```text
latency-sensitive service under memory pressure
```

不要在论文里展示很多 unrelated workloads。主线必须始终是：

```text
scheduler wants lower latency
paging wants lower memory footprint
two policies conflict
ledger detects resource debt
degrade restores stability
```

---

## 21. 论文贡献写法

英文版：

```text
1. We identify resource-effect conflicts among verifier-accepted BPF policies as a new safety problem in BPF-programmable kernel subsystems.

2. We introduce effect tokens and per-scope resource ledgers to account for scheduling and paging effects across shared resource scopes.

3. We design effect-boundary enforcement and bounded degradation, enabling ContractBPF-Ledger to revoke harmful effects without killing the entire BPF policy.

4. We implement ContractBPF-Ledger on Linux with sched_ext and a PageFlex-style paging hook, and show that it prevents scheduler-paging conflicts with low steady-state overhead.
```

中文版：

```text
1. 提出 verifier-accepted BPF policy 之间的资源效应冲突问题。

2. 设计 effect token 与 per-scope resource ledger，用于统一记录调度与分页 effect。

3. 在 effect boundary 做低开销 enforcement，并支持 effect-level bounded degrade。

4. 在 sched_ext 与 PageFlex-style paging 上实现原型，证明其能阻断调度—分页组合冲突。
```

---

## 22. 推荐论文 Abstract 草稿

```text
eBPF is increasingly used to program core kernel policies such as scheduling and paging.
Existing verifier, isolation, and language-based approaches protect local memory and control-flow safety,
but they do not reason about the dynamic resource effects of independently loaded BPF policies.

This paper presents ContractBPF-Ledger, a resource-effect accounting system for BPF-programmable kernel policies.
ContractBPF-Ledger grants effect tokens to BPF policies, records scheduling and paging effects in per-scope resource ledgers,
and enforces budgets at effect boundaries rather than at every BPF instruction.
When a policy exceeds its resource budget or triggers a cross-subsystem feedback loop, ContractBPF-Ledger performs bounded degradation,
such as throttling an effect, revoking page demotion, or falling back to the kernel default policy.

We implement ContractBPF-Ledger on Linux using sched_ext and a PageFlex-style paging hook.
Our evaluation shows that it prevents verifier-accepted scheduler and paging policies from forming harmful resource-effect conflicts,
while preserving low steady-state overhead.
```

---

## 23. CCF-A 评分

| 维度 | 评分 | 说明 |
|---|---:|---|
| 问题重要性 | 9.0 | eBPF 进入调度和分页主路径，问题真实且及时 |
| Novelty | 8.5 | effect token + ledger + degrade 比单纯 contract 更硬 |
| 可实现性 | 8.6 | 双子系统范围可控，不改 verifier，不做 transport |
| 实验可讲性 | 8.8 | 单一 killer story 清晰 |
| 与现有工作区分 | 8.6 | 避开 AEE/MOAT/HIVE/Rex 的核心叙事 |
| 风险控制 | 8.0 | MM 仍有风险，但可通过 decision hook 降级 |
| CCF-A 命中潜力 | 8.4–8.6 | 若实验扎实，有较强冲击力 |

最终评分：

```text
8.5 / 10
```

---

## 24. 最终建议

建议采用 **ContractBPF-Ledger** 版本，而不是原始的 ContractBPF 大平台版本。

### 做什么

```text
1. 只做 sched_ext + paging。
2. 主打 verifier-accepted BPF policies 的 resource-effect conflict。
3. 提出 effect token。
4. 提出 per-scope resource ledger。
5. 在 effect boundary 做 runtime enforcement。
6. 实现 bounded degrade。
7. 用 latency-sensitive service under memory pressure 作为唯一 killer story。
```

### 不做什么

```text
1. 不替代 verifier。
2. 不主做 transport。
3. 不直接暴露危险 MM 对象给 BPF。
4. 不把 contract 降级成 helper allowlist。
5. 不把论文写成通用 BPF 安全平台。
```

### 一句话总结

> **ContractBPF-Ledger 不试图替代 verifier，也不做通用 BPF 隔离；它解决的是 verifier-accepted BPF policies 在调度和分页主路径中产生的动态资源效应冲突。核心机制是 effect token、per-scope resource ledger 和 bounded degrade。**

