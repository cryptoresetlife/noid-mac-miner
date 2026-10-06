# NOID Miner for Apple Silicon

开源 NOID Mac 矿工，支持 **CPU、Metal GPU、CPU + GPU**，默认连接 InnovLab 香港矿池（TLS / PPLNS）。实验版 **0.3.0**。

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
- 已在 M4 Max 测试；M2 Max 尚未完成实机验证，算力因芯片、温度、电源和其他负载而异。
- M4 Max 同条件 GPU 基准：0.2 版 **2.56 MH/s**，0.3 版 **3.75 MH/s**，提升约 **46%**（8,388,608 次哈希，包含调度时间）。
- 矿池 CPU + GPU 短时实测：CPU **1.97 MH/s**，GPU **3.53 MH/s**，合计约 **5.50 MH/s**。CPU 和 GPU 都收到接受回执；测试结束后两个进程正常退出。
- 以上是短样本，不是长期收益保证，也不声称达到社区所说的 40 MH/s。

## 收益、停止与隐私

应用不收取开发者费。矿池费用与 PPLNS 规则由矿池决定；接受份额不等于立刻得到币。页面 24 小时算力需要足够运行时间。

点击「停止挖矿」、关闭最后一个窗口或退出程序均停止挖矿。普通打开不会自动开挖，不随开机启动。网络失败或非过期份额拒绝时，相应矿工停止并显示原因；处理后可以点击停止，再开始。

软件没有预置收款钱包、不收集私钥、不包含远程管理功能或遥测。你填入的公开地址仅保存在本机 UserDefaults，并发送给矿池用于收益归属；运行日志只保留在窗口内。矿池能看到连接 IP、钱包和生成的 worker 名。分享截图或日志前请自己遮盖钱包。

## 源码编译

仅开发者需要 Xcode Command Line Tools、Git 和 [rustup](https://rustup.rs/)。在 Apple Silicon Mac：

```bash
xcode-select --install
rustup toolchain install 1.96.0 --profile minimal
bash build-app.command
python3 test-gpu.py  # 可选：256 个哈希与严格目标比较验证
```

脚本会从公开的上游仓库下载固定提交，不启动挖矿。产物在 `dist/`。官方 CPU 源码固定于 [proof-native/parano1d](https://github.com/proof-native/parano1d) 的 `d1a7e8b0816b29029e2066bf9a974253bb4a07c8`（2.0.2）；Cargo.lock 固定依赖。

`App.swift` 是 SwiftUI 界面，`Engine.swift` 管理 TLS Stratum 与进程，`MetalMiner.swift` 调度 GPU，`noid.metal` 实现哈希，`oracle` 使用上游 CPU 实现生成查表并校验候选。每个 GPU 候选提交前独立 CPU 校验；启动时另做哈希一致性检查。

GF 平方、32 位乘法、tower 状态及查表优化不改变共识哈希。测试包含随机/零 header、nonce 边界、CPU/GPU 候选集合与目标相等时拒绝。

本项目不是 InnovLab 或 INVminer 官方产品。Apache-2.0 开源；保留上游 LICENSE 与 NOTICE。
