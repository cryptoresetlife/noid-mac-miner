# NOID Miner for Apple Silicon

开源 NOID Mac 矿工，支持 **CPU、Metal GPU、CPU + GPU**，默认连接 InnovLab 香港矿池（TLS / PPLNS）。实验版 **0.4.0**。

## 0.4 新增负载控制和自动重连

- **CPU 线程数**：1 到本机逻辑处理器数；默认 4（小于 4 的机器使用实际数量）。开始前选择，运行中先停止再调整。Rayon 线程池实际线程数会被检查。
- **GPU 强度**：10%–100%，默认 70%，支持运行中调整。通过批次间歇控制目标计算占空比，数值不是活动监视器利用率、GPU 核心数或瓦数限制；算力会随降低强度而减少。
- **系统过热自动降载**：默认打开。系统报告 serious 时 CPU 和 GPU 计算占空比最多 50%；critical 时暂停计算、保留连接，系统状态恢复后继续。遵循 [Apple 系统热状态 API](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html)，不读取 SMC 温度、不控制风扇，不代表恒温保证。
- **自动重连**：仅临时断网、连接关闭、握手/无消息超时自动重连，退避 2、4、8、16、30 秒，最高 30 秒。每次重新订阅和认证，领取新的 nonce 命名空间，不提交旧会话份额。稳定工作 30 秒后重置退避。
- **手动停止优先**：停止或退出立即取消计算间歇和重连等待，不会自动重新开挖。钱包认证失败、未知协议、非过期份额拒绝或 CPU/GPU 校验失败仍停止，不用重连掩盖错误。
- **停止原因和日志**：界面保留停止原因，单个后端结束会显示「部分运行」。「导出诊断日志」保存最近最多 150 行，并自动隐藏钱包；分享前仍请自己检查。

发热较高时可先尝试 **CPU 2–4 线程 + GPU 50%–70%**，再按设备响应调整。照片中的传感器温度不能单独证明停止原因；0.3 没有按温度停止的功能，但网络断开会让矿工退出。

## 下载后使用

1. 在本仓库 **Releases** 下载 `NOID-Miner-AppleSilicon.zip`，不是 GitHub 的 Source code ZIP。
2. 解压，把 `NOID Miner.app` 拖入「应用程序」，双击打开。
3. 填入自己的 NOID 收款地址（`o1` 开头）。**不需要私钥、助记词或注册账号**。
4. 选择 GPU / CPU / CPU + GPU，点击「开始挖矿」。
5. 出现「矿池已接受份额」表示矿池已接受工作量；收益和付款在 [InnovLab](https://noid.innovlab.cc/#miners) 输入自己的钱包查询。

安装包已包含运行组件，无需安装 Rust、Python、Xcode 或运行终端命令。首次 GPU 启动会编译 Metal 内核并比对官方 CPU 哈希，请稍等。

**当前为临时签名，未经过 Apple 公证。** 如果 macOS 阻止打开，在「系统设置 → 隐私与安全性」按系统提供的「仍要打开」流程确认你下载的是本仓库版本。无需关闭系统安全保护。若希望完全无提示分发，需要维护者用 Apple Developer ID 签名和公证；当前没有这样的证书。

## 设备与性能

- Apple Silicon M 系列，macOS 13 及以上；不支持 Intel Mac、Windows 或 NVIDIA GPU。
- 已在 M4 Max 测试，算力因芯片、温度、电源和其他负载而异。
- M4 Max 同条件 GPU 基准：0.2 版 **2.56 MH/s**，0.3 版 **3.75 MH/s**，提升约 **46%**（8,388,608 次哈希，包含调度时间）。
- 0.3 版矿池 CPU + GPU 短时实测：CPU **1.97 MH/s**，GPU **3.53 MH/s**，合计约 **5.50 MH/s**。CPU 和 GPU 都收到接受回执；测试结束后两个进程正常退出。0.4 默认降低线程数和 GPU 强度，默认算力会相应降低。

## 收益、停止与隐私

应用不收取开发者费。矿池费用与 PPLNS 规则由矿池决定；接受份额不等于立刻得到币。页面 24 小时算力需要足够运行时间。

点击「停止挖矿」、关闭最后一个窗口或退出程序均停止挖矿。普通打开不会自动开挖，不随开机启动。临时网络错误自动重连；非过期份额拒绝等校验错误仍停止。两个后端相互独立，一个停止不会伪装成两者均正常。

软件没有预置收款钱包、不收集私钥、不包含远程管理功能或遥测。你填入的公开地址仅保存在本机 UserDefaults，并发送给矿池用于收益归属；运行日志只保留在窗口内。矿池能看到连接 IP、钱包和生成的 worker 名。分享截图或日志前请自己遮盖钱包。

## 源码编译

仅开发者需要 Xcode Command Line Tools、Git 和 [rustup](https://rustup.rs/)。在 Apple Silicon Mac：

```bash
xcode-select --install
rustup toolchain install 1.96.0 --profile minimal
bash build-app.command
python3 test-gpu.py  # 可选：256 个哈希与严格目标比较验证
xcrun swiftc -O TestPolicy.swift Engine.swift -o bin/test-policy -framework Network -framework Foundation
bin/test-policy  # 离线负载策略、重连退避、手动停止验证，不开挖
```

脚本会从公开的上游仓库下载固定提交，不启动挖矿。产物在 `dist/`。官方 CPU 源码固定于 [proof-native/parano1d](https://github.com/proof-native/parano1d) 的 `d1a7e8b0816b29029e2066bf9a974253bb4a07c8`（2.0.2）；Cargo.lock 固定依赖。

`App.swift` 是 SwiftUI 界面，`Engine.swift` 管理 TLS Stratum 与进程，`MetalMiner.swift` 调度 GPU，`noid.metal` 实现哈希，`oracle` 使用上游 CPU 实现生成查表并校验候选。每个 GPU 候选提交前独立 CPU 校验；启动时另做哈希一致性检查。

GF 平方、32 位乘法、tower 状态及查表优化不改变共识哈希。测试包含随机/零 header、nonce 边界、CPU/GPU 候选集合与目标相等时拒绝。

`TestPool.swift` 是可选的矿池集成测试，需要自行设置 `NOID_TEST_WALLET` 并传入安装包的 miner 资源目录。它临时运行 CPU 2 线程和 GPU 50% 强度，在得到接受回执后模拟断连，验证新会话继续接受份额及手动停止不再重连；最长 240 秒，然后退出。测试不含任何预置钱包，不是常驻监控。

本项目不是 InnovLab 或 INVminer 官方产品。Apache-2.0 开源；保留上游 LICENSE 与 NOTICE。
