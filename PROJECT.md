# AWS Clickstream Platform — 项目文档

**作者**：Hao Lin ｜ **目标**：2027 北美暑期 Data / Platform Engineering 实习
**定稿**：2026-10-06 ｜ 来源：舰队编排流程（GPT-5.6 Sol 设计 → Claude Opus 跨厂商审查 → orchestrator GATE）

---

## 零、这个项目要解决什么问题

**不是为了证明你会数据处理**——那个你有三年生产经历。它要解决两件具体的事：

1. **关键词可见性**：你的技术栈（StarRocks / Paimon / DolphinScheduler / Celeborn）在北美认知度低，
   ATS 和 recruiter 的布尔筛选抓不到你。这个项目提供 AWS / Terraform / CI-CD / Snowflake / dbt / Airflow 这组词。
2. **能力可迁移的证据**：向对方证明你那套能力在托管云栈上同样成立，而不是只在中国大厂的自研环境里成立。

**贯穿业务域**：应用分发 / 广告点击流 `impression → click → install → activation/payment`。
三个阶段共用同一套事件协议和业务键。

**面试叙事**（三阶段通用）：
> "同类架构我在约 100 亿事件/日的生产场景做过，这是可公开复现的 AWS 版本。"

**总量**：70–110 小时，现金支出 $12–24（非硬上限）。顺序固定 1 → 2 → 3。

---

## 一、第一阶 · 云上骨架（`v0.1`，24–34 小时）

**向招聘方证明**：能独立部署、管控并销毁一套 AWS 托管实时数据栈，不依赖平台团队。

### 架构

```
Python producer → Kinesis Data Streams → Managed Service for Apache Flink
                                              ↓
                                       S3 (Iceberg) ← Glue Data Catalog
                                              ↓
                                           Athena
控制面：Terraform · GitHub Actions (OIDC) · least-privilege IAM · CloudWatch · Budgets + Budget Action
```

**第一阶直接用 Iceberg，不要先写 Parquet 再迁。** 这是审查挑出来的：
Parquet → Iceberg 的跳跃需要额外的 connector 和 catalog 配置，白白多一道迁移成本。

### 1.1 骨架版（前 4–6 小时，做完就能上简历）

**不接任何数据**，只把环境立起来。这是整个项目里投入产出比最高的一段。

#### 仓库结构

```
aws-clickstream-platform/
├── README.md                    ← 第一个 commit 就要有，链接先活起来
├── .gitignore                   ← *.tfstate* / .terraform/ / *.tfvars
├── Makefile                     ← make plan / apply / destroy / nuke
├── .github/workflows/ci.yml
├── infra/
│   ├── bootstrap/               ← 一次性，用本地 state 跑一次
│   │   └── main.tf
│   ├── backend.tf               ← S3 remote state
│   ├── main.tf
│   ├── budget.tf
│   ├── variables.tf
│   └── outputs.tf
└── docs/
    └── architecture.md
```

#### 第一步：bootstrap（约 1.5 小时，最容易卡）

| 资源 | 要点 |
|---|---|
| `aws_s3_bucket` 存 tfstate | 版本控制 + 服务端加密 + `block_public_access` 全开；桶名全局唯一，带随机后缀 |
| state 锁 | 新版 Terraform 支持 S3 原生锁，可省掉 DynamoDB。**先确认版本**，不确定就建 `aws_dynamodb_table` |
| `aws_iam_openid_connect_provider` | 对应 `token.actions.githubusercontent.com`；AWS 现已不强制校验 thumbprint |
| `aws_iam_role` 给 CI | **信任策略的 `sub` 钉死到 `repo:<你>/<repo>:ref:refs/heads/main`**，不要用通配符 |

> 这一步是骨架里唯一会耗几小时的地方，OIDC 信任策略第一次配基本都要试几轮。
> 建议先在 CI 里跑一次 `aws sts get-caller-identity` 验明身份再往下做。

#### 第二步：主栈（约 1 小时）

