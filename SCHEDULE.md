# 参赛日程（截至 2026-12-15）

> 截止：**2026-12-15 14:00 ET = 北京时间 12-16 03:00**
> 目标提交日：**12-13**（留 2 天缓冲）
> 赛道：**Open-Source Contribution & Ports（OSP）**
> 追加目标：Best Use of QNX-specific Technologies（$3,500）

---

## 当前进度（2026-11-10）

| 项 | 状态 |
|---|---|
| QNX SDP 8.0 环境（香港 Ubuntu） | ✅ |
| libuv 1.53 / yaml-cpp / OpenSSL 3.5.8 交叉编译 | ✅ |
| C SDK 编译出 `libmoq_transport_client.a` | ✅ |
| `flv2moqtransport_client` 可执行文件 | ✅ |
| QNX → 公网服务器 → 浏览器 端到端推流 | ✅（用 HTTP-FLV + flv.js 播放正常） |
| WebCodecs 播放器 A/V 同步 | ❌ 已知问题，用 flv.js 规避 |
| 补丁固化 | ⬜ |
| qnx-ports 生态贡献 | ⬜ |
| 测量数据 | ⬜ |
| 文档 / 视频 / 提交 | ⬜ |

---

## 第 1 周（11/10 – 11/16）：收口 + 转向赛道

| 任务 | 产出 | 预计 |
|---|---|---|
| 确认赛道改为 OSP，更新 Devpost 字段 | 表单已改 | 5 min |
| `git diff` 固化补丁到 `patches/` | `0001..000N.patch` | 半天 |
| 更新 `docs/02-porting-notes.md`（把实战坑表补齐） | 文档 | 2 h |
| 写 `docs/05-why-moq.md`（MoQ vs WebRTC/RTMP 论点 + 实验映射） | 文档 | 半天 |
| 研究 qnx-ports 配方格式（读 `ports/libuv`、`ports/libyaml`） | 笔记 | 半天 |

**周末检查点**：补丁能一键 bootstrap 应用，文档能自洽解释"为什么值得做"。

---

## 第 2 周（11/17 – 11/23）：生态贡献（OSP 赛道的核心证据）

| 任务 | 产出 | 预计 |
|---|---|---|
| 写 yaml-cpp 的 qnx-ports 配方并本地验证 | 可构建的 port 目录 | 1 天 |
| 给 `qnx-ports/build-files` 提 PR | **真实 PR URL** | 半天 |
| OpenSSL 3.5 配方（含 QUIC、`qcc-nodep` 处理） | port 目录 + 说明 | 2–3 天 |
| 提 PR 或在 issue 中先讨论 | PR/issue URL | 半天 |

**周末检查点**：至少 1 个 PR 已提交（哪怕未合并，URL 就是证据）。

> 这两个配方是本赛道最硬的加分项：`qnx-ports` 现有 151 个 port 里**没有 openssl，也没有 yaml-cpp**。

---

## 第 3 周（11/24 – 11/30）：测量与 QNX 特性

| 任务 | 产出 | 优先级 |
|---|---|---|
| 服务器侧加到达时间日志，算 QNX→服务器延迟 | CSV + 统计 | P0 |
| 弱网对比：RTMP(6%) vs MoQ(10%/25%) | 连接存活表 | P0 |
| 长跑 10 分钟，算 `latency_delta` | 不累积证据 | P1 |
| `/dev/moq` 资源管理器（`devctl` 查统计） | `moq_rm.c` | P1（专项奖） |
| APS 分区 + `pidin` 截图 | 截图 | P1（专项奖） |

**周末检查点**：有三组可信数字 + 至少一个 QNX 原生组件。

---

## 第 4 周（12/01 – 12/07）：产品化与材料

| 任务 | 产出 |
|---|---|
| 配置/启动脚本/状态查询（`moqctl status`） | 可交付的产品形态 |
| README 重写（按评委 5 分钟能看懂的顺序） | README |
| Gallery 素材（架构图、`pidin`、曲线、trace） | 6–8 张 3:2 图 |
| 拍摄 demo 视频（≤3 分钟，YouTube public） | 视频 URL |

---

## 第 5 周（12/08 – 12/14）：提交

| 日期 | 任务 |
|---|---|
| 12/08–12/10 | 填 Devpost 全部字段（名称、pitch、story、built with、gallery、视频） |
| 12/11 | 自查：仓库公开、LICENSE 可识别、构建说明可复现 |
| **12/12–12/13** | **点 Submit**（不要等到最后一天） |
| 12/14–12/15 | 缓冲，只处理意外 |

---

## 关键风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| OpenSSL 配方比预期复杂 | 第 2 周 PR 提不出 | 先提 yaml-cpp（简单），OpenSSL 降级为 issue + 文档 |
| 播放器 A/V 不同步 | demo 不好看 | 已用 flv.js 规避 |
| 测量数据不理想 | 论证变弱 | 重点放在"不累积/不断连"，不主打绝对延迟 |
| 时间不够 | 提交不完整 | 12/10 起停止开发，只做包装 |

---

## 每周固定动作

- 周日：更新本文件的状态列
- 每次踩坑：立刻写进 `docs/02-porting-notes.md`（否则会忘）
- 每完成一个里程碑：`git commit` + `push`（换机器不丢）
