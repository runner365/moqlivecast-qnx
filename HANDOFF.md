# 交接说明（换机器时先看这个）

> 本文件用于在 macOS ↔ Windows ↔ 云主机之间切换时保留上下文。
> 会话记录**不会跨机器同步**（DeepSeek Harness 的会话存在本机 `~/.dsh/sessions/`），
> 所以关键决策、环境路径和进度都写在这里。

## 一句话

把 [moqlivecast](https://github.com/runner365/moqlivecast)（自研 C 版 QUIC/HTTP3/WebTransport + MoQ）移植到
**QNX 8.0**，做成"弱网实时视频不阻塞控制回路"的遥操作回传单元，参加 QNX Global Hackathon。

## 赛事关键信息

| 项 | 内容 |
|---|---|
| 截止 | 2026-12-15 14:00 ET = **北京时间 12-16 03:00** |
| 赛道 | **Robotics & Medical**（不报 Open-Source & Ports：上游是自己，PR 自引用会被扣分） |
| 追加目标 | **Best Use of QNX-specific Technologies（$3,500）**——资源管理器 / pulses / APS / HAM / 启动定制 |
| 备选目标 | Best Codelab（$3,500），写 QNX 交叉编译教程，可不相关于本项目 |
| 评审四项（等权） | Technological Implementation / Design（要"完整产品"，不是 PoC）/ Potential Impact / Innovation & AI Creativity |
| 硬要求 | 提交期内新建仓库、公开、About 处能识别 LICENSE、<3 分钟 YouTube 视频、构建说明 |

## 已完成（W1）

- [x] QNX Everywhere 许可申请、部署、激活（License key 已在服务器上）
- [x] QNX SDP 8.0 安装于香港云主机
- [x] **交叉编译双架构验证**：`qcc -Vgcc_ntox86_64` 和 `-Vgcc_ntoaarch64le` 均产出
      `interpreter /usr/lib/ldqnx-64.so.2` 的 QNX ELF
- [x] **QNX 8.0 在 QEMU 中启动成功**（`QNX noname 8.0.0 ... x86pc x86_64`）
- [x] **部署通道打通**：QEMU slirp 网络，QNX 内 `curl http://10.0.2.2:8000/...` 拉取二进制，
      实测 ELF 传输并执行成功
- [x] 技术路线：接缝切在 **C SDK**（`moq_transport_client/`），QNX 只跑发布端（路线 A）
- [x] 证据方案：QEMU 开发、RPi5 出数字；视频源用"预录素材 + 时间戳叠加"，**不依赖摄像头**

## 环境（已验证可用）

### 编译机：香港云主机（Ubuntu 22.04, x86_64, 4C8G/100G）

```bash
source ~/qnx800/qnxsdp-env.sh     # 已写入 ~/.bashrc
qcc --version                     # QNX 8.0.3 工具链

~/qnx/qnxsoftwarecenter/qnxsoftwarecenter_clt   # QSC CLI
# 注意：baseline id 是 com.qnx.qnx800，不是 com.qnx.sdp/8.0
```

装 SDP 时踩过的坑：`-mirror` 首次会因 seed repo 不存在报
`Request requires authorization`，需要在 GUI 里登录一次（或重试）后 seed repo 才被创建；
之后 `-mirror`（拉全量，含 target 包）才能成功，否则 `-installBaseline` 会报
`Missing requirement: com.qnx.qnx800.target`。

### QNX 目标：QEMU（同一台服务器）

```bash
cd ~/vm
qemu-system-x86_64 -smp 2 -cpu max -m 1G \
  -drive file=output/disk-qemu.vmdk,if=ide,id=drv0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:26:ea:44 \
  -kernel output/ifs.bin \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0 \
  -nographic
```

- 控制台登录：`root`（无密码）
- **不要用 mkqnximage 自带的网桥方案**：云主机不允许建桥，`brctl`/`dnsmasq` 那套走不通，用上面的 slirp
- 退出 QEMU：`Ctrl-A` 然后 `X`

### 部署二进制（当前唯一通道）

```bash
# 编译机
mkdir -p ~/share && cp build/xxx ~/share/
cd ~/share && python3 -m http.server 8000

# QNX 控制台
mkdir -p /data/moq && cd /data/moq
curl -o xxx http://10.0.2.2:8000/xxx && chmod +x xxx && ./xxx
```

### 已知限制

- **sshd 起不来**：QNX 镜像缺 `/usr/libexec/sshd-auth`，且 `/usr` 是只读 IFS，无法在运行时补。
  修法只有一个：重建镜像时把该文件打进 `/usr/libexec/`（`mkqnximage --copy` 或等价方式）。
  不阻塞开发——用上面的 curl 通道即可。
- `/system`、`/usr` 只读；`/data` 可写。二进制、配置、日志一律放 `/data/`。
- 云主机无嵌套虚拟化，QEMU 走 TCG，启动 1–3 分钟。最终性能数据必须来自 RPi5。

## 下一步（W2）：编译 C SDK

1. 取代码
   ```bash
   cd ~ && git clone https://github.com/runner365/moqlivecast-qnx.git
   cd moqlivecast-qnx && ./scripts/bootstrap.sh
   ```
2. 先做单个文件的编译探针（挑不依赖 libuv/OpenSSL 的）：
   ```bash
   source ~/qnx800/qnxsdp-env.sh
   qcc -Vgcc_ntox86_64 -c -I upstream/quic -o /tmp/probe.o upstream/quic/quic_packet.c
   ```
3. 按 `quic/` → `http3/` → `moq_transport_client/` 的顺序往上撞，
   每发现一处 Linux 特有依赖就记进 [`docs/02-porting-notes.md`](docs/02-porting-notes.md)

## 赛事材料

Devpost 的全部字段、Project Story 草稿、Gallery 计划、视频脚本都记在
[`docs/devpost-submission.md`](docs/devpost-submission.md)，后续讨论直接改那个文件。

## 尚未验证（风险）

- libuv 1.51+ 的 QNX 8 支持在目标上的实际行为（上游 PR #4801 已合并，但没在 QNX 8.0.3 上验过）
- OpenSSL / yaml-cpp 在 QNX 上的构建方式（qnx-ports 没有 yaml-cpp 配方）
- RPi5 的 QNX 镜像与网络配置

## 在新机器上恢复

```bash
git clone https://github.com/runner365/moqlivecast-qnx.git && cd moqlivecast-qnx
./scripts/bootstrap.sh    # 按 URL 拉上游 @ pinned commit，再打 patches/
```