| 资源 | 说明 |
|---|---|
| `aws_s3_bucket` 数据湖 | `raw/` `curated/` 两个前缀，生命周期 7 天，加密 + 禁公开 |
| `aws_glue_catalog_database` | 免费，先建着 |
| `aws_kinesis_stream` | 按需模式；平时 destroy，演示时再建 |
| `aws_cloudwatch_log_group` | 保留 3 天 |
| provider `default_tags` | `project` / `env` / `owner`，后面做成本归因全靠它 |

#### 第三步：成本护栏（约 0.5 小时，区分度最高）

```hcl
aws_budgets_budget        # 月度 $30，50/80/100% 三档通知
aws_budgets_budget_action # 触发时给目标角色附加 Deny 策略
aws_iam_role              # budgets 服务用的执行角色
```

**为什么这条值钱**：绝大多数个人项目只配告警。
面试时你可以说清「Budgets **只告警不阻断**，而且账单延迟数小时、窗口内仍在计费，所以我加了 Action」。

#### 第四步：CI（约 1 小时）

`.github/workflows/ci.yml`，PR 触发：

```yaml
permissions:
  id-token: write     # OIDC 必须
  contents: read
```

顺序：`checkout` → **gitleaks 扫密钥** → `terraform fmt -check` →
`configure-aws-credentials`（OIDC，**不放任何长期 Access Key**）→ `init` + `validate` →
`plan -no-color` → plan 作为 artifact 上传。

**不要配自动 apply。** plan 给人看、apply 手动触发，这本身是个能讲的工程判断。

#### 第五步：README（约 1 小时，别省）

调研结论：招聘经理基本不看源码，**只看 README**。所以这部分投入产出比最高。

1. **架构图**（Mermaid 即可，GitHub 直接渲染）
2. **为什么选 Kinesis 不选 MSK** —— 带价格对照 `$0.04/h` vs `$0.75/h`
3. **安全边界** —— OIDC 短期凭证、最小权限、state 加密、密钥扫描，每条一句
4. **成本控制** —— Budget Action、标签、生命周期、一键销毁，附账单截图
5. **本地复现步骤** —— 别人 clone 下来能跑
6. **路线图** —— 三阶段复选框，当前进度一目了然

#### 骨架版验收（全过了才动简历）

- `make apply` exit 0；`make destroy` exit 0，控制台资源清单为空
- CI 在一个 PR 上全绿
- gitleaks 零发现
- `git ls-files | grep tfstate` **必须为空**
- README 有架构图
- 公开 release `v0.0.1`，说明是 infrastructure skeleton

### 1.2 第一阶完整版（剩余 20–28 小时）

在骨架之上接通数据流：producer 造点击流 → Kinesis → Managed Flink → S3/Iceberg → Athena 可查。

**工时分解**（已计入审查指出的隐藏成本）：

| 项 | 小时 |
|---|---|
| 基础设施 | 12–16 |
| 首次 IAM / OIDC 调通 | 4–6 |
| **Flink 部署迭代**（打包 → 传 S3 → 改配置 → 等 2–10 分钟） | 4–8 |
| README、截图、release | 2–4 |

> **Flink 部署迭代是真正的时间黑洞**，不是写代码慢。提前知道这件事能少一次挫败。

**验收**：端到端数据一致（Athena 行数与 producer manifest 相符）；README 内嵌架构图标明数据流、
控制面和安全边界；tfstate 走加密版本化 S3；CI 跑 `fmt/validate/plan` + gitleaks；
交付 3 分钟 demo 视频、Release、一条 LinkedIn 帖。

**成本**：Flink 最小约 `2 KPU + 1 编排 KPU = $0.33/小时`，运行 6–10 小时，总计 **$4–8**。
忘关一夜约 $8，所以要设定时销毁 + 每日巡检。

**简历原句**（v0.1 上线当天就加进 PROJECTS）：

