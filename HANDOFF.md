# 交接说明（换机器时先看这个）

> 本文件用于在 macOS ↔ Windows 之间切换开发机时保留上下文。
> 会话记录本身**不会跨机器同步**（DeepSeek Harness 的会话存在本机 `~/.dsh/sessions/`），
> 所以关键决策和进度都写在这里。

## 一句话

把 [moqlivecast](https://github.com/runner365/moqlivecast)（自研 C 版 QUIC/HTTP3/WebTransport + MoQ）移植到
**QNX 8.0**，做成"弱网实时视频不阻塞控制回路"的遥操作回传单元，参加 QNX Global Hackathon。

## 赛事关键信息

| 项 | 内容 |
|---|---|
| 截止 | 2026-12-15 14:00 ET = **北京时间 12-16 03:00**（约 6 周） |
| 赛道 | **Robotics & Medical**（不报 Open-Source & Ports：上游是自己，PR 自引用会被扣分） |
| 追加目标 | **Best Use of QNX-specific Technologies（$3,500）**——资源管理器 / pulses / APS / HAM / 启动定制 |
| 备选目标 | Best Codelab（$3,500），写 QNX 交叉编译教程，可不相关于本项目 |
| 评审四项（等权） | Technological Implementation / Design（要"完整产品"，不是 PoC）/ Potential Impact / Innovation & AI Creativity |
| 硬要求 | 提交期内新建仓库、公开、About 处能识别 LICENSE、<3 分钟 YouTube 视频、构建说明 |

## 已完成

- [x] QNX Everywhere 许可申请并部署：`sweibd@gmail.com`（Dashboard 状态 Deployed）
- [x] 本仓库骨架（port 层 / toolchain / scripts / docs），本地已 commit，**尚未 push 到 GitHub**
- [x] 技术路线确定：接缝切在 **C SDK**（`moq_transport_client/`），QNX 只跑发布端（路线 A）
- [x] 证据方案确定：QEMU 开发、RPi5 出数字；视频源用"预录素材 + 时间戳叠加"，**不依赖摄像头**

## 环境决策

| 机器 | 角色 |
|---|---|
| **Windows 小新（Intel）** | 主力编译机：WSL2 + Ubuntu 22.04 x86_64，装 QNX SDP |
| Mac（Apple Silicon） | 编辑、浏览器播放端、录屏剪辑；**不能装 SDP** |

原因：QNX SDP 不支持 ARM 宿主、不支持 macOS。
腾讯云那台 2C1.8G/40G 太小（QSC 会 OOM），只能当弱网中间盒用。

## 下一步（W1）

1. Windows：`wsl --install -d Ubuntu-22.04` → `uname -m` 必须是 `x86_64`
2. 下载 QSC（Linux Hosts 包）：<https://www.qnx.com/download/group.html?programid=29178>
3. 安装并激活：
   ```bash
   ./qnx-setup-lin.run force-override disable-auto-start agree-to-license-terms ~/qnxinstall
   cd ~/qnxinstall/qnxsoftwarecenter
   ./qnxsoftwarecenter_clt -syncLicenseKeys -myqnx.user=sweibd@gmail.com -myqnx.password=*** -activateAll -listLicenseKeys
   ./qnxsoftwarecenter_clt -cleanInstall -destination ~/qnx800 -installBaseline com.qnx.sdp/8.0 -myqnx.user=... -myqnx.password=...
   ```
4. 验收：`source ~/qnx800/qnxsdp-env.sh && qcc -Vgcc_ntox86_64 -o /tmp/h /tmp/h.c && file /tmp/h`
   → 出现 `ELF 64-bit ... x86-64` 即通过
5. 通过后：用 `-c` 只编译不链接，探 libuv / OpenSSL / yaml-cpp 的依赖边界

## 赛事材料

Devpost 的全部字段、Project Story 草稿、Gallery 计划、视频脚本都记在
[`docs/devpost-submission.md`](docs/devpost-submission.md)，后续讨论直接改那个文件。

## 尚未验证（风险）

- libuv 1.51+ 的 QNX 8 支持在目标上的实际行为（上游 PR #4801 已合并，但没在 QNX 8.0.2 上验过）
- OpenSSL / yaml-cpp 在 QNX 上的构建方式（qnx-ports 没有 yaml-cpp 配方）
- RPi5 的 QNX 镜像与网络配置

## 在新机器上恢复

```bash
git clone <本仓库 URL> && cd moqlivecast-qnx
./scripts/bootstrap.sh    # 按 URL 拉上游 @ pinned commit，再打 patches/
```