```
Built a reproducible AWS clickstream platform with Kinesis, Managed Flink, Iceberg, Terraform,
GitHub Actions OIDC, least-privilege IAM, and automated security and cost guardrails.
```

**面试会问**：
1. 为什么用 Kinesis 不用 MSK？→ 流量规模、运维面、`$0.04/h` vs `$0.75/h`
2. CI 如何安全访问 AWS？→ OIDC 短期凭证、`sub` 钉死到分支、最小权限
3. 个人项目怎么防止烧钱？→ Budget Action、标签、生命周期、一键销毁 + 账单证据

---

## 二、第二阶 · 可靠流处理（`v0.2`，24–38 小时）

**向招聘方证明**：能把生产级流处理能力迁到 AWS，并用测试和故障记录证明正确性。

> **这一阶是你的主场**：乱序、迟到、watermark、exactly-once 正是 2026 年流式岗面试的核心题。
> 已核实的关键表述：**端到端 exactly-once = 可重放 source + checkpoint 进度 + 幂等/事务性 sink**。
> 如果时间紧，这一阶可以降成第一阶之上的 `v0.1.x` 附加项（4–6 小时注入异常 + 一次恢复记录）。

### 架构

沿用第一阶的 Iceberg。新增：

- producer 注入**重复、乱序、迟到、多版本 Avro** 事件
- **Glue Schema Registry** 管兼容性
- Flink：event-time watermark、状态去重、checkpoint
- 坏数据 → S3 **DLQ**
- CloudWatch 指标与告警

### 工时

| 项 | 小时 |
|---|---|
| 逻辑与 fixture | 10–14 |
| connector / Catalog、恢复、性能 | 8–12 |
| Flink 部署等待与排错 | 4–8 |
| README、截图、release | 2–4 |

### 验收

- 固定 seed 的基线数据 + expected output 入库
- 测试覆盖：重复、迟到、乱序、兼容与不兼容的 schema drift
- **强制重启 Flink 后从 checkpoint 恢复**，用业务键、manifest、一致性 SQL 证明无丢失无重复
- 公布吞吐、p95 延迟、恢复时间、DLQ 数量
- 更新架构图；交付 3 分钟 demo、Release、LinkedIn 帖

### 成本

运行 16–28 小时，Flink `$5.3–9.2`，总计 **$7–13**。限制 KPU/shard、日志保留 3 天、测完即销毁。

### 简历原句

```
Hardened an AWS Managed Flink pipeline for out-of-order and late events, stateful deduplication,
schema evolution, DLQ routing, and checkpoint recovery, validated through deterministic
fault-injection tests.
```

### 面试会问

1. watermark 和允许迟到怎么定？→ 基线分布 + 丢弃/延迟的权衡
2. checkpoint 恢复后怎么证明没重复没丢失？→ manifest、唯一键、一致性 SQL
3. schema 不兼容怎么办？→ 兼容规则、隔离、告警、重放流程

---

## 三、第三阶 · 分析工程（`v1.0`，22–38 小时）

**向招聘方证明**：具备 Snowflake 仓内建模、dbt 数据测试、Airflow 编排能力。
**这是你现在完全空白的一块，也是北美 JD 出现频率最高的组合。**

### 架构

```
S3 点击流批次 → Airflow (本地 Docker) → Snowflake staging → dbt
                                                              ├ incremental facts
                                                              ├ dimensions（snapshot 做 SCD2）
                                                              └ marts
dbt tests: unique / not_null / relationships / freshness
dbt docs + lineage 发布
```

### 治理（这部分才是 Snowflake 岗位的区分点）

- **RBAC**：`LOADER` / `TRANSFORMER` / `ANALYST` 三个角色
- **warehouse 隔离**：ingest 与 transform 分开
- **成本归因**：`QUERY_TAG` + query history + warehouse metering，按 release / DAG / 环境归因

### 工时

| 项 | 小时 |
|---|---|
| 三件新工具首次安装与认证 | 6–10 |
| 加载与编排 | 6–10 |
| 建模、SCD2、tests、docs | 6–10 |
| README、截图、release | 2–4 |
| 排错 | 2–4 |

### 验收

- `dbt build` exit 0；snapshot 与 docs 可验证
- Airflow DAG 正常执行、失败重试、指定日期 backfill 成功
- 重跑同一批次不增重复行；故意注入坏数据时测试**必须失败**
- 展示越权失败、warehouse 隔离、成本报表
- 交付架构图、3 分钟 demo、Release、LinkedIn 帖

### 成本

**Snowflake 试用是 30 天 / $400 credits —— 不要提前注册，真正开始第三阶的前一天再开。**
X-Small warehouse + 60 秒 auto-suspend + 批量 `COPY`（不用常驻 Snowpipe）。
试用期内 Snowflake 现金 **$0**，AWS 侧 $1–3。

### 简历原句

```
Built a Snowflake analytics workflow orchestrated by Airflow, using dbt incremental models,
dimensional marts with SCD2 snapshots, lineage documentation, data-quality tests, idempotent
loads, and backfills.
```

### 面试会问

1. incremental model 怎么保证幂等？→ 批次键、`unique_key`、merge、重跑测试
2. Airflow 和 dbt 怎么分工？→ 跨系统编排 vs 仓内转换
3. Snowflake 成本怎么控？→ X-Small、auto-suspend、批处理、query history

---

## 四、每个阶段都不能省的四件事

审查结论：验收标准全是 exit code 和 CI 绿，**但这些只有在有人去看时才有价值**。所以每阶段必须交付：

1. **README 架构图**（不是"README 含架构"，是真的有图）
2. **3 分钟 demo 视频**
3. **公开 Release**
4. **一条 LinkedIn 帖** —— 这是项目唯一能改变「零回应」的传导路径

另外：**`v0.1` 一上线立刻进简历 PROJECTS 栏，不要等 `v1.0`。** 招聘窗口 11 月–1 月就满了。

---

## 五、和教程项目的区别（README 里要写清楚）

| 教程项目的特征 | 本项目的做法 |
|---|---|
| 用清洗好的玩具数据（Titanic / Iris / Kaggle） | 生成可复现的重复、乱序、迟到、坏记录、多版本 schema |
| 只跑通 happy path | 每阶都有重试、DLQ、幂等、checkpoint 恢复、失败测试 |
| 堆砌技术名词 | README 记录三组取舍：Kinesis vs MSK、批量加载 vs Snowpipe、本地 Airflow vs MWAA |
| 缺工程证据 | 每阶独立 release：CI、测试输出、故障记录、性能基线、账单截图、可重复销毁命令 |

---

## 六、会卡住你的坑

- **OIDC 信任策略的 `sub` 写错**最常见 —— 先在 CI 跑 `aws sts get-caller-identity` 验身份
- **S3 桶名全局唯一** —— 被占了 apply 会中途失败，留下半截资源
- **Budget Action 需要单独的执行角色** —— 忘了建会报权限错
- **Kinesis 按需有最低计费** —— 别建了放着不管
- **Flink 部署迭代慢** —— 这是时间黑洞，不是你写代码慢，提前有心理准备
- **AWS Budgets 只告警不阻断**，且延迟数小时 —— 真要硬控必须配 Budget Action

---

## 七、进度追踪

- [ ] `v0.0.1` 骨架：Terraform + OIDC + CI + Budget Action（4–6h）→ **简历加 PROJECTS 栏**
- [ ] `v0.1` 第一阶完整：数据流通，Athena 可查（剩余 20–28h）→ 简历换完整描述 + LinkedIn 帖
- [ ] `v0.2` 第二阶：异常注入、checkpoint 恢复、DLQ（24–38h，时间紧可降为附加项）
- [ ] `v1.0` 第三阶：Snowflake + dbt + Airflow（22–38h）→ 注册 Snowflake 试用的时机在这一步前一天
